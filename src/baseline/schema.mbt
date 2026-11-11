///|
pub let max_baseline_bytes : Int32 = 32 * 1024 * 1024

///|
pub let max_records : Int32 = 100

///|
fn invalid(
  index : Int32,
  field : String,
  reason : String,
) -> Unit raise BaselineError {
  raise InvalidBaseline(index, field, reason)
}

///|
let hex_digits : Array[String] = [
  "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f",
]

///|
fn hex2(n : Int32) -> String {
  "\{hex_digits[n / 16]}\{hex_digits[n % 16]}"
}

///|
/// RFC 8259 string literal with the mandatory escapes; other control
/// characters use \u00XX. Non-ASCII stays literal UTF-8.
fn json_string(value : String) -> String {
  let builder = StringBuilder()
  builder.write_char('"')
  for c in value.iter() {
    let n = c.to_int()
    if n == 34 {
      builder.write_string("\\\"")
    } else if n == 92 {
      builder.write_string("\\\\")
    } else if n == 8 {
      builder.write_string("\\b")
    } else if n == 12 {
      builder.write_string("\\f")
    } else if n == 10 {
      builder.write_string("\\n")
    } else if n == 13 {
      builder.write_string("\\r")
    } else if n == 9 {
      builder.write_string("\\t")
    } else if n < 32 {
      builder.write_string("\\u00")
      builder.write_string(hex2(n))
    } else {
      builder.write_char(c)
    }
  }
  builder.write_char('"')
  builder.to_string()
}

///|
fn valid_fingerprint(value : String) -> Bool {
  if !value.has_prefix("sha256:") || value.length() != 71 {
    return false
  }
  for i, c in value.to_array() {
    if i < 7 {
      continue
    }
    let n = c.to_int()
    if !((n >= 48 && n <= 57) || (n >= 97 && n <= 102)) {
      return false
    }
  }
  true
}

///|
fn integral(value : @json.Json) -> Int32? {
  match value {
    Number(number, ..) => {
      let whole = number.to_int()
      if whole.to_double() == number {
        Some(whole)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
/// Encode with preserved numeric representations and canonical field order.
pub fn encode(baseline : Baseline) -> String {
  let builder = StringBuilder()
  builder.write_string(
    "{\"version\":1,\"body_mode\":\"\{body_mode_name(baseline.mode)}\",\"records\":[",
  )
  for i, record in baseline.records {
    if i > 0 {
      builder.write_char(',')
    }
    builder.write_string(
      "{\"id\":\{json_string(record.id)},\"method\":\{json_string(record.meth)},\"fingerprint\":\{json_string(record.fingerprint)},\"status\":\{record.status}",
    )
    match record.body {
      Uncaptured => ()
      Empty => builder.write_string(",\"body\":{\"kind\":\"empty\"}")
      JsonBody(value) =>
        builder.write_string(
          ",\"body\":{\"kind\":\"json\",\"value\":\{value.stringify()}}",
        )
      TextBody(text) =>
        builder.write_string(
          ",\"body\":{\"kind\":\"text\",\"text\":\{json_string(text)}}",
        )
    }
    builder.write_char('}')
  }
  builder.write_string("]}")
  builder.to_string()
}

///|
fn parse_body(
  value : @json.Json,
  index : Int32,
) -> RecordedBody raise BaselineError {
  let obj = match value {
    Object(obj) => obj
    _ => {
      invalid(index, "body", "must be an object")
      {}
    }
  }
  for key in obj.keys() {
    if !["kind", "value", "text"].contains(key) {
      invalid(index, "body", "unknown field")
    }
  }
  let kind = match obj.get("kind") {
    Some(String(kind)) => kind
    _ => {
      invalid(index, "body.kind", "must be a string")
      ""
    }
  }
  match kind {
    "empty" => {
      if obj.length() != 1 {
        invalid(index, "body", "empty body must not carry extra fields")
      }
      Empty
    }
    "json" => {
      let value = match obj.get("value") {
        Some(value) => value
        None => {
          invalid(index, "body.value", "json body requires a value")
          @json.null
        }
      }
      JsonBody(value)
    }
    "text" => {
      let text = match obj.get("text") {
        Some(String(text)) => text
        _ => {
          invalid(index, "body.text", "text body requires a string")
          ""
        }
      }
      TextBody(text)
    }
    _ => {
      invalid(index, "body.kind", "must be empty, json, or text")
      Uncaptured
    }
  }
}

///|
/// Parse a strict v1 baseline. Duplicate keys, unknown fields, wrong version,
/// invalid statuses/kinds and body-presence mismatches are rejected.
pub fn parse(text : String) -> Baseline raise BaselineError {
  if @utf8.encode(text).length() > max_baseline_bytes {
    invalid(0, "input", "baseline exceeds 32 MiB UTF-8 limit")
  }
  let value = @json.parse(
    text,
    reject_duplicate_keys=true,
    max_nesting_depth=64,
    preserve_number_repr=true,
  ) catch {
    _ => {
      invalid(0, "json", "invalid JSON, duplicate key, or excessive nesting")
      @json.null
    }
  }
  let obj = match value {
    Object(obj) => obj
    _ => {
      invalid(0, "baseline", "must be an object")
      {}
    }
  }
  for key in obj.keys() {
    if !["version", "body_mode", "records"].contains(key) {
      invalid(0, "baseline", "unknown field")
    }
  }
  match obj.get("version") {
    Some(Number(number, ..)) =>
      if number != 1.0 {
        invalid(0, "version", "only baseline version 1 is supported")
      }
    _ => invalid(0, "version", "must be the number 1")
  }
  let mode = match obj.get("body_mode") {
    Some(String("none")) => NoBodies
    Some(String("auto")) => AutoBodies
    _ => {
      invalid(0, "body_mode", "must be none or auto")
      NoBodies
    }
  }
  let entries = match obj.get("records") {
    Some(Array(records)) => records
    _ => {
      invalid(0, "records", "must be an array")
      []
    }
  }
  if entries.is_empty() {
    invalid(0, "records", "at least one record is required")
  }
  if entries.length() > max_records {
    invalid(0, "records", "at most 100 records are allowed")
  }
  let records : Array[Record] = []
  let ids : Map[String, Bool] = Map([])
  for index, entry in entries {
    let index = index + 1
    let obj = match entry {
      Object(obj) => obj
      _ => {
        invalid(index, "record", "must be an object")
        {}
      }
    }
    let allowed = match mode {
      NoBodies => ["id", "method", "fingerprint", "status"]
      AutoBodies => ["id", "method", "fingerprint", "status", "body"]
    }
    for key in obj.keys() {
      if !allowed.contains(key) {
        invalid(index, "record", "unknown field")
      }
    }
    let id = match obj.get("id") {
      Some(String(id)) => id
      _ => {
        invalid(index, "id", "must be a string")
        ""
      }
    }
    if ids.contains(id) {
      invalid(index, "id", "duplicate record id")
    }
    ids.set(id, true)
    let meth = match obj.get("method") {
      Some(String(meth)) => meth
      _ => {
        invalid(index, "method", "must be a string")
        ""
      }
    }
    let fingerprint = match obj.get("fingerprint") {
      Some(String(fingerprint)) => fingerprint
      _ => {
        invalid(index, "fingerprint", "must be a string")
        ""
      }
    }
    if !valid_fingerprint(fingerprint) {
      invalid(
        index, "fingerprint", "must be sha256: plus 64 lowercase hex digits",
      )
    }
    let status = match obj.get("status") {
      Some(value) =>
        match integral(value) {
          Some(status) =>
            if status < 200 || status > 599 {
              invalid(index, "status", "must be within 200..599")
              0
            } else {
              status
            }
          None => {
            invalid(index, "status", "must be an integer")
            0
          }
        }
      None => {
        invalid(index, "status", "is required")
        0
      }
    }
    let body = match mode {
      NoBodies => Uncaptured
      AutoBodies =>
        match obj.get("body") {
          Some(value) => parse_body(value, index)
          None => {
            invalid(index, "body", "is required in auto mode")
            Uncaptured
          }
        }
    }
    records.push(Record::make(id, meth, fingerprint, status, body))
  }
  Baseline::make(mode, records)
}

///|
/// Match by unique ID plus request fingerprint. Missing/extra IDs and changed
/// request semantics raise before any connection is made.
pub fn check_match(
  baseline : Baseline,
  cases : Array[@cases.Case],
) -> Unit raise BaselineError {
  let recorded : Map[String, String] = Map([])
  for record in baseline.records {
    recorded.set(record.id, record.fingerprint)
  }
  let present : Map[String, Bool] = Map([])
  for case in cases {
    present.set(case.id, true)
    match recorded.get(case.id) {
      None => raise RequestMismatch(case.source_line)
      Some(fingerprint) =>
        if fingerprint != request_fingerprint(case) {
          raise RequestMismatch(case.source_line)
        }
    }
  }
  for record in baseline.records {
    // Extra baseline IDs carry no case-file coordinate; report file level 0.
    if !present.contains(record.id) {
      raise RequestMismatch(0)
    }
  }
}
