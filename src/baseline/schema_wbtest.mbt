///|
fn wb_record(
  id~ : String = "a",
  meth~ : String = "GET",
  status~ : Int32 = 200,
  body~ : RecordedBody = Uncaptured,
) -> Record {
  let fingerprint = "sha256:\{sha256_hex(@utf8.encode(id))}"
  Record::make(id, meth, fingerprint, status, body)
}

///|
fn swap(text : String, old : String, new : String) -> String {
  text.replace_all(old~, new~)
}

///|
test "encode and parse round trip for both body modes" {
  let none_baseline = Baseline::make(NoBodies, [
    wb_record(id="a"),
    wb_record(id="b-1", meth="POST", status=404),
  ])
  let parsed = parse(encode(none_baseline))
  assert_true(Baseline::mode(parsed) is NoBodies)
  assert_eq(Baseline::records(parsed).length(), 2)
  assert_eq(Baseline::records(parsed)[1].id, "b-1")
  assert_eq(Baseline::records(parsed)[1].meth, "POST")
  assert_eq(Baseline::records(parsed)[1].status, 404)
  let auto_baseline = Baseline::make(AutoBodies, [
    wb_record(body=Empty),
    wb_record(
      id="j",
      body=JsonBody(
        @json.parse(
          "{\"v\":[1,2.50,null],\"n\":9007199254740993}",
          preserve_number_repr=true,
        ),
      ),
    ),
    wb_record(id="t", body=TextBody("line1\nline2:雪")),
  ])
  let text = encode(auto_baseline)
  let parsed_auto = parse(text)
  assert_true(Baseline::mode(parsed_auto) is AutoBodies)
  match Baseline::records(parsed_auto)[0].body {
    Empty => ()
    _ => fail("expected empty body")
  }
  // Numbers round trip through the preserved representation.
  assert_true(text.contains("\"n\":9007199254740993") && text.contains("2.50"))
  match Baseline::records(parsed_auto)[2].body {
    TextBody(text) => assert_eq(text, "line1\nline2:雪")
    _ => fail("expected text body")
  }
  // JSON null value is preserved, not confused with an absent body.
  let null_record = wb_record(id="n", body=JsonBody(@json.null))
  match
    parse(encode(Baseline::make(AutoBodies, [null_record]))).records[0].body {
    JsonBody(@json.Null) => ()
    _ => fail("expected JSON null")
  }
  // Escaped identifiers survive the round trip.
  let quote = wb_record(id="a\"b")
  match parse(encode(Baseline::make(NoBodies, [quote]))).records[0].id {
    "a\"b" => ()
    _ => fail("expected escaped id")
  }
}

///|
test "parse rejects malformed baselines" {
  let good = encode(Baseline::make(NoBodies, [wb_record()]))
  let a_digest = "sha256:\{sha256_hex(@utf8.encode("a"))}"
  let rejects : Array[String] = [
    "",
    "{}",
    "[]",
    swap(good, "\"records\"", "\"extra\":0,\"records\""),
    swap(good, "\"version\":1", "\"version\":2"),
    swap(good, "\"version\":1", "\"version\":\"1\""),
    swap(good, "\"body_mode\":\"none\"", "\"body_mode\":\"all\""),
    swap(good, "\"records\":[{", "\"records\":["),
    swap(
      good,
      "]}",
      ",{\"id\":\"a\",\"method\":\"GET\",\"fingerprint\":\"\{a_digest}\",\"status\":200}]}",
    ),
    swap(good, "\"status\":200", "\"status\":199"),
    swap(good, "\"status\":200", "\"status\":600"),
    swap(good, "\"status\":200", "\"status\":20.5"),
    swap(
      good, "\"records\":[{", "\"records\":[{\"body\":{\"kind\":\"empty\"},{",
    ),
    swap(good, "{\"id\"", "{\"body\":{\"kind\":\"empty\"},\"id\""),
    "{\"version\":1,\"body_mode\":\"none\",\"records\":[{\"id\":\"a\",\"method\":\"GET\",\"fingerprint\":\"\{a_digest}\",\"status\":200,\"body\":{\"kind\":\"empty\"}}]}",
    "{\"version\":1,\"body_mode\":\"auto\",\"records\":[{\"id\":\"a\",\"method\":\"GET\",\"fingerprint\":\"\{a_digest}\",\"status\":200}]}",
    "{\"version\":1,\"body_mode\":\"auto\",\"records\":[{\"id\":\"a\",\"method\":\"GET\",\"fingerprint\":\"\{a_digest}\",\"status\":200,\"body\":{\"kind\":\"text\",\"value\":\"x\"}}]}",
    "{\"version\":1,\"body_mode\":\"auto\",\"records\":[{\"id\":\"a\",\"method\":\"GET\",\"fingerprint\":\"\{a_digest}\",\"status\":200,\"body\":{\"kind\":\"mystery\"}}]}",
    "{\"version\":1,\"body_mode\":\"none\",\"records\":[{\"id\":\"a\",\"method\":\"GET\",\"fingerprint\":\"\{a_digest}\",\"status\":200},{\"id\":\"a\",\"method\":\"GET\",\"fingerprint\":\"\{a_digest}\",\"status\":200}]}",
    "{\"version\":1,\"body_mode\":\"none\",\"records\":[]}",
  ]
  for text in rejects {
    let rejected = try {
      let _ = parse(text)
      false
    } catch {
      InvalidBaseline(_, _, _) => true
      error => raise error
    }
    assert_true(rejected, msg="expected rejection: \{text}")
  }
  // Duplicate keys anywhere are rejected recursively.
  let dup = try {
    let _ = parse(
      "{\"version\":1,\"body_mode\":\"none\",\"records\":[],\"records\":[]}",
    )
    false
  } catch {
    InvalidBaseline(_, _, _) => true
    error => raise error
  }
  assert_true(dup)
}

///|
test "check match requires identical id sets and fingerprints" {
  let cases = @cases.parse_cases(
    "{\"id\":\"a\",\"method\":\"GET\",\"path\":\"/x?y=1\"}\n{\"id\":\"b\",\"method\":\"POST\",\"path\":\"/y\",\"body\":null}",
    allow_write=true,
  )
  let records = cases.map(fn(case) {
    Record::make(case.id, case.meth, request_fingerprint(case), 200, Uncaptured)
  })
  // Reordered records still match.
  check_match(Baseline::make(NoBodies, [records[1], records[0]]), cases)
  // Missing baseline entry.
  let rejected_missing = try {
    check_match(Baseline::make(NoBodies, [records[0]]), cases)
    false
  } catch {
    RequestMismatch(line) => {
      assert_eq(line, 2)
      true
    }
    error => raise error
  }
  assert_true(rejected_missing)
  // Extra baseline entry reports file level zero.
  let extra = [
    records[0],
    records[1],
    Record::make("ghost", "GET", records[0].fingerprint, 200, Uncaptured),
  ]
  let rejected_extra = try {
    check_match(Baseline::make(NoBodies, extra), cases)
    false
  } catch {
    RequestMismatch(line) => {
      assert_eq(line, 0)
      true
    }
    error => raise error
  }
  assert_true(rejected_extra)
  // Changed request semantics (path) break the fingerprint.
  let changed = @cases.parse_cases(
    "{\"id\":\"a\",\"method\":\"GET\",\"path\":\"/changed\"}",
  )
  let rejected_changed = try {
    check_match(Baseline::make(NoBodies, [records[1], records[0]]), changed)
    false
  } catch {
    RequestMismatch(line) => {
      assert_eq(line, 1)
      true
    }
    error => raise error
  }
  assert_true(rejected_changed)
}

///|
test "fingerprints cover semantics and exclude env credentials" {
  let base = @cases.parse_cases(
    "{\"id\":\"a\",\"method\":\"GET\",\"path\":\"/x?y=1\",\"headers\":{\"Accept\":\"application/json\",\"Authorization\":{\"env\":\"TOKEN\"}}}",
  )
  let baseline_digest = request_fingerprint(base[0])
  // Stable across identical inputs.
  assert_eq(
    baseline_digest,
    request_fingerprint(
      @cases.parse_cases(
        "{\"id\":\"other\",\"method\":\"GET\",\"path\":\"/x?y=1\",\"headers\":{\"Accept\":\"application/json\",\"Authorization\":{\"env\":\"OTHER_NAME\"}}}",
      )[0],
    ),
  )
  // Env-referenced credential headers are excluded entirely.
  assert_eq(
    baseline_digest,
    request_fingerprint(
      @cases.parse_cases(
        "{\"id\":\"other\",\"method\":\"GET\",\"path\":\"/x?y=1\",\"headers\":{\"Accept\":\"application/json\"}}",
      )[0],
    ),
  )
  // Every semantic dimension changes the digest.
  let variations = [
    "{\"id\":\"a\",\"method\":\"POST\",\"path\":\"/x?y=1\",\"headers\":{\"Accept\":\"application/json\",\"Authorization\":{\"env\":\"TOKEN\"}}}",
    "{\"id\":\"a\",\"method\":\"GET\",\"path\":\"/x?y=2\",\"headers\":{\"Accept\":\"application/json\",\"Authorization\":{\"env\":\"TOKEN\"}}}",
    "{\"id\":\"a\",\"method\":\"GET\",\"path\":\"/x?y=1\",\"headers\":{\"Accept\":\"text/plain\",\"Authorization\":{\"env\":\"TOKEN\"}}}",
    "{\"id\":\"a\",\"method\":\"GET\",\"path\":\"/x?y=1\",\"headers\":{\"Accept\":\"application/json\",\"Authorization\":{\"env\":\"TOKEN\"}},\"body\":null}",
  ]
  for variation in variations {
    let parsed = @cases.parse_cases(variation, allow_write=true)
    assert_true(
      request_fingerprint(parsed[0]) != baseline_digest,
      msg="fingerprint should differ for \{variation}",
    )
  }
  // Digest shape.
  assert_true(baseline_digest.has_prefix("sha256:"))
  assert_eq(baseline_digest.length(), 71)
}
