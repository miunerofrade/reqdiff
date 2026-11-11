///|
fn credential_header_name(name : String) -> Bool {
  name.contains("auth") ||
  name.contains("token") ||
  name.contains("secret") ||
  name.contains("api-key") ||
  name.contains("apikey")
}

///|
/// SHA-256 over a canonical projection of the request: version marker, method,
/// validated path (query and escapes preserved), literal non-credential headers
/// sorted by lowercase name, then body kind/content. Env-referenced headers are
/// excluded entirely; runner-derived defaults (Host, Content-Length, User-Agent,
/// Accept-Encoding) are not part of identity. The projection itself is never
/// stored or printed; a digest is not redaction, only non-identity by design.
pub fn request_fingerprint(case : @cases.Case) -> String {
  let builder = StringBuilder()
  builder.write_string("reqdiff-request-v1\n")
  builder.write_string(case.meth)
  builder.write_char('\n')
  builder.write_string(case.path)
  builder.write_char('\n')
  let headers : Array[String] = []
  for name, value in case.headers {
    match value {
      Literal(value) =>
        if !credential_header_name(name) {
          headers.push("\{name}:\{value}")
        }
      Env(_) => ()
    }
  }
  headers.sort()
  for header in headers {
    builder.write_string(header)
    builder.write_char('\n')
  }
  match case.body {
    None => builder.write_string("body=none")
    Some(JsonBody(value)) => {
      builder.write_string("body=json=")
      builder.write_string(value.stringify())
    }
    Some(TextBody(value)) => {
      builder.write_string("body=text=")
      builder.write_string(value)
    }
  }
  "sha256:\{sha256_hex(@utf8.encode(builder.to_string()))}"
}
