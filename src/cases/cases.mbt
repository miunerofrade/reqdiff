///|
/// Errors contain only source coordinates and static descriptions, never input values.
pub(all) suberror ValidationError {
  InvalidInput(Int32, String, String)
}

///|
pub fn ValidationError::to_string(self : ValidationError) -> String {
  match self {
    InvalidInput(line, field, reason) =>
      "line \{line}, field \{field}: \{reason}"
  }
}

///|
pub fn ValidationError::output(
  self : ValidationError,
  logger : &Logger,
) -> Unit {
  logger.write_string(self.to_string())
}

///|
pub impl Show for ValidationError with fn output(self, logger) {
  self.output(logger)
}

///|
/// Do not derive Show: literal headers and bodies may contain secrets.
pub(all) enum HeaderValue {
  Literal(String)
  Env(String)
}

///|
/// Some(JsonBody(Null)) is distinct from no body.
pub(all) enum Body {
  JsonBody(Json)
  TextBody(String)
}

///|
/// Header names are normalized to lowercase. source_line is one-based.
pub struct Case {
  id : String
  meth : String
  path : String
  headers : Map[String, HeaderValue]
  body : Body?
  source_line : Int32
}

///|
pub let max_file_bytes : Int32 = 5 * 1024 * 1024

///|
/// Bound each JSONL record independently of the file limit.
pub let max_line_bytes : Int32 = 1024 * 1024

///|
pub let max_cases : Int32 = 100

///|
fn invalid(
  line : Int32,
  field : String,
  reason : String,
) -> Unit raise ValidationError {
  raise InvalidInput(line, field, reason)
}

///|
fn ascii_alnum(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
}

///|
fn control(c : Char) -> Bool {
  let n = c.to_int()
  n < 32 || (n >= 127 && n <= 159)
}

///|
fn clean_value(s : String) -> Bool {
  for c in s.iter() {
    if control(c) {
      return false
    }
  }
  true
}

///|
fn valid_id(s : String) -> Bool {
  let cs = s.to_array()
  if cs.length() == 0 || cs.length() > 64 || !ascii_alnum(cs[0]) {
    return false
  }
  for c in cs {
    if !(ascii_alnum(c) || c == '.' || c == '_' || c == '-') {
      return false
    }
  }
  true
}

///|
fn valid_env_name(s : String) -> Bool {
  let cs = s.to_array()
  if cs.length() == 0 {
    return false
  }
  for i, c in cs {
    if !((c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      c == '_' ||
      (i > 0 && c >= '0' && c <= '9')) {
      return false
    }
  }
  true
}

///|
fn token_name(s : String) -> Bool {
  if s.is_empty() {
    return false
  }
  for c in s.iter() {
    if !(ascii_alnum(c) || "!#$%&'*+-.^_`|~".contains_char(c)) {
      return false
    }
  }
  true
}

///|
fn hex(c : Char) -> Int32 {
  if c >= '0' && c <= '9' {
    c.to_int() - 48
  } else if c >= 'a' && c <= 'f' {
    c.to_int() - 97 + 10
  } else if c >= 'A' && c <= 'F' {
    c.to_int() - 65 + 10
  } else {
    -1
  }
}

///|
fn check_path(s : String, line : Int32) -> Unit raise ValidationError {
  let cs = s.to_array()
  if cs.length() == 0 || cs[0] != '/' || (cs.length() > 1 && cs[1] == '/') {
    invalid(line, "path", "must begin with a single slash")
  }
  let mut i = 0
  while i < cs.length() {
    let c = cs[i]
    if control(c) || c == ' ' || c == '\\' || c == '#' {
      invalid(line, "path", "contains a forbidden character")
    }
    if c == '%' {
      if i + 2 >= cs.length() || hex(cs[i + 1]) < 0 || hex(cs[i + 2]) < 0 {
        invalid(line, "path", "malformed percent escape")
      }
      let n = hex(cs[i + 1]) * 16 + hex(cs[i + 2])
      if n < 32 || n == 127 || n == 92 {
        invalid(line, "path", "forbidden percent escape")
      }
      i += 3
    } else {
      i += 1
    }
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
  line : Int32,
) -> String raise ValidationError {
  match obj.get(key) {
    Some(String(s)) => s
    _ => {
      invalid(line, key, "must be a string")
      ""
    }
  }
}

///|
fn parse_headers(
  value : Json,
  line : Int32,
) -> Map[String, HeaderValue] raise ValidationError {
  let headers : Map[String, HeaderValue] = Map([])
  let obj = match value {
    Object(obj) => obj
    _ => {
      invalid(line, "headers", "must be an object")
      {}
    }
  }
  for name, value in obj {
    if !token_name(name) {
      invalid(line, "headers", "invalid header name")
    }
    let name = name.to_lower()
    if headers.contains(name) {
      invalid(line, "headers", "duplicate header name")
    }
    if [
        "host", "content-length", "transfer-encoding", "connection", "cookie", "proxy-authorization",
        "proxy-authenticate", "keep-alive", "te", "trailer", "upgrade",
      ].contains(name) {
      invalid(
        line, "headers", "protocol, cookie, or proxy header is not allowed",
      )
    }
    let parsed = match value {
      String(s) => {
        if name.contains("auth") ||
          name.contains("token") ||
          name.contains("secret") ||
          name.contains("api-key") ||
          name.contains("apikey") {
          invalid(
            line, "headers", "credential headers require an env reference",
          )
        }
        if !clean_value(s) {
          invalid(line, "headers", "header value contains a control character")
        }
        Literal(s)
      }
      Object(reference) => {
        if reference.length() != 1 || !reference.contains("env") {
          invalid(line, "headers.env", "expected only an env field")
        }
        let env = match reference.get("env") {
          Some(String(s)) => s
          _ => {
            invalid(line, "headers.env", "must be a string")
            ""
          }
        }
        if !valid_env_name(env) {
          invalid(line, "headers.env", "invalid environment variable name")
        }
        Env(env)
      }
      _ => {
        invalid(line, "headers", "expected a string or env reference")
        Literal("")
      }
    }
    headers.set(name, parsed)
  }
  headers
}

///|
/// Parse JSON Lines without I/O. Blank lines are allowed; an empty suite is not.
pub fn parse_cases(
  text : String,
  allow_write~ : Bool = false,
) -> Array[Case] raise ValidationError {
  if @utf8.encode(text).length() > max_file_bytes {
    invalid(0, "input", "file exceeds 5 MiB UTF-8 limit")
  }
  let cases : Array[Case] = []
  let ids : Map[String, Bool] = Map([])
  let mut line = 0
  for record in text.split("\n") {
    line += 1
    if @utf8.encode(record).length() > max_line_bytes {
      invalid(line, "input", "line exceeds 1 MiB UTF-8 limit")
    }
    if record.trim().is_empty() {
      continue
    }
    if cases.length() >= max_cases {
      invalid(line, "input", "at most 100 cases are allowed")
    }
    let value = @json.parse(
      record,
      reject_duplicate_keys=true,
      max_nesting_depth=64,
      preserve_number_repr=true,
    ) catch {
      _ => {
        invalid(
          line, "json", "invalid JSON, duplicate key, or excessive nesting",
        )
        @json.null
      }
    }
    let obj = match value {
      Object(obj) => obj
      _ => {
        invalid(line, "case", "must be an object")
        {}
      }
    }
    for key in obj.keys() {
      if !["id", "method", "path", "headers", "body", "body_text"].contains(key) {
        invalid(line, "case", "unknown field")
      }
    }
    let id = required_string(obj, "id", line)
    if !valid_id(id) {
      invalid(line, "id", "must match [A-Za-z0-9][A-Za-z0-9._-]{0,63}")
    }
    if ids.contains(id) {
      invalid(line, "id", "duplicate case id")
    }
    ids.set(id, true)
    let meth = required_string(obj, "method", line)
    if !["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"].contains(
        meth,
      ) {
      invalid(line, "method", "unsupported or non-uppercase HTTP method")
    }
    if !allow_write && meth != "GET" && meth != "HEAD" {
      invalid(line, "method", "requires --allow-write")
    }
    let path = required_string(obj, "path", line)
    check_path(path, line)
    let headers = match obj.get("headers") {
      Some(v) => parse_headers(v, line)
      None => {}
    }
    if obj.contains("body") && obj.contains("body_text") {
      invalid(line, "body", "body and body_text are mutually exclusive")
    }
    let body = match obj.get("body") {
      Some(v) => Some(JsonBody(v))
      None =>
        match obj.get("body_text") {
          Some(String(s)) => Some(TextBody(s))
          Some(_) => {
            invalid(line, "body_text", "must be a string")
            None
          }
          None => None
        }
    }
    cases.push({ id, meth, path, headers, body, source_line: line, })
  }
  if cases.is_empty() {
    invalid(0, "input", "at least one case is required")
  }
  cases
}

///|
/// Validate all referenced values without returning or printing any of them.
pub fn validate_env(
  cases : Array[Case],
  env : Map[String, String],
) -> Unit raise ValidationError {
  for case in cases {
    for _, value in case.headers {
      if value is Env(name) {
        match env.get(name) {
          None =>
            invalid(
              case.source_line,
              "headers.env",
              "required environment variable is missing",
            )
          Some(s) => {
            if s.is_empty() {
              invalid(
                case.source_line,
                "headers.env",
                "required environment variable is empty",
              )
            }
            if !clean_value(s) {
              invalid(
                case.source_line,
                "headers.env",
                "environment value contains a control character",
              )
            }
          }
        }
      }
    }
  }
}

///| Safe plan: only validated identifiers, methods, counts and body kind. Never URLs,

///|
/// paths/queries, header names/values, environment names/values, or body contents.
pub fn render_plan(cases : Array[Case]) -> Array[String] {
  cases.map(fn(case) {
    let body = match case.body {
      None => "none"
      Some(JsonBody(_)) => "json"
      Some(TextBody(_)) => "text"
    }
    "\{case.id} \{case.meth} headers=\{case.headers.length()} body=\{body}"
  })
}
