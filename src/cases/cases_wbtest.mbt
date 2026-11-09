///|
fn rejects(
  text : String,
  field : String,
  allow_write~ : Bool = false,
) -> Unit raise {
  try {
    parse_cases(text, allow_write~) |> ignore
    fail("expected invalid input")
  } catch {
    InvalidInput(line, actual, reason) => {
      assert_eq(actual, field)
      assert_true(line >= 0)
      assert_false(reason.contains("PRIVATE"))
    }
    other => raise other
  }
}

///|
fn rejects_origin(origin : String) -> Unit raise {
  try {
    validate_origin(origin) |> ignore
    fail("expected invalid origin")
  } catch {
    InvalidInput(line, field, reason) => {
      assert_eq(line, 0)
      assert_eq(field, "origin")
      assert_false(reason.contains("PRIVATE"))
    }
    other => raise other
  }
}

///|
test "positive cases preserve body distinctions and line numbers" {
  let cases = parse_cases(
    "\n{\"id\":\"hello-1.x_2\",\"method\":\"GET\",\"path\":\"/v1?q=two%20words&x=%2F\",\"headers\":{\"Accept\":\"application/json\"}}\r\n \t\n{\"id\":\"null\",\"method\":\"HEAD\",\"path\":\"/\",\"body\":null}\n{\"id\":\"text\",\"method\":\"GET\",\"path\":\"/\",\"body_text\":\"\"}\n",
  )
  assert_eq(cases.length(), 3)
  assert_eq(cases[0].source_line, 2)
  assert_eq(cases[1].source_line, 4)
  assert_true(cases[0].body is None)
  assert_true(cases[1].body is Some(JsonBody(Null)))
  assert_true(cases[2].body is Some(TextBody("")))
  assert_true(
    cases[0].headers.get("accept") is Some(Literal("application/json")),
  )
}

///|
test "methods and write opt in" {
  for meth in ["POST", "PUT", "PATCH", "DELETE", "OPTIONS"] {
    let text = "{\"id\":\"x\",\"method\":\"\{meth}\",\"path\":\"/\"}"
    rejects(text, "method")
    assert_eq(parse_cases(text, allow_write=true)[0].meth, meth)
  }
  for meth in ["get", "CONNECT", "TRACE", "", "GET PRIVATE"] {
    rejects(
      "{\"id\":\"x\",\"method\":\"\{meth}\",\"path\":\"/\"}",
      "method",
      allow_write=true,
    )
  }
}

///|
test "ids are unique stable bounded ascii tokens" {
  for id in ["", "-x", ".x", "_x", "two words", "é", "x/y", "x:PRIVATE"] {
    rejects("{\"id\":\"\{id}\",\"method\":\"GET\",\"path\":\"/\"}", "id")
  }
  let id64 = Array::make(64, "x").join("")
  assert_eq(
    parse_cases("{\"id\":\"\{id64}\",\"method\":\"GET\",\"path\":\"/\"}")[0].id.length(),
    64,
  )
  rejects("{\"id\":\"\{id64}x\",\"method\":\"GET\",\"path\":\"/\"}", "id")
  let row = "{\"id\":\"same\",\"method\":\"GET\",\"path\":\"/\"}"
  rejects("\{row}\n\{row}", "id")
}

///|
test "strict objects types and recursive duplicate keys" {
  rejects("", "input")
  rejects(" \n\r\n\t", "input")
  for text in ["[]", "null", "1", "\"PRIVATE\""] {
    rejects(text, "case")
  }
  for text in ["{", "{\"PRIVATE\":", "{} PRIVATE"] {
    rejects(text, "json")
  }
  rejects(
    "{\"id\":\"x\",\"method\":\"GET\",\"path\":\"/\",\"PRIVATE\":1}", "case",
  )
  for
    text in [
      "{\"id\":\"x\",\"id\":\"y\",\"method\":\"GET\",\"path\":\"/\"}", "{\"id\":\"x\",\"method\":\"GET\",\"path\":\"/\",\"body\":{\"PRIVATE\":1,\"PRIVATE\":2}}",
      "{\"id\":\"x\",\"method\":\"GET\",\"path\":\"/\",\"headers\":{\"X\":{\"env\":\"A\",\"env\":\"B\"}}}",
      "{\"id\":\"x\",\"method\":\"GET\",\"path\":\"/\",\"headers\":{\"X\":\"a\",\"\\u0058\":\"b\"}}",
    ] {
    rejects(text, "json")
  }
  rejects("{}", "id")
  rejects("{\"id\":false}", "id")
  rejects("{\"id\":\"x\"}", "method")
  rejects("{\"id\":\"x\",\"method\":\"GET\"}", "path")
  rejects("{\"id\":\"x\",\"method\":\"GET\",\"path\":null}", "path")
  rejects(
    "{\"id\":\"x\",\"method\":\"GET\",\"path\":\"/\",\"headers\":null}", "headers",
  )
  rejects(
    "{\"id\":\"x\",\"method\":\"GET\",\"path\":\"/\",\"body_text\":null}", "body_text",
  )
  rejects(
    "{\"id\":\"x\",\"method\":\"GET\",\"path\":\"/\",\"body\":null,\"body_text\":\"\"}",
    "body",
  )
}

///|
test "path injection and malformed encoding" {
  for
    path in [
      "", "https://PRIVATE.test/", "//PRIVATE.test/", "relative", "/#PRIVATE", "/ PRIVATE",
      "/%", "/%1", "/%GG", "/%0d", "/%0A", "/%00", "/%1f", "/%7F", "/%5c", "/%5C",
    ] {
    rejects("{\"id\":\"x\",\"method\":\"GET\",\"path\":\"\{path}\"}", "path")
  }
  for
    path_json in [
      "\"/\\\\PRIVATE\"", "\"/\\t\"", "\"/\\u007f\"", "\"/\\u0085\"",
    ] {
    rejects("{\"id\":\"x\",\"method\":\"GET\",\"path\":\{path_json}}", "path")
  }
}

///|
test "headers enforce token names controls credential and protocol rules" {
  for
    headers in [
      "{\"Bad Name\":\"PRIVATE\"}", "{\"\":\"PRIVATE\"}", "{\"A:B\":\"PRIVATE\"}",
      "{\"X\":\"PRIVATE\\r\\nInjected: yes\"}", "{\"X\":\"PRIVATE\\t\"}", "{\"X\":\"PRIVATE\\u007f\"}",
      "{\"X\":1}", "{\"X\":null}", "{\"X\":[]}", "{\"X\":\"a\",\"x\":\"b\"}", "{\"Authorization\":\"PRIVATE\"}",
      "{\"X-Auth-Token\":\"PRIVATE\"}", "{\"X-API-Key\":\"PRIVATE\"}",
    ] {
    rejects(
      "{\"id\":\"x\",\"method\":\"GET\",\"path\":\"/\",\"headers\":\{headers}}",
      "headers",
    )
  }
  for
    name in [
      "Host", "Content-Length", "Transfer-Encoding", "Connection", "Cookie", "Proxy-Authorization",
      "Proxy-Authenticate", "Keep-Alive", "TE", "Trailer", "Upgrade",
    ] {
    rejects(
      "{\"id\":\"x\",\"method\":\"GET\",\"path\":\"/\",\"headers\":{\"\{name}\":{\"env\":\"TOKEN\"}}}",
      "headers",
    )
  }
  for
    reference in [
      "{}", "{\"env\":\"TOKEN\",\"PRIVATE\":true}", "{\"env\":\"bad-name\"}", "{\"env\":\"1BAD\"}",
      "{\"env\":\"\"}", "{\"env\":null}", "{\"env\":false}",
    ] {
    rejects(
      "{\"id\":\"x\",\"method\":\"GET\",\"path\":\"/\",\"headers\":{\"X\":\{reference}}}",
      "headers.env",
    )
  }
}

///|
test "environment checking and plans never expose sensitive fields" {
  let cases = parse_cases(
    "\n{\"id\":\"safe\",\"method\":\"GET\",\"path\":\"/PRIVATE?token=PRIVATE\",\"headers\":{\"Authorization\":{\"env\":\"PRIVATE_TOKEN\"},\"X-Note\":\"PRIVATE\"},\"body_text\":\"PRIVATE\"}",
  )
  assert_eq(render_plan(cases), ["safe GET headers=2 body=text"])
  validate_env(cases, { "PRIVATE_TOKEN": "Bearer PRIVATE" })
  for
    env in [
      {},
      { "PRIVATE_TOKEN": "" },
      { "PRIVATE_TOKEN": "PRIVATE\r\n" },
      { "PRIVATE_TOKEN": "PRIVATE\t" },
    ] {
    try {
      validate_env(cases, env)
      fail("expected environment error")
    } catch {
      InvalidInput(line, field, reason) => {
        assert_eq(line, 2)
        assert_eq(field, "headers.env")
        assert_false(reason.contains("PRIVATE"))
      }
      other => raise other
    }
  }
}

///|
test "case count and exact UTF8 byte limits" {
  let rows = Array::makei(100, fn(i) {
    "{\"id\":\"case\{i}\",\"method\":\"GET\",\"path\":\"/\"}"
  })
  assert_eq(parse_cases(rows.join("\n")).length(), 100)
  rows.push("{\"id\":\"overflow\",\"method\":\"GET\",\"path\":\"/\"}")
  rejects(rows.join("\n"), "input")
  let prefix = "{\"id\":\"x\",\"method\":\"GET\",\"path\":\"/\",\"body_text\":\""
  let suffix = "\"}"
  let padding = max_line_bytes - prefix.length() - suffix.length()
  let exact = prefix + "x".repeat(padding) + suffix
  assert_eq(@utf8.encode(exact).length(), max_line_bytes)
  assert_eq(parse_cases(exact).length(), 1)
  rejects(exact + " ", "input")
  // Blank lines count toward the file byte budget but not the case count.
  let exact_file = exact + "\n".repeat(max_file_bytes - max_line_bytes)
  assert_eq(@utf8.encode(exact_file).length(), max_file_bytes)
  assert_eq(parse_cases(exact_file).length(), 1)
  rejects(exact_file + "\n", "input")
  // Characters are UTF-16 code units, so the encoder must enforce bytes, not length.
  let multibyte = prefix + "界".repeat(padding / 2) + suffix
  assert_true(multibyte.length() < max_line_bytes)
  rejects(multibyte, "input")
  let file_multibyte = prefix + "界".repeat(max_file_bytes / 2) + suffix
  assert_true(file_multibyte.length() < max_file_bytes)
  rejects(file_multibyte, "input")
}

///|
test "origin normalization and supported hosts" {
  for
    (input, expected) in [
      ("http://localhost", "http://localhost"),
      ("HTTPS://Example.COM/", "https://example.com"),
      ("http://127.0.0.1:1/", "http://127.0.0.1:1"),
      ("https://example.test:65535", "https://example.test:65535"),
      ("http://localhost:00080", "http://localhost:80"),
      ("http://[::1]:8080/", "http://[::1]:8080"),
      ("https://[2001:DB8:0:0:0:0:0:1]", "https://[2001:db8:0:0:0:0:0:1]"),
      ("http://[::ffff:192.0.2.1]", "http://[::ffff:192.0.2.1]"),
      ("http://[::]", "http://[::]"),
      ("http://a-b.example", "http://a-b.example"),
    ] {
    assert_eq(validate_origin(input), expected)
  }
}

///|
test "origin rejects credentials paths malformed hosts ports and IPv6" {
  for
    origin in [
      "", "ftp://PRIVATE.test", "//PRIVATE.test", "http://", "http://PRIVATE@host",
      "http://user:PRIVATE@host", "http://host/path", "http://host//", "http://host/?PRIVATE",
      "http://host#PRIVATE", "http://host?PRIVATE", "http://host ", "http://host\t",
      "http://host\r\n", "http://host\\PRIVATE", "http://host/%2f", "http://host:",
      "http://host:0", "http://host:65536", "http://host:-1", "http://host:1x", "http://host:9999999999999999999999999999999",
      "http://bad_host", "http://-bad.test", "http://bad-.test", "http://bad..test",
      "http://.test", "http://test.", "http://é.test", "http://999.1.1.1", "http://127.1",
      "http://0177.0.0.1", "http://2130706433", "http://0x7f.0.0.1", "http://123",
      "http://example.123", "http://[::1", "http://::1", "http://[:::1]", "http://[1::2::3]",
      "http://[1:2:3:4:5:6:7]", "http://[1:2:3:4:5:6:7:8:9]", "http://[1:2:3:4:5:6:7::8]",
      "http://[gg::1]", "http://[12345::1]", "http://[fe80::1%25eth0]", "http://[::1]PRIVATE",
      "http://[::1]:", "http://[::1]]", "http://[192.0.2.1::]", "http://[::ffff:999.0.0.1]",
    ] {
    rejects_origin(origin)
  }
}
