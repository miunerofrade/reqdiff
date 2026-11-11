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
/// Whole-suite budget for captured bodies in auto mode.
pub let max_capture_bytes : Int32 = 8 * 1024 * 1024

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
// Same algorithm as bounded_body, keeping the bytes for baseline capture.
async fn bounded_body_keep(
  client : @http.ClientConnection,
  limit : Int32,
) -> Bytes {
  let buffer = FixedArray::make(limit + 1, b'\x00')
  let mut used = 0
  while used <= limit {
    let count = client.read_into(buffer, offset=used, max_len=limit + 1 - used)
    if count == 0 {
      return Bytes::makei(used, i => buffer[i])
    }
    used += count
    if used > limit {
      raise BodyLimitExceeded
    }
  }
  abort("unreachable")
}

///|
fn decode_strict(
  bytes : Bytes,
  line : Int32,
  reason : String,
) -> String raise RunError {
  @utf8.decode(bytes[:]) catch {
    _ => {
      raise Failed(line, reason)
      ""
    }
  }
}

///|
// Classify a captured response body. Empty stays empty regardless of headers;
// JSON media types must strictly parse; everything else must be strict UTF-8.
fn classify_body(
  bytes : Bytes,
  response : @http.ResponseHeader,
  line : Int32,
) -> @baseline.RecordedBody raise RunError {
  if bytes.length() == 0 {
    return Empty
  }
  match response.headers.get("Content-Encoding") {
    Some(encoding) =>
      if encoding.to_lower() != "identity" {
        raise Failed(line, "response content encoding is not identity")
      }
    None => ()
  }
  let media = match response.headers.get("Content-Type") {
    Some(value) => value.split(";").collect()[0].trim().to_owned().to_lower()
    None => ""
  }
  if media == "application/json" || media.has_suffix("+json") {
    let text = decode_strict(bytes, line, "response is not valid UTF-8")
    let value = @json.parse(
      text,
      reject_duplicate_keys=true,
      max_nesting_depth=64,
      preserve_number_repr=true,
    ) catch {
      _ => {
        raise Failed(line, "response declared JSON but is not valid JSON")
        @json.null
      }
    }
    JsonBody(value)
  } else {
    TextBody(decode_strict(bytes, line, "response is not valid UTF-8 text"))
  }
}

///|
priv struct Observation {
  status : Int32
  body_bytes : Int32
  body : @baseline.RecordedBody
}

///|
async fn execute_full(
  case : @cases.Case,
  origin : String,
  env : Map[String, String],
  timeout_ms : Int32,
  mode : @baseline.BodyMode,
) -> Observation {
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
      match mode {
        NoBodies => {
          let body_bytes = bounded_body(client, max_response_bytes)
          { status: response.code, body_bytes, body: Uncaptured, }
        }
        AutoBodies => {
          let bytes = bounded_body_keep(client, max_response_bytes)
          let classified = classify_body(bytes, response, case.source_line)
          {
            status: response.code,
            body_bytes: bytes.length(),
            body: classified,
          }
        }
      }
    }
  catch {
    // Classification failures already carry their safe description.
    Failed(_, _) as classified => raise classified
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
/// Validate origin, collection and environment. Returns the normalized origin
/// and parsed cases so callers can run their own pre-connection checks.
pub fn preflight(
  text : String,
  base : String,
  env : Map[String, String],
  allow_write~ : Bool = false,
) -> (String, Array[@cases.Case]) raise @cases.ValidationError {
  let origin = @cases.validate_origin(base)
  let cases = @cases.parse_cases(text, allow_write~)
  @cases.validate_env(cases, env)
  (origin, cases)
}

///|
async fn execute_all(
  origin : String,
  cases : Array[@cases.Case],
  env : Map[String, String],
  timeout_ms : Int32,
  mode : @baseline.BodyMode,
) -> Array[Observation] {
  let observations : Array[Observation] = []
  let mut captured = 0
  for case in cases {
    let observation = execute_full(case, origin, env, timeout_ms, mode)
    captured += observation.body_bytes
    if mode is AutoBodies && captured > max_capture_bytes {
      raise Failed(
        case.source_line,
        "captured response bodies exceed 8 MiB in total",
      )
    }
    observations.push(observation)
  }
  observations
}

///|
fn summaries(
  cases : Array[@cases.Case],
  observations : Array[Observation],
) -> Array[Summary] {
  let results : Array[Summary] = []
  for i, case in cases {
    let observation = observations[i]
    results.push(Summary::{
      id: case.id,
      meth: case.meth,
      status: observation.status,
      body_bytes: observation.body_bytes,
    })
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
  let (origin, cases) = preflight(text, base, env, allow_write~)
  let observations = execute_all(
    origin,
    cases,
    env,
    request_timeout_ms,
    NoBodies,
  )
  summaries(cases, observations)
}

///|
/// Preflight the entire collection, then capture responses for a baseline.
pub async fn capture(
  text : String,
  base : String,
  env : Map[String, String],
  mode~ : @baseline.BodyMode,
  allow_write~ : Bool = false,
) -> Array[@baseline.Record] {
  let (origin, cases) = preflight(text, base, env, allow_write~)
  capture_cases(origin, cases, env, mode~)
}

///|
/// Execute preflighted cases sequentially, returning baseline records.
pub async fn capture_cases(
  origin : String,
  cases : Array[@cases.Case],
  env : Map[String, String],
  mode~ : @baseline.BodyMode,
) -> Array[@baseline.Record] {
  let observations = execute_all(origin, cases, env, request_timeout_ms, mode)
  let records : Array[@baseline.Record] = []
  for i, case in cases {
    let observation = observations[i]
    records.push(
      @baseline.Record::make(
        case.id,
        case.meth,
        @baseline.request_fingerprint(case),
        observation.status,
        observation.body,
      ),
    )
  }
  records
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
