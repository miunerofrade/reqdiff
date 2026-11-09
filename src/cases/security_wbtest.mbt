///|
test "every ASCII encoded control and mixed-case backslash is rejected" {
  let digits = "0123456789abcdef".to_array()
  for n = 0; n < 32; n = n + 1 {
    let escaped = "%\{digits[n / 16]}\{digits[n % 16]}"
    rejects(
      "{\"id\":\"x\",\"method\":\"GET\",\"path\":\"/ok?q=\{escaped}\"}",
      "path",
    )
  }
  rejects("{\"id\":\"x\",\"method\":\"GET\",\"path\":\"/%7f\"}", "path")
  rejects("{\"id\":\"x\",\"method\":\"GET\",\"path\":\"/%5C\"}", "path")
}

///|
test "JSON structured bodies remain opaque and arbitrary" {
  for
    body in [
      "null", "false", "true", "12.50", "\"PRIVATE\"", "[1,null]", "{\"arbitrary\":{\"unknown\":true}}",
    ] {
    let cases = parse_cases(
      "{\"id\":\"x\",\"method\":\"GET\",\"path\":\"/\",\"body\":\{body}}",
    )
    assert_true(cases[0].body is Some(JsonBody(_)))
    assert_eq(render_plan(cases), ["x GET headers=0 body=json"])
  }
}

///|
test "parse diagnostics are safe including duplicate key and malformed values" {
  for
    text in [
      "{\"PRIVATE_KEY\":0,\"PRIVATE_KEY\":1}", "{\"id\":\"PRIVATE ID\",\"method\":\"GET\",\"path\":\"/\"}",
      "{\"id\":\"x\",\"method\":\"GET\",\"path\":\"/PRIVATE#PRIVATE\"}", "{\"id\":\"x\",\"method\":\"GET\",\"path\":\"/\",\"headers\":{\"Authorization\":\"PRIVATE_VALUE\"}}",
    ] {
    try {
      parse_cases("\n\n" + text) |> ignore
      fail("expected invalid case")
    } catch {
      InvalidInput(line, _, _) as err => {
        assert_eq(line, 3)
        assert_false(err.to_string().contains("PRIVATE"))
        assert_true(err.to_string().contains("line 3"))
      }
      other => raise other
    }
  }
}

///|
test "deep JSON rejected safely and Unicode origins rejected conservatively" {
  let deep = "{\"id\":\"x\",\"method\":\"GET\",\"path\":\"/\",\"body\":" +
    "[".repeat(130) +
    "0" +
    "]".repeat(130) +
    "}"
  rejects(deep, "json")
  // Unicode case conversion must not accidentally admit compatibility host letters.
  rejects_origin("http://K.test")
  rejects_origin("http://host\u{00a0}")
  rejects_origin("http://host\u{0085}")
}
