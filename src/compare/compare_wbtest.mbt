///|
fn wb_parsed(text : String) -> @json.Json {
  @json.parse(text, preserve_number_repr=true) catch {
    _ => abort("test fixture JSON must parse")
  }
}

///|
fn wb_record(
  id~ : String = "a",
  status~ : Int32 = 200,
  body~ : @baseline.RecordedBody = @baseline.Uncaptured,
) -> @baseline.Record {
  @baseline.Record::make(id, "GET", "sha256:x", status, body)
}

///|
fn wb_json_record(
  id~ : String = "a",
  status~ : Int32 = 200,
  json~ : String,
) -> @baseline.Record {
  wb_record(id~, status~, body=@baseline.JsonBody(wb_parsed(json)))
}

///|
test "numbers compare by exact decimal value" {
  fn differing(left : String, right : String) -> Bool {
    let report = compare(
      [wb_json_record(json="\{left}")],
      [wb_json_record(json="\{right}")],
      [],
    )
    report.total_differences > 0
  }
  // 9007199254740992 and 9007199254740993 differ despite Double rounding.
  assert_true(differing("9007199254740992", "9007199254740993"))
  // 1 = 1.0 = 1e0 and -0 = 0.
  assert_false(differing("1", "1.0"))
  assert_false(differing("1.0", "1e0"))
  assert_false(differing("-0", "0"))
  assert_false(differing("1.2300", "1.23"))
  assert_false(differing("1e2", "100"))
  // Huge exponents compare without expansion and without overflow.
  assert_true(differing("1e9999", "2e9999"))
  assert_true(differing("1e99999999999999999999", "1e99999999999999999998"))
  assert_false(differing("1e9999", "1e+9999"))
  assert_false(differing("1e-9999", "1e-9999"))
  assert_true(differing("1e-9999", "1e-9998"))
  assert_false(differing("-1.5e3", "-1500"))
}

///|
test "pointer compilation is strict RFC 6901" {
  let accepted = ["", "/a", "/a/b", "/~0/~1", "/0", "/", "/array/0", "/a/"]
  for pointer in accepted {
    let compiled = compile_ignores([pointer])
    assert_eq(compiled.length(), 1, msg=pointer)
  }
  let rejected = ["a", "/01", "/a/-", "/~2", "/~", "/a~0b~"]
  for pointer in rejected {
    let errored = try {
      let _ = compile_ignores([pointer])
      false
    } catch {
      InvalidPointer(ordinal, _) => {
        assert_eq(ordinal, 1)
        true
      }
    }
    assert_true(errored, msg=pointer)
  }
  // Ordinals are one-based flag positions.
  let errored = try {
    let _ = compile_ignores(["/ok", "bad"])
    false
  } catch {
    InvalidPointer(ordinal, _) => {
      assert_eq(ordinal, 2)
      true
    }
  }
  assert_true(errored)
}

///|
test "json structure ignores key order and preserves array order" {
  fn identical(left : String, right : String) -> Bool raise {
    let pointers = compile_ignores([])
    compare([wb_json_record(json=left)], [wb_json_record(json=right)], pointers).total_differences ==
    0
  }
  assert_true(identical("{\"a\":1,\"b\":2}", "{\"b\":2,\"a\":1}"))
  assert_false(identical("[1,2]", "[2,1]"))
  assert_false(identical("{\"a\":1}", "{\"a\":1,\"b\":null}"))
  assert_false(identical("{\"a\":1}", "{\"a\":1,\"b\":2}"))
  assert_false(identical("{\"a\":null}", "{\"a\":0}"))
  assert_false(identical("{\"a\":1}", "{\"a\":\"1\"}"))
  assert_false(identical("{\"a\":[]}", "{\"a\":{}}"))
  assert_false(identical("[1,2]", "[1,2,3]"))
  // Nested paths report one count per differing location.
  let report = compare(
    [wb_json_record(json="{\"x\":{\"a\":1,\"c\":3},\"y\":[1,2]}")],
    [wb_json_record(json="{\"x\":{\"a\":9,\"c\":3},\"y\":[1,5]}")],
    [],
  )
  assert_eq(report.total_differences, 1)
  match report.records[0].differences[0] {
    JsonBodyDifference(count) => assert_eq(count, 2)
    _ => fail("expected json difference")
  }
}

///|
test "ignores mask subtrees symmetrically without shifting arrays" {
  fn identical(left : String, right : String, ignore : String) -> Bool raise {
    let pointers = compile_ignores([ignore])
    compare([wb_json_record(json=left)], [wb_json_record(json=right)], pointers).total_differences ==
    0
  }
  // Ignored element masks differences at that index on both sides.
  assert_true(identical("[1,2]", "[9,2]", "/0"))
  // Remaining elements still align by index; no element deletion.
  assert_false(identical("[1,2]", "[1,9]", "/0"))
  // Root masks the entire JSON body but never the status.
  assert_true(identical("{\"any\":\"thing\"}", "{\"other\":1}", ""))
  let status_report = compare(
    [wb_json_record(status=200, json="{\"a\":1}")],
    [wb_json_record(status=500, json="{\"b\":2}")],
    compile_ignores([""]),
  )
  assert_eq(status_report.total_differences, 1)
  match status_report.records[0].differences[0] {
    StatusDifference(200, 500) => ()
    _ => fail("expected status difference")
  }
  // Unknown pointers are no-ops; ignoring a subtree masks everything in it.
  assert_false(identical("{\"a\":1}", "{\"a\":2}", "/missing"))
  assert_true(identical("{\"a\":{\"b\":1}}", "{\"a\":{\"b\":2}}", "/a"))
  // Missing versus null inside an ignored subtree is masked.
  assert_true(identical("{\"a\":{\"b\":1}}", "{\"a\":{\"c\":null}}", "/a"))
  // ...but visible outside it.
  assert_false(identical("{\"a\":{\"b\":1}}", "{\"a\":{\"c\":null}}", "/x"))
}

///|
test "statuses kinds and text differences are reported per record" {
  let recorded = [
    wb_record(id="s", status=200),
    wb_record(id="k", body=@baseline.JsonBody(wb_parsed("1"))),
    wb_record(id="t", body=@baseline.TextBody("same")),
    wb_record(id="e", body=@baseline.Empty),
    wb_record(id="extra", body=@baseline.TextBody("gone")),
  ]
  let observed = [
    wb_record(id="s", status=404),
    wb_record(id="k", body=@baseline.TextBody("now text")),
    wb_record(id="t", body=@baseline.TextBody("changed")),
    wb_record(id="e", body=@baseline.Empty),
  ]
  let report = compare(recorded, observed, [])
  assert_eq(report.cases, 4)
  assert_eq(report.differing_cases, 4)
  assert_eq(report.total_differences, 4)
  assert_eq(report.records[0].id, "s")
  match report.records[0].differences[0] {
    StatusDifference(200, 404) => ()
    _ => fail("expected status")
  }
  match report.records[1].differences[0] {
    BodyKindDifference("json", "text") => ()
    _ => fail("expected kind")
  }
  match report.records[2].differences[0] {
    TextBodyDifference => ()
    _ => fail("expected text")
  }
  // Identical empty bodies produce no record; the extra recorded id appends.
  assert_eq(report.records[3].id, "extra")
  match report.records[3].differences[0] {
    BodyKindDifference("text", "missing") => ()
    _ => fail("expected missing kind")
  }
  assert_false(report.truncated)
}

///|
test "reports cap listed records but keep exact totals" {
  let recorded : Array[@baseline.Record] = []
  let observed : Array[@baseline.Record] = []
  for i in 0..<55 {
    recorded.push(wb_record(id="c-\{i}", status=200))
    observed.push(wb_record(id="c-\{i}", status=500))
  }
  let report = compare(recorded, observed, [])
  assert_eq(report.cases, 55)
  assert_eq(report.differing_cases, 55)
  assert_eq(report.total_differences, 55)
  assert_eq(report.records.length(), 50)
  assert_true(report.truncated)
}
