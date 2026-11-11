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
) -> @baseline.Record raise {
  wb_record(
    id~,
    status~,
    body=@baseline.JsonBody(@json.parse(json, preserve_number_repr=true)),
  )
}

///|
test "identical suites render a single summary line" {
  let report = @compare.compare([wb_record()], [wb_record()], [])
  assert_eq(render_terminal(report), "IDENTICAL: 1 case(s); no differences")
  assert_eq(
    render_json(report),
    "{\"version\":1,\"cases\":1,\"differences\":0,\"truncated\":false,\"records\":[]}",
  )
}

///|
test "terminal reports list categories counts and truncation" {
  let report = @compare.compare(
    [
      wb_record(id="s", status=200),
      wb_record(id="k", body=@baseline.JsonBody(@json.parse("null"))),
      wb_record(id="t", body=@baseline.TextBody("a")),
      wb_record(id="e", body=@baseline.Empty),
    ],
    [
      wb_record(id="s", status=404),
      wb_record(id="k", body=@baseline.TextBody("x")),
      wb_record(id="t", body=@baseline.TextBody("b")),
      wb_record(id="e", body=@baseline.TextBody("was empty")),
    ],
    [],
  )
  let rendered = render_terminal(report)
  let lines = rendered.split("\n").collect()
  assert_eq(lines[0], "DIFF: 4 case(s); 4 difference(s)")
  assert_eq(lines[1], "s status: 200 -> 404")
  assert_eq(lines[2], "k body kind: json -> text")
  assert_eq(lines[3], "t body text: differs")
  assert_eq(lines[4], "e body kind: empty -> text")
  assert_eq(lines.length(), 5)
  // Truncation marker names shown and full counts.
  let recorded : Array[@baseline.Record] = []
  let observed : Array[@baseline.Record] = []
  for i in 0..<52 {
    recorded.push(wb_record(id="c-\{i}", status=200))
    observed.push(wb_record(id="c-\{i}", status=500))
  }
  let truncated = render_terminal(@compare.compare(recorded, observed, []))
  assert_true(truncated.has_prefix("DIFF: 52 case(s); 52 difference(s)\n"))
  assert_true(
    truncated.contains("report truncated: showing 50 of 52 differing case(s)"),
  )
  assert_eq(truncated.split("\n").collect().length(), 52)
}

///|
test "json reports stay parseable and free of private content" {
  let report = @compare.compare(
    [
      wb_record(id="s\"q", status=200),
      wb_json_record(id="j", json="{\"a\":1}"),
      wb_record(id="t", body=@baseline.TextBody("x")),
    ],
    [
      wb_record(id="s\"q", status=500),
      wb_json_record(id="j", json="{\"a\":9007199254740993}"),
      wb_record(id="t", body=@baseline.TextBody("y")),
    ],
    [],
  )
  let rendered = render_json(report)
  assert_true(rendered.has_prefix("{\"version\":1,"))
  assert_true(
    rendered.contains("\"cases\":3") && rendered.contains("\"differences\":3"),
  )
  assert_false(rendered.contains("9007199254740993"))
  assert_true(rendered.contains("s\\\"q"))
  assert_false(rendered.contains("\"x\""))
  assert_false(rendered.contains("\"y\""))
  assert_false(rendered.contains("\"a\""))
  // The count line reports one json location for the number change.
  assert_true(rendered.contains("\"count\":1"))
}
