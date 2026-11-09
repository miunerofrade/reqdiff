///|
test "ordinary hexadecimal-prefixed DNS labels are not legacy IPv4" {
  assert_eq(validate_origin("https://0xdocs.example"), "https://0xdocs.example")
  assert_eq(
    validate_origin("https://api.0xteam.example"),
    "https://api.0xteam.example",
  )
  for input in ["http://0x7f000001", "http://127.0x1"] {
    let rejected = try {
      let _ = validate_origin(input)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "JSON nesting exceeds the explicit budget" {
  let body = "[".repeat(70) + "0" + "]".repeat(70)
  let rejected = try {
    let _ = parse_cases(
      "{\"id\":\"deep\",\"method\":\"GET\",\"path\":\"/\",\"body\":\{body}}",
    )
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
