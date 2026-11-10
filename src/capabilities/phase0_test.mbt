// Local native capability probes and product TLS rejection. No external hosts.
// All listeners bind IPv4 loopback with port 0; each test owns its resources.

///|
suberror BodyLimitExceeded {
  BodyLimitExceeded(Int32)
}

///|
// Fixed allocation, at most limit + 1 bytes read (one byte detects overflow).
// A production 1 MiB cap uses this same algorithm with limit = 1024 * 1024.
async fn bounded_body(client : @http.ClientConnection, limit : Int32) -> Bytes {
  let buffer = FixedArray::make(limit + 1, b'\x00')
  let mut used = 0
  while used <= limit {
    let count = client.read_into(buffer, offset=used, max_len=limit + 1 - used)
    if count == 0 {
      return Bytes::makei(used, i => buffer[i])
    }
    used += count
    if used > limit {
      raise BodyLimitExceeded(limit)
    }
  }
  abort("unreachable")
}

///|
async test "phase0 HTTP request and bounded response on dynamic loopback port" {
  @async.with_timeout(5000) <| () => {
    @async.with_task_group() <| group => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      group.spawn_bg() <| () => {
        let (conn, _) = server.accept()
        defer conn.close()
        let request = conn.read_request()
        assert_eq(request.meth, Post)
        assert_eq(request.path, "/phase0?local=1")
        assert_eq(request.headers.get("x-phase0"), Some("synthetic"))
        assert_eq(conn.read_all(), b"public fixture")
        conn.send_response(201, "Created")
        conn.write(b"local response")
        conn.end_response()
      }
      let client = @http.ClientConnection(
        "http://127.0.0.1:\{server.addr.port()}",
      )
      defer client.close()
      client.request(Post, "/phase0?local=1", extra_headers={
        "x-phase0": "synthetic",
      })
      client.write(b"public fixture")
      assert_eq(client.end_request().code, 201)
      // Exact-limit success also exercises the single-byte EOF probe.
      assert_eq(bounded_body(client, 14), b"local response")
    }
  }
}

///|
async test "phase0 response cap rejects overflow after limit plus one bytes" {
  @async.with_timeout(5000) <| () => {
    @async.with_task_group() <| group => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      group.spawn_bg() <| () => {
        let (conn, _) = server.accept()
        defer conn.close()
        let _ = conn.read_request()
        conn.send_response(200, "OK")
        conn.write(b"0123456789abcdefEXCESS")
        conn.end_response()
      }
      let client = @http.ClientConnection(
        "http://127.0.0.1:\{server.addr.port()}",
      )
      defer client.close()
      client.request(Get, "/overflow")
      assert_eq(client.end_request().code, 200)
      let rejected = try {
        let _ = bounded_body(client, 16)
        false
      } catch {
        BodyLimitExceeded(limit) => {
          assert_eq(limit, 16)
          true
        }
        error => raise error
      }
      assert_true(rejected)
    }
  }
}

///|
async test "phase0 whole request deadline cancels stalled response body and closes client" {
  let events : Array[String] = []
  @async.with_timeout(5000) <| () => {
    @async.with_task_group() <| group => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      group.spawn_bg(no_wait=true) <| () => {
        let (conn, _) = server.accept()
        defer {
          conn.close()
          events.push("server closed")
        }
        let _ = conn.read_request()
        conn.send_response(200, "OK")
        conn.write(b"partial")
        conn.flush()
        // Never finish this body. The enclosing task group must cancel us.
        @async.sleep(60000)
      }
      let timed_out = try {
        // Wrap connection establishment, request write, headers AND body read.
        @async.with_timeout(500) <| () => {
          let client = @http.ClientConnection(
            "http://127.0.0.1:\{server.addr.port()}",
          )
          defer {
            client.close()
            events.push("client closed")
          }
          client.request(Get, "/stall")
          assert_eq(client.end_request().code, 200)
          events.push("headers received")
          let _ = bounded_body(client, 32)
          events.push("unexpected completion")
        }
        false
      } catch {
        @async.TimeoutError => true
        error => raise error
      }
      assert_true(timed_out)
      assert_eq(events, ["headers received", "client closed"])
    }
  }
  assert_eq(events, ["headers received", "client closed", "server closed"])
}

///|
async test "phase0 async filesystem roundtrip with guaranteed cleanup" {
  let directory = @fs.tmpdir(prefix="reqdiff-phase0-")
  {
    defer @fs.rmdir(directory, recursive=true)
    let path = "\{directory}/public-fixture.txt"
    @fs.write_text(path, "synthetic public fixture\n", create_mode=CreateNew)
    assert_eq(@fs.read_text(path), "synthetic public fixture\n")
    assert_eq(@fs.read_binary(path), b"synthetic public fixture\n")
  }
  assert_false(@fs.exists(directory))
}

///|
// These files are deliberately PUBLIC synthetic credentials. Never use them
// outside tests. Windows Schannel needs the empty-password PKCS#12 fixture.
// SDK native server_from_pair is marked internal-testing-only. This probe is
// deliberately test-only; it does not endorse a production TLS server API.
// Suppress ONLY alert_internal on these two test fixture adapters; package and
// project warnings remain enabled, including --deny-warn. Windows uses Schannel
// PFX; Linux/macOS use the SDK OpenSSL backend with PEM (runtime not tested here).
#warnings("-alert_internal")
#cfg(platform="windows")
async fn local_tls_server(tcp : @socket.Tcp) -> @tls.Tls {
  @tls.Tls::server_from_pair(
    tcp,
    tcp,
    pfx_file="src/capabilities/fixtures/PUBLIC_TEST_ONLY.pfx",
  )
}

///|
#warnings("-alert_internal")
#cfg(not(platform="windows"))
async fn local_tls_server(tcp : @socket.Tcp) -> @tls.Tls {
  @tls.Tls::server_from_pair(
    tcp,
    tcp,
    private_key_file="src/capabilities/fixtures/PUBLIC_TEST_ONLY.key.pem",
    private_key_type=PEM,
    certificate_file="src/capabilities/fixtures/localhost.cert.pem",
    certificate_type=PEM,
  )
}

///|
async test "phase0 HTTPS trusts explicit local CA and reads HTTP response" {
  @async.with_timeout(10000) <| () => {
    @async.with_task_group() <| group => {
      let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      group.spawn_bg() <| () => {
        let (tcp, _) = server.accept()
        defer tcp.close()
        let tls = local_tls_server(tcp)
        defer tls.close()
        let request = tls.read_until(b"\r\n\r\n", include_delimiter=true)
        assert_true(request is Some(_))
        tls.write(
          b"HTTP/1.1 200 OK\r\nContent-Length: 9\r\nConnection: close\r\n\r\nlocal tls",
        )
        tls.shutdown()
      }
      // Numeric loopback avoids DNS / IPv6 ambiguity. The synthetic cert SAN
      // includes IP:127.0.0.1 and DNS:127.0.0.1 plus DNS:localhost. The
      // numeric DNS SAN accommodates this SDK's Linux SSL_set1_host path;
      // Windows Schannel uses the IP SAN. Both identities stay loopback-only.
      let client = @http.ClientConnection(
        "https://127.0.0.1:\{server.addr.port()}",
        trust=@tls.CustomPemFile("src/capabilities/fixtures/localhost.cert.pem"),
      )
      defer client.close()
      client.request(Get, "/tls")
      assert_eq(client.end_request().code, 200)
      assert_eq(bounded_body(client, 32), b"local tls")
    }
  }
}

///|
async test "phase0 HTTPS rejects unrelated local CA rather than disabling verification" {
  @async.with_timeout(10000) <| () => {
    @async.with_task_group() <| group => {
      let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      // Some TLS backends report the rejected handshake at the server too.
      group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
        let (tcp, _) = server.accept()
        defer tcp.close()
        let tls = local_tls_server(tcp)
        defer tls.close()
        let _ = tls.read()
      }
      let rejected = try {
        let client = @http.ClientConnection(
          "https://127.0.0.1:\{server.addr.port()}",
          trust=@tls.CustomPemFile(
            "src/capabilities/fixtures/unrelated.cert.pem",
          ),
        )
        defer client.close()
        false
      } catch {
        error => {
          // A timeout or filesystem error must not count as TLS rejection.
          assert_true(
            @debug.to_string(error).has_prefix("TlsError("),
            msg="expected TLS rejection, got \{error}",
          )
          true
        }
      }
      assert_true(rejected)
    }
  }
}

///|
async test "product runner rejects untrusted localhost TLS with default system roots" {
  @async.with_timeout(10000) <| () => {
    @async.with_task_group() <| group => {
      let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
        let (tcp, _) = server.accept()
        defer tcp.close()
        let tls = local_tls_server(tcp)
        defer tls.close()
        let _ = tls.read()
      }
      let rejected = try {
        let _ = @runner.run(
          "{\"id\":\"tls\",\"method\":\"GET\",\"path\":\"/\"}",
          "https://127.0.0.1:\{server.addr.port()}",
          Map([]),
        )
        false
      } catch {
        @runner.Failed(line, reason) => {
          assert_eq(line, 1)
          assert_eq(reason, "connection, TLS or I/O failure")
          true
        }
        error => raise error
      }
      assert_true(rejected)
    }
  }
}
