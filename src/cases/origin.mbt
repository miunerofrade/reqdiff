///|
fn decimal(s : String, max : Int32) -> Int32? {
  if s.is_empty() {
    return None
  }
  let mut n = 0
  for c in s.iter() {
    if c < '0' || c > '9' {
      return None
    }
    // Check before multiplying, including arbitrarily long port strings.
    let digit = c.to_int() - 48
    if n > (max - digit) / 10 {
      return None
    }
    n = n * 10 + digit
    if n > max {
      return None
    }
  }
  Some(n)
}

///|
fn ipv4(host : String) -> Bool {
  let parts = host.split(".").to_array()
  if parts.length() != 4 {
    return false
  }
  for part in parts {
    // Avoid legacy octal or integer address interpretations.
    if part.length() > 1 && part.has_prefix("0") {
      return false
    }
    if decimal(part.to_owned(), 255) is None {
      return false
    }
  }
  true
}

///|
/// Return number of 16-bit groups; an embedded IPv4 tail occupies two.
fn ipv6_groups(part : String, allow_ipv4 : Bool) -> Int32? {
  if part.is_empty() {
    return Some(0)
  }
  let groups = part.split(":").to_array()
  let mut n = 0
  for i, group in groups {
    if group.is_empty() {
      return None
    }
    if group.contains(".") {
      if !allow_ipv4 || i != groups.length() - 1 || !ipv4(group.to_owned()) {
        return None
      }
      n += 2
    } else {
      if group.length() > 4 {
        return None
      }
      for c in group.to_owned().iter() {
        if hex(c) < 0 {
          return None
        }
      }
      n += 1
    }
  }
  Some(n)
}

///|
fn ipv6(host : String) -> Bool {
  if host.contains("::") {
    let halves = host.split("::").to_array()
    if halves.length() != 2 {
      return false
    }
    match
      (
        ipv6_groups(halves[0].to_owned(), false),
        ipv6_groups(halves[1].to_owned(), true),
      ) {
      (Some(left), Some(right)) => left + right < 8
      _ => false
    }
  } else {
    ipv6_groups(host, true) == Some(8)
  }
}

///|
/// Conservative ASCII DNS host syntax, not a DNS existence check or IDNA parser.
fn domain(host : String) -> Bool {
  if host.is_empty() || host.length() > 253 {
    return false
  }
  let labels = host.split(".").to_array()
  let mut all_numeric = true
  for label in labels {
    let cs = label.to_owned().to_array()
    if cs.length() == 0 ||
      cs.length() > 63 ||
      !ascii_alnum(cs[0]) ||
      !ascii_alnum(cs[cs.length() - 1]) {
      return false
    }
    for c in cs {
      if !(ascii_alnum(c) || c == '-') {
        return false
      }
      if c < '0' || c > '9' {
        all_numeric = false
      }
    }
  }
  if all_numeric {
    return ipv4(host)
  }
  // Numeric final labels are ambiguous with legacy IPv4 parsing in URL clients.
  let last = labels[labels.length() - 1]
  if last.has_prefix("0x") && last.length() > 2 {
    let mut hexadecimal = true
    for c in last[2:].to_owned().iter() {
      if hex(c) < 0 {
        hexadecimal = false
      }
    }
    if hexadecimal {
      return false
    }
  }
  let mut last_numeric = true
  for c in last.to_owned().iter() {
    if c < '0' || c > '9' {
      last_numeric = false
    }
  }
  !last_numeric
}

///| Only a bare http(s) origin is allowed. Scheme/host are lowercased, a single

///|
/// trailing slash is removed, and a numeric port is canonicalized. No I/O.
pub fn validate_origin(input : String) -> String raise ValidationError {
  for c in input.iter() {
    if control(c) || c == ' ' || c == '\\' || c.to_int() > 126 {
      invalid(0, "origin", "contains a forbidden character")
    }
  }
  let lower = input.to_lower()
  let (scheme, rest) = if lower.has_prefix("http://") {
    ("http://", lower[7:].to_owned())
  } else if lower.has_prefix("https://") {
    ("https://", lower[8:].to_owned())
  } else {
    invalid(0, "origin", "scheme must be http or https")
    ("", "")
  }
  let authority = if rest.has_suffix("/") {
    rest[:rest.length() - 1].to_owned()
  } else {
    rest
  }
  if authority.is_empty() || authority.contains_any(chars="/?#@\\") {
    invalid(0, "origin", "expected a host and optional port only")
  }
  let (host, port) = if authority.has_prefix("[") {
    let parts = authority.split("]").to_array()
    if parts.length() != 2 {
      invalid(0, "origin", "invalid bracketed IPv6 host")
    }
    let raw = parts[0][1:].to_owned()
    if !ipv6(raw) {
      invalid(0, "origin", "invalid IPv6 host")
    }
    let tail = parts[1]
    let port = if tail.is_empty() {
      None
    } else if tail.has_prefix(":") {
      Some(tail[1:].to_owned())
    } else {
      invalid(0, "origin", "invalid port suffix")
      None
    }
    ("[\{raw}]", port)
  } else {
    let parts = authority.split(":").to_array()
    if parts.length() > 2 {
      invalid(0, "origin", "IPv6 hosts must be bracketed")
    }
    let host = parts[0].to_owned()
    if !domain(host) {
      invalid(0, "origin", "invalid host")
    }
    (host, if parts.length() == 2 { Some(parts[1].to_owned()) } else { None })
  }
  let suffix = match port {
    None => ""
    Some(s) =>
      match decimal(s, 65535) {
        Some(n) if n >= 1 => ":\{n}"
        _ => {
          invalid(0, "origin", "port must be between 1 and 65535")
          ""
        }
      }
  }
  "\{scheme}\{host}\{suffix}"
}
