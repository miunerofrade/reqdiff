// Native product integration tests. Every listener owns a dynamic IPv4 loopback
// port; fixtures and credentials are synthetic. No TLS test adapter is needed.

///|
fn wb_origin(server : @socket.TcpServer) -> String {
  "http://127.0.0.1:\{server.addr.port()}"
}

///|
async fn wb_request_head(tcp : @socket.Tcp) -> String {
  match tcp.read_until(b"\r\n\r\n", include_delimiter=true) {
    Some(bytes) => @utf8.decode(bytes)
    None => fail("runner did not send a complete request header")
  }
}

///|
async fn wb_no_connection(server : @socket.TcpServer) -> Unit {
  try
    @async.with_timeout(50) <| () => {
      let (tcp, _) = server.accept()
      defer tcp.close()
      fail("unexpected connection: preflight, ordering or fail-fast violated")
    }
  catch {
    @async.TimeoutError => ()
    error => raise error
  }
}

///|
async fn wb_expect_failure(
  base : String,
  reason : String,
  timeout_ms~ : Int32 = 1000,
) -> Unit {
  // The later case must never execute; leading blanks test source coordinates.
  let text =
    #|
    #|
    #|{"id":"broken","method":"GET","path":"/broken?PRIVATE=1"}
    #|{"id":"later","method":"GET","path":"/must-not-run"}
  try {
    let _ = run_with_deadline(text, base, {}, false, timeout_ms)
    fail("expected the first request to fail")
  } catch {
    Failed(line, actual) => {
      assert_eq(line, 3)
      assert_eq(actual, reason)
    }
    error => raise error
  }
}

///|
async test "runner sends all methods with env headers and exact UTF-8 bodies" {
  @async.with_timeout(5000) <| () => {
    @async.with_task_group() <| group => {
      let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      let methods : Array[@http.RequestMethod] = [
        Get,
        Head,
        Post,
        Put,
        Patch,
        Delete,
        Options,
      ]
      let paths = [
        "/get?q=two%20words&slash=%2F", "/head", "/json", "/text", "/null", "/empty",
        "/options",
      ]
      let bodies = [
        b"",
        b"",
        @utf8.encode("{\"v\":\"雪\"}"),
        @utf8.encode("é\r\nlocal"),
        b"null",
        b"",
        b"",
      ]
      let content_types : Array[String?] = [
        None,
        None,
        Some("application/json"),
        Some("text/plain; charset=utf-8"),
        Some("application/vnd.reqdiff+json"),
        Some("text/plain; charset=utf-8"),
        None,
      ]
      let seen : Array[String] = []
      group.spawn_bg() <| () => {
        for i, meth in methods {
          let (tcp, _) = server.accept()
          let conn = @http.ServerConnection::new(tcp)
          defer conn.close()
          let request = conn.read_request()
          assert_eq(request.meth, meth)
          assert_eq(request.path, paths[i])
          assert_eq(request.headers.get("content-type"), content_types[i])
          assert_eq(
            request.headers.get("accept-encoding"),
            Some(if i == 4 { "gzip" } else { "identity" }),
          )
          if i == 0 {
            assert_eq(request.headers.get("X-Fixture"), Some("literal value"))
            assert_eq(
              request.headers.get("authorization"),
              Some("Bearer PUBLIC_TEST"),
            )
            assert_eq(request.headers.get("accept"), Some("application/json"))
          }
          if i >= 2 && i <= 5 {
            assert_eq(
              request.headers.get("content-length"),
              Some(bodies[i].length().to_string()),
            )
          }
          assert_eq(conn.read_all(), bodies[i])
          seen.push(request.path)
          if i == 1 {
            // HEAD advertises more than the cap, but has no response entity.
            tcp.write(
              b"HTTP/1.1 200 OK\r\nContent-Length: 1048577\r\nConnection: close\r\n\r\n",
            )
          } else {
            tcp.write(
              b"HTTP/1.1 201 Created\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok",
            )
          }
        }
      }
      let text =
        #|{"id":"GET","method":"GET","path":"/get?q=two%20words&slash=%2F","headers":{"X-Fixture":"literal value","Authorization":{"env":"PUBLIC_TEST_TOKEN"},"Accept":"application/json"}}
        #|{"id":"HEAD","method":"HEAD","path":"/head"}
        #|{"id":"POST","method":"POST","path":"/json","body":{"v":"雪"}}
        #|{"id":"PUT","method":"PUT","path":"/text","body_text":"é\r\nlocal"}
        #|{"id":"PATCH","method":"PATCH","path":"/null","body":null,"headers":{"cOnTeNt-TyPe":"application/vnd.reqdiff+json","aCcEpT-EnCoDiNg":"gzip"}}
        #|{"id":"DELETE","method":"DELETE","path":"/empty","body_text":""}
        #|{"id":"OPTIONS","method":"OPTIONS","path":"/options"}
      let results = run(
        text,
        wb_origin(server),
        { "PUBLIC_TEST_TOKEN": "Bearer PUBLIC_TEST" },
        allow_write=true,
      )
      assert_eq(results.length(), methods.length())
      assert_eq(seen, paths)
      for i, result in results {
        assert_eq(result.id, methods[i].to_string())
        assert_eq(result.meth, methods[i].to_string())
        assert_eq(result.status, if i == 1 { 200 } else { 201 })
        assert_eq(result.body_bytes, if i == 1 { 0 } else { 2 })
      }
    }
  }
}

///|
async test "runner waits for the whole response before starting the next case" {
  @async.with_timeout(5000) <| () => {
    @async.with_task_group() <| group => {
      let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      group.spawn_bg() <| () => {
        let (first, _) = server.accept()
        defer first.close()
        assert_true(
          wb_request_head(first).has_prefix("GET /first HTTP/1.1\r\n"),
        )
        first.write(b"HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\na")
        // A parallel runner would connect while the first body is incomplete.
        wb_no_connection(server)
        first.write(b"bcde")
        let (second, _) = server.accept()
        defer second.close()
        assert_true(
          wb_request_head(second).has_prefix("GET /second HTTP/1.1\r\n"),
        )
        second.write(b"HTTP/1.1 202 Accepted\r\nContent-Length: 3\r\n\r\nxyz")
      }
      let text =
        #|{"id":"first","method":"GET","path":"/first"}
        #|{"id":"second","method":"GET","path":"/second"}
      let results = run(text, wb_origin(server), {})
      assert_eq(results.length(), 2)
      for i, result in results {
        assert_eq(result.id, if i == 0 { "first" } else { "second" })
        assert_eq(result.meth, "GET")
        assert_eq(result.status, if i == 0 { 200 } else { 202 })
        assert_eq(result.body_bytes, if i == 0 { 5 } else { 3 })
      }
    }
  }
}

///|
async test "runner returns redirect and error statuses without following or retrying" {
  @async.with_timeout(5000) <| () => {
    @async.with_task_group() <| group => {
      let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      let seen : Array[String] = []
      group.spawn_bg() <| () => {
        for expected_path in ["/redirect", "/busy", "/missing"] {
          let (tcp, _) = server.accept()
          defer tcp.close()
          let conn = @http.ServerConnection::new(tcp)
          defer conn.close()
          let request = conn.read_request()
          assert_eq(request.path, expected_path)
          seen.push(request.path)
          match request.path {
            "/redirect" =>
              tcp.write(
                b"HTTP/1.1 302 Found\r\nLocation: /must-not-follow\r\nContent-Length: 4\r\n\r\nmove",
              )
            "/busy" =>
              tcp.write(
                b"HTTP/1.1 503 Unavailable\r\nRetry-After: 0\r\nContent-Length: 3\r\n\r\nerr",
              )
            "/missing" =>
              tcp.write(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n")
            _ => fail("redirect target must not be requested")
          }
          assert_eq(tcp.read(), None)
        }
      }
      let text =
        #|{"id":"redirect","method":"GET","path":"/redirect"}
        #|{"id":"busy","method":"GET","path":"/busy"}
        #|{"id":"missing","method":"GET","path":"/missing"}
      let results = run(text, wb_origin(server), {})
      assert_eq(results.length(), 3)
      for i, result in results {
        assert_eq(result.id, ["redirect", "busy", "missing"][i])
        assert_eq(result.meth, "GET")
        assert_eq(result.status, [302, 503, 404][i])
        assert_eq(result.body_bytes, [4, 3, 0][i])
      }
      assert_eq(seen, ["/redirect", "/busy", "/missing"])
      assert_eq(
        render_run(results),
        "RUN: 3 case(s); requests completed\nredirect GET status=302 bytes=4\nbusy GET status=503 bytes=3\nmissing GET status=404 bytes=0",
      )
    }
  }
}

///|
fn wb_sized_response(size : Int32, chunked : Bool) -> Bytes {
  let header = @utf8.encode(
    if chunked {
      let hex_size = if size == 1048576 { "100000" } else { "100001" }
      "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n\{hex_size}\r\n"
    } else {
      "HTTP/1.1 200 OK\r\nContent-Length: \{size}\r\n\r\n"
    },
  )
  // Send valid framing even for overflow; size alone must cause rejection.
  let tail = if chunked { b"\r\n0\r\n\r\n" } else { b"" }
  Bytes::makei(header.length() + size + tail.length(), i => {
    if i < header.length() {
      header[i]
    } else if i < header.length() + size {
      b'x'
    } else {
      tail[i - header.length() - size]
    }
  })
}

///|
async test "runner accepts empty and exact 1 MiB bodies but rejects fixed and chunked overflow" {
  @async.with_timeout(10000) <| () => {
    for
      fixture in [
        (0, false),
        (1048576, false),
        (1048576, true),
        (1048577, false),
        (1048577, true),
      ] {
      let (size, chunked) = fixture
      @async.with_task_group() <| group => {
        let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
        defer server.close()
        let response = wb_sized_response(size, chunked)
        group.spawn_bg() <| () => {
          let (tcp, _) = server.accept()
          defer tcp.close()
          assert_true(
            wb_request_head(tcp).has_prefix(
              "GET /broken?PRIVATE=1 HTTP/1.1\r\n",
            ),
          )
          tcp.write(response[:])
          // Overflow may close with a reset while chunk framing is unread.
          // The runner's exact limit error is asserted independently below.
          if size > max_response_bytes {
            let closed = try (tcp.read() is None) catch {
              _ => true
            }
            assert_true(closed)
          } else {
            assert_eq(tcp.read(), None)
          }
        }
        if size > max_response_bytes {
          wb_expect_failure(wb_origin(server), "response body exceeds 1 MiB")
          wb_no_connection(server)
        } else {
          let text =
            #|{"id":"sized","method":"GET","path":"/broken?PRIVATE=1"}
          let results = run(text, wb_origin(server), {})
          assert_eq(results.length(), 1)
          assert_eq(results[0].id, "sized")
          assert_eq(results[0].meth, "GET")
          assert_eq(results[0].status, 200)
          assert_eq(results[0].body_bytes, size)
        }
      }
    }
  }
}

///|
async test "runner short internal deadline covers delayed headers and unfinished body and closes client" {
  @async.with_timeout(5000) <| () => {
    for send_headers in [false, true] {
      let events : Array[String] = []
      @async.with_task_group() <| group => {
        let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
        defer server.close()
        group.spawn_bg() <| () => {
          let (tcp, _) = server.accept()
          defer {
            tcp.close()
            events.push("server closed")
          }
          assert_true(
            wb_request_head(tcp).has_prefix(
              "GET /broken?PRIVATE=1 HTTP/1.1\r\n",
            ),
          )
          events.push("request received")
          if send_headers {
            tcp.write(b"HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nx")
            events.push("partial body")
          }
          // No response (or body completion) until the product deadline fires.
          assert_eq(tcp.read(), None)
          events.push("client closed")
        }
        wb_expect_failure(
          wb_origin(server),
          "request timed out",
          timeout_ms=300,
        )
        wb_no_connection(server)
      }
      assert_eq(
        events,
        if send_headers {
          ["request received", "partial body", "client closed", "server closed"]
        } else {
          ["request received", "client closed", "server closed"]
        },
      )
    }
  }
}

///|
async test "runner rejects disconnect truncation and invalid HTTP without retry or later requests" {
  @async.with_timeout(5000) <| () => {
    let fixtures = [
      (b"", "invalid or incomplete HTTP response"),
      (
        b"HTTP/1.1 200 OK\r\nContent-Length: 8\r\n\r\nshort", "invalid or incomplete HTTP response",
      ),
      (
        b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nab", "invalid or incomplete HTTP response",
      ),
      (b"NOT-HTTP 200 Bad\r\n\r\n", "invalid or incomplete HTTP response"),
      (
        b"HTTP/1.1 101 Switching Protocols\r\n\r\n", "invalid or incomplete HTTP response",
      ),
      (
        b"HTTP/1.1 600 Invalid\r\nContent-Length: 0\r\n\r\n", "invalid or incomplete HTTP response",
      ),
      (
        b"HTTP/1.1 -1 Invalid\r\nContent-Length: 0\r\n\r\n", "invalid or incomplete HTTP response",
      ),
      (
        b"HTTP/1.1 200 OK\r\nmalformed-header\r\n\r\n", "invalid or incomplete HTTP response",
      ),
    ]
    for fixture in fixtures {
      let (response, reason) = fixture
      @async.with_task_group() <| group => {
        let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
        defer server.close()
        let seen : Array[String] = []
        group.spawn_bg() <| () => {
          let (tcp, _) = server.accept()
          defer tcp.close()
          assert_true(
            wb_request_head(tcp).has_prefix(
              "GET /broken?PRIVATE=1 HTTP/1.1\r\n",
            ),
          )
          seen.push("broken")
          if !response.is_empty() {
            tcp.write(response[:])
          }
          // EOF terminates these deliberately incomplete responses.
          tcp.close()
        }
        wb_expect_failure(wb_origin(server), reason)
        assert_eq(seen, ["broken"])
        wb_no_connection(server)
      }
    }
  }
}

///|
async test "runner preflights origin whole file write permission and env before any connection" {
  @async.with_timeout(5000) <| () => {
    let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let valid = "{\"id\":\"first\",\"method\":\"GET\",\"path\":\"/must-not-run\"}"
    let needs_env = "{\"id\":\"last\",\"method\":\"GET\",\"path\":\"/\",\"headers\":{\"Authorization\":{\"env\":\"PUBLIC_TEST_TOKEN\"}}}"
    let base = wb_origin(server)
    let fixtures : Array[
      (String, String, Map[String, String], Int32, String, String),
    ] = [
      (
        "\{valid}\n\n{",
        base,
        {},
        3,
        "json",
        "invalid JSON, duplicate key, or excessive nesting",
      ),
      (
        "\{valid}\n{\"id\":\"last\",\"method\":\"POST\",\"path\":\"/\"}",
        base,
        {},
        2,
        "method",
        "requires --allow-write",
      ),
      (
        "\{valid}\n\{needs_env}",
        base,
        {},
        2,
        "headers.env",
        "required environment variable is missing",
      ),
      (
        "\{valid}\n\{needs_env}",
        base,
        { "PUBLIC_TEST_TOKEN": "PUBLIC\r\ninjected: x" },
        2,
        "headers.env",
        "environment value contains a control character",
      ),
      (
        valid,
        "\{base}/forbidden",
        {},
        0,
        "origin",
        "expected a host and optional port only",
      ),
    ]
    for fixture in fixtures {
      let (text, origin, env, line, field, reason) = fixture
      try {
        let _ = run(text, origin, env)
        fail("expected preflight rejection")
      } catch {
        @cases.InvalidInput(actual_line, actual_field, actual_reason) => {
          assert_eq(actual_line, line)
          assert_eq(actual_field, field)
          assert_eq(actual_reason, reason)
        }
        error => raise error
      }
      // Accept probes the listening socket/backlog, not just a scheduled counter.
      wb_no_connection(server)
    }
  }
}
