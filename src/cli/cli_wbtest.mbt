///|
test "help version and invalid arguments are controlled" {
  match parse_args(["--help"]) {
    Display(text) => {
      assert_true(text.contains("validate"))
      assert_true(text.contains("plan"))
      assert_true(text.contains("run"))
      assert_true(text.contains("record"))
      assert_true(text.contains("diff"))
      assert_false(text.contains("snapshot"))
    }
    _ => fail("expected help")
  }
  match parse_args(["--version"]) {
    Display(text) => assert_eq(text, "0.1.0-dev")
    _ => fail("expected version")
  }
  for
    args in [
      [],
      ["run"],
      ["record"],
      ["diff"],
      ["validate"],
      ["plan", "cases.jsonl"],
      ["run", "cases.jsonl"],
      ["run", "--base-url", "http://localhost"],
      ["record", "cases.jsonl", "--base-url", "http://localhost"],
      ["diff", "cases.jsonl", "--base-url", "http://localhost"],
      ["record", "c", "--base-url", "http://localhost", "--body", "both"],
      ["diff", "c", "--base-url", "http://localhost", "--format", "xml"],
      ["--token=private"],
    ] {
    match parse_args(args) {
      Invalid => ()
      _ => fail("expected invalid args")
    }
  }
}

///|
test "run parser requires an explicit origin and does not execute via offline evaluation" {
  match
    parse_args(["run", "x", "--base-url", "http://localhost", "--allow-write"]) {
    Run(path, base, allow_write) => {
      assert_eq(path, "x")
      assert_eq(base, "http://localhost")
      assert_true(allow_write)
    }
    _ => fail("expected run")
  }
  match parse_args(["run", "x", "--base-url", "http://localhost"]) {
    Run(_, _, allow_write) => assert_false(allow_write)
    _ => fail("expected run")
  }
  let rejected = try {
    let _ = evaluate(Run("x", "http://localhost", false), "", {})
    false
  } catch {
    @cases.InvalidInput(_, field, _) => {
      assert_eq(field, "command")
      true
    }
  }
  assert_true(rejected)
}

///|
test "record and diff parse flags with defaults and repeats" {
  match
    parse_args([
      "record", "c", "--base-url", "http://localhost", "--out", "b.json",
    ]) {
    Record(path, base, out, body_auto, force, allow_write) => {
      assert_eq(path, "c")
      assert_eq(base, "http://localhost")
      assert_eq(out, "b.json")
      assert_false(body_auto)
      assert_false(force)
      assert_false(allow_write)
    }
    _ => fail("expected record")
  }
  match
    parse_args([
      "record", "c", "--base-url", "http://localhost", "--out", "b.json", "--body",
      "auto", "--force", "--allow-write",
    ]) {
    Record(_, _, _, body_auto, force, allow_write) => {
      assert_true(body_auto)
      assert_true(force)
      assert_true(allow_write)
    }
    _ => fail("expected record")
  }
  match
    parse_args([
      "diff", "c", "--base-url", "http://localhost", "--baseline", "b.json", "--ignore",
      "/a", "--ignore", "/arr/0", "--format", "json", "--allow-write",
    ]) {
    Diff(path, base, baseline, ignores, format, allow_write) => {
      assert_eq(path, "c")
      assert_eq(base, "http://localhost")
      assert_eq(baseline, "b.json")
      assert_eq(ignores, ["/a", "/arr/0"])
      assert_eq(format, "json")
      assert_true(allow_write)
    }
    _ => fail("expected diff")
  }
  match
    parse_args([
      "diff", "c", "--base-url", "http://localhost", "--baseline", "b",
    ]) {
    Diff(_, _, _, ignores, format, _) => {
      assert_true(ignores.is_empty())
      assert_eq(format, "terminal")
    }
    _ => fail("expected diff")
  }
  let rejected = try {
    let _ = evaluate(
      Diff("x", "http://localhost", "b", [], "terminal", false),
      "",
      {},
    )
    false
  } catch {
    @cases.InvalidInput(_, field, _) => {
      assert_eq(field, "command")
      true
    }
  }
  assert_true(rejected)
}

///|
test "validate and plan report counts without private input" {
  let text = "{\"id\":\"users\",\"method\":\"GET\",\"path\":\"/users?secret=hidden-query\",\"headers\":{\"Authorization\":{\"env\":\"TOKEN\"}}}"
  let env = { "TOKEN": "hidden-credential" }
  let validated = evaluate(parse_args(["validate", "input.jsonl"]), text, env)
  assert_eq(validated, "VALID: 1 case(s); no requests sent")
  let output = evaluate(
    parse_args(["plan", "input.jsonl", "--base-url", "HTTP://LOCALHOST:08080/"]),
    text,
    env,
  )
  assert_true(output.contains("http://localhost:8080"))
  assert_true(output.contains("users"))
  assert_false(output.contains("hidden-query"))
  assert_false(output.contains("hidden-credential"))
  assert_false(output.contains("Authorization"))
  assert_false(output.contains("TOKEN"))
}

///|
test "write opt in and input errors survive CLI integration" {
  let text = "{\"id\":\"create\",\"method\":\"POST\",\"path\":\"/items\",\"body\":null}"
  let rejected = try {
    let _ = evaluate(parse_args(["validate", "x"]), text, {})
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_eq(
    evaluate(parse_args(["validate", "--allow-write", "x"]), text, {}),
    "VALID: 1 case(s); no requests sent",
  )
  let missing = try {
    let _ = evaluate(
      parse_args(["validate", "x"]),
      "{\"id\":\"secure\",\"method\":\"GET\",\"path\":\"/\",\"headers\":{\"Authorization\":{\"env\":\"MY_SECRET_NAME\"}}}",
      {},
    )
    false
  } catch {
    error => {
      assert_false(error.to_string().contains("MY_SECRET_NAME"))
      true
    }
  }
  assert_true(missing)
}
