// Reports carry only public identifiers, categories and counts — never
// bodies, JSON keys/pointers, request paths/queries, headers or env values.

///|
fn json_escape(value : String) -> String {
  let builder = StringBuilder()
  builder.write_char('"')
  for c in value.iter() {
    let n = c.to_int()
    if n == 34 {
      builder.write_string("\\\"")
    } else if n == 92 {
      builder.write_string("\\\\")
    } else if n == 10 {
      builder.write_string("\\n")
    } else if n == 13 {
      builder.write_string("\\r")
    } else if n == 9 {
      builder.write_string("\\t")
    } else if n < 32 {
      let hex = "0123456789abcdef"
      builder.write_string("\\u00")
      builder.write_char(hex[n / 16].to_char().unwrap())
      builder.write_char(hex[n % 16].to_char().unwrap())
    } else {
      builder.write_char(c)
    }
  }
  builder.write_char('"')
  builder.to_string()
}

///|
fn difference_line(id : String, difference : @compare.Difference) -> String {
  match difference {
    StatusDifference(recorded, observed) =>
      "\{id} status: \{recorded} -> \{observed}"
    BodyKindDifference(recorded, observed) =>
      "\{id} body kind: \{recorded} -> \{observed}"
    JsonBodyDifference(count) => "\{id} body json: \{count} difference(s)"
    TextBodyDifference => "\{id} body text: differs"
  }
}

///|
pub fn render_terminal(report : @compare.Report) -> String {
  if report.total_differences == 0 {
    return "IDENTICAL: \{report.cases} case(s); no differences"
  }
  let lines : Array[String] = [
    "DIFF: \{report.cases} case(s); \{report.total_differences} difference(s)",
  ]
  for record in report.records {
    for difference in record.differences {
      lines.push(difference_line(record.id, difference))
    }
  }
  if report.truncated {
    lines.push(
      "report truncated: showing \{report.records.length()} of \{report.differing_cases} differing case(s)",
    )
  }
  // println at the process boundary adds the final newline.
  lines.join("\n")
}

///|
fn render_difference_json(
  builder : StringBuilder,
  first : Bool,
  id : String,
  difference : @compare.Difference,
) -> Bool {
  if !first {
    builder.write_char(',')
  }
  match difference {
    StatusDifference(recorded, observed) =>
      builder.write_string(
        "{\"id\":\{json_escape(id)},\"status\":{\"recorded\":\{recorded},\"current\":\{observed}}}",
      )
    BodyKindDifference(recorded, observed) =>
      builder.write_string(
        "{\"id\":\{json_escape(id)},\"body\":{\"kind\":{\"recorded\":\{json_escape(recorded)},\"current\":\{json_escape(observed)}}}}",
      )
    JsonBodyDifference(count) =>
      builder.write_string(
        "{\"id\":\{json_escape(id)},\"body\":{\"kind\":\"json\",\"count\":\{count}}}",
      )
    TextBodyDifference =>
      builder.write_string(
        "{\"id\":\{json_escape(id)},\"body\":{\"kind\":\"text\"}}",
      )
  }
  false
}

///|
pub fn render_json(report : @compare.Report) -> String {
  let builder = StringBuilder()
  builder.write_string(
    "{\"version\":1,\"cases\":\{report.cases},\"differences\":\{report.total_differences},\"truncated\":\{report.truncated},\"records\":[",
  )
  let mut first = true
  for record in report.records {
    for difference in record.differences {
      first = render_difference_json(builder, first, record.id, difference)
    }
  }
  builder.write_string("]}")
  builder.to_string()
}
