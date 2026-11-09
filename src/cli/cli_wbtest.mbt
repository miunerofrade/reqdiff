///|
test "help version and invalid arguments are controlled" {
  match parse_args(["--help"]) {
    Display(text) => {
      assert_true(text.contains("validate"))
      assert_true(text.contains("plan"))
      assert_false(text.contains("record"))
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
      ["validate"],
      ["plan", "cases.jsonl"],
      ["--token=private"],
    ] {
    match parse_args(args) {
      Invalid => ()
      _ => fail("expected invalid args")
    }
  }
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
