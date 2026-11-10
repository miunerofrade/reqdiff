///|
/// Only safe coordinates and fixed descriptions cross the process boundary.
pub(all) suberror RunError {
  Failed(Int32, String)
}

///|
/// Response contents and headers are deliberately absent from terminal results.
pub struct Summary {
  id : String
  meth : String
  status : Int32
  body_bytes : Int32
}

///|
pub let request_timeout_ms : Int32 = 10000

///|
pub let max_response_bytes : Int32 = 1024 * 1024

///|
priv suberror BodyLimitExceeded

///|
priv suberror InvalidResponse

///|
fn request_method(meth : String) -> @http.RequestMethod {
  match meth {
    "GET" => Get
    "HEAD" => Head
    "POST" => Post
    "PUT" => Put
    "PATCH" => Patch
    "DELETE" => Delete
    "OPTIONS" => Options
    _ => abort("method must be validated before execution")
  }
}

///|
fn request_headers(
  case : @cases.Case,
  env : Map[String, String],
) -> @http.Headers {
  let headers : @http.Headers = Map([])
  for name, value in case.headers {
    let value = match value {
      Literal(value) => value
      Env(name) => env.get(name).unwrap()
    }
    headers.set(@http.CaseInsensitiveString(name), value)
  }
  if !headers.contains("Accept-Encoding") {
    // Explicit encoding disables SDK auto-decompression. Count entity bytes.
    headers.set("Accept-Encoding", "identity")
  }
  if !headers.contains("Content-Type") {
    match case.body {
      Some(JsonBody(_)) => headers.set("Content-Type", "application/json")
      Some(TextBody(_)) =>
        headers.set("Content-Type", "text/plain; charset=utf-8")
      None => ()
    }
  }
  headers
}

///|
// Fixed allocation and at most limit + 1 bytes consumed, including chunked bodies.
async fn bounded_body(client : @http.ClientConnection, limit : Int32) -> Int32 {
  let buffer = FixedArray::make(limit + 1, b'\x00')
  let mut used = 0
  while used <= limit {
    let count = client.read_into(buffer, offset=used, max_len=limit + 1 - used)
    if count == 0 {
      return used
    }
    used += count
    if used > limit {
      raise BodyLimitExceeded
    }
  }
  abort("unreachable")
}

///|
async fn execute_one(
  case : @cases.Case,
  origin : String,
  env : Map[String, String],
  timeout_ms : Int32,
) -> Summary {
  try
    @async.with_timeout(timeout_ms) <| () => {
      let body = match case.body {
        None => None
        Some(JsonBody(value)) => Some(@utf8.encode(value.stringify()))
        Some(TextBody(value)) => Some(@utf8.encode(value))
      }
      // User-Agent is constructor-only in this SDK. No proxy or custom trust.
      let client = @http.ClientConnection(
        origin,
        headers=request_headers(case, env),
      )
      defer client.close()
      let extra_headers : @http.Headers = Map([])
      if body is Some(bytes) {
        extra_headers.set("Content-Length", bytes.length().to_string())
      }
      client.request(request_method(case.meth), case.path, extra_headers~)
      if body is Some(bytes) {
        client.write(bytes[:])
      }
      let response = client.end_request()
      // Informational responses are handled by the SDK; protocol upgrades are unsupported.
      if response.code < 200 || response.code > 599 {
        raise InvalidResponse
      }
      let body_bytes = bounded_body(client, max_response_bytes)
      { id: case.id, meth: case.meth, status: response.code, body_bytes, }
    }
  catch {
    @async.TimeoutError => raise Failed(case.source_line, "request timed out")
    BodyLimitExceeded =>
      raise Failed(case.source_line, "response body exceeds 1 MiB")
    InvalidResponse
    | @http.IncorrectBodyLength
    | @io.ReaderClosed
    | @http.BadRequest
    | @http.HttpVersionNotSupported(_)
    | @http.NotImplemented =>
      raise Failed(case.source_line, "invalid or incomplete HTTP response")
    _ => raise Failed(case.source_line, "connection, TLS or I/O failure")
  }
}

///|
async fn run_with_deadline(
  text : String,
  base : String,
  env : Map[String, String],
  allow_write : Bool,
  timeout_ms : Int32,
) -> Array[Summary] {
  let origin = @cases.validate_origin(base)
  let cases = @cases.parse_cases(text, allow_write~)
  @cases.validate_env(cases, env)
  let results : Array[Summary] = []
  for case in cases {
    results.push(execute_one(case, origin, env, timeout_ms))
  }
  results
}

///|
/// Preflight the entire collection before establishing any connection.
pub async fn run(
  text : String,
  base : String,
  env : Map[String, String],
  allow_write~ : Bool = false,
) -> Array[Summary] {
  run_with_deadline(text, base, env, allow_write, request_timeout_ms)
}

///|
pub fn render_run(results : Array[Summary]) -> String {
  let lines = ["RUN: \{results.length()} case(s); requests completed"]
  for result in results {
    lines.push(
      "\{result.id} \{result.meth} status=\{result.status} bytes=\{result.body_bytes}",
    )
  }
  lines.join("\n")
}
