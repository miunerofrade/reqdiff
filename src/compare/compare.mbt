///|
pub(all) suberror CompareError {
  InvalidPointer(Int32, String)
}

///|
pub fn CompareError::to_string(self : CompareError) -> String {
  match self {
    InvalidPointer(index, reason) =>
      "ignore flag \{index}, field pointer: \{reason}"
  }
}

///|
pub(all) struct Pointer {
  tokens : Array[String]
}

///|
fn invalid_pointer(ordinal : Int32, reason : String) -> Unit raise CompareError {
  raise InvalidPointer(ordinal, reason)
}

///|
fn compile_pointer(
  text : String,
  ordinal : Int32,
) -> Pointer raise CompareError {
  if text is "" {
    return Pointer::{ tokens: [], }
  }
  if !text.has_prefix("/") {
    invalid_pointer(ordinal, "must be empty or start with a slash")
  }
  let tokens : Array[String] = []
  let builder = StringBuilder()
  let mut escaped = false
  let mut first = true
  for c in text.iter() {
    if first {
      // Consume the leading slash that starts the first token.
      first = false
      continue
    }
    if escaped {
      match c {
        '0' => builder.write_char('~')
        '1' => builder.write_char('/')
        _ => invalid_pointer(ordinal, "invalid tilde escape")
      }
      escaped = false
    } else {
      match c {
        '~' => escaped = true
        '/' => {
          tokens.push(builder.to_string())
          builder.reset()
        }
        _ => builder.write_char(c)
      }
    }
  }
  if escaped {
    invalid_pointer(ordinal, "dangling tilde escape")
  }
  tokens.push(builder.to_string())
  Pointer::{ tokens, }
}

///|
/// Compile strict RFC 6901 pointers. The ordinal is the one-based flag number
/// used in diagnostics; pointer text itself is never echoed.
pub fn compile_ignores(
  pointers : Array[String],
) -> Array[Pointer] raise CompareError {
  let result : Array[Pointer] = []
  for i, pointer in pointers {
    result.push(compile_pointer(pointer, i + 1))
  }
  result
}

///|
// Unambiguous token path key: per-token length prefix, then the token bytes.
fn path_key(tokens : Array[String]) -> String {
  let builder = StringBuilder()
  for token in tokens {
    builder.write_string("\{token.length()}:\{token}")
  }
  builder.to_string()
}

///|
let zero_key = "z"

///|
// Reverse a digit array without relying on deprecated collection Show.
fn reverse_digits(digits : Array[Char]) -> Array[Char] {
  let out : Array[Char] = []
  for k in 0..<digits.length() {
    out.push(digits[digits.length() - 1 - k])
  }
  out
}

///|
// Addition of non-negative decimal digit strings, most significant first.
fn add_digits(a : Array[Char], b : Array[Char]) -> Array[Char] {
  let result : Array[Char] = []
  let mut carry = 0
  let mut i = 1
  while i <= a.length() || i <= b.length() {
    let mut sum = carry
    if i <= a.length() {
      sum += a[a.length() - i].to_int() - 48
    }
    if i <= b.length() {
      sum += b[b.length() - i].to_int() - 48
    }
    result.push((48 + sum % 10).to_char().unwrap())
    carry = sum / 10
    i += 1
  }
  if carry > 0 {
    result.push((48 + carry).to_char().unwrap())
  }
  reverse_digits(result)
}

///|
fn cmp_digits(a : Array[Char], b : Array[Char]) -> Int32 {
  if a.length() != b.length() {
    return a.length() - b.length()
  }
  for i in 0..<a.length() {
    let difference = a[i].to_int() - b[i].to_int()
    if difference != 0 {
      return difference
    }
  }
  0
}

///|
// Subtraction of digit strings, requiring a >= b.
fn sub_digits(a : Array[Char], b : Array[Char]) -> Array[Char] {
  let result : Array[Char] = []
  let mut borrow = 0
  let mut i = 1
  while i <= a.length() {
    let mut diff = borrow + a[a.length() - i].to_int() - 48
    if i <= b.length() {
      diff -= b[b.length() - i].to_int() - 48
    }
    if diff < 0 {
      diff += 10
      borrow = -1
    } else {
      borrow = 0
    }
    result.push((48 + diff).to_char().unwrap())
    i += 1
  }
  let reversed = reverse_digits(result)
  // Strip leading zeros, keeping one digit.
  let mut start = 0
  while start < reversed.length() - 1 && reversed[start] == '0' {
    start += 1
  }
  let stripped : Array[Char] = []
  for k in start..<reversed.length() {
    stripped.push(reversed[k])
  }
  stripped
}

///|
fn int_to_digits(value : Int32) -> Array[Char] {
  let reversed : Array[Char] = []
  let mut rest = value
  if rest == 0 {
    reversed.push('0')
  }
  while rest > 0 {
    reversed.push((48 + rest % 10).to_char().unwrap())
    rest /= 10
  }
  reverse_digits(reversed)
}

///|
fn strip_leading_zeros(digits : Array[Char]) -> Array[Char] {
  let mut start = 0
  while start < digits.length() - 1 && digits[start] == '0' {
    start += 1
  }
  let stripped : Array[Char] = []
  for k in start..<digits.length() {
    stripped.push(digits[k])
  }
  stripped
}

///|
/// Exact decimal key without Double conversion: sign, significant digits and
/// exponent as digit strings. 1 = 1.0 = 1e0, -0 = 0, huge exponents stay
/// unexpanded. repr=None falls back to the Double's shortest form.
fn canonical_number(repr : String) -> String {
  let chars = repr.to_array()
  let mut i = 0
  let mut neg = false
  if i < chars.length() && chars[i] == '-' {
    neg = true
    i += 1
  }
  let digits : Array[Char] = []
  let mut frac_len = 0
  while i < chars.length() && chars[i] >= '0' && chars[i] <= '9' {
    digits.push(chars[i])
    i += 1
  }
  if i < chars.length() && chars[i] == '.' {
    i += 1
    while i < chars.length() && chars[i] >= '0' && chars[i] <= '9' {
      digits.push(chars[i])
      frac_len += 1
      i += 1
    }
  }
  // The decimal point shifts the value: exp = explicit - fraction length.
  let mut exp_neg = false
  let mut exp_digits : Array[Char] = ['0']
  if i < chars.length() && (chars[i] == 'e' || chars[i] == 'E') {
    i += 1
    if i < chars.length() && chars[i] == '+' {
      i += 1
    } else if i < chars.length() && chars[i] == '-' {
      exp_neg = true
      i += 1
    }
    let raw : Array[Char] = []
    while i < chars.length() {
      raw.push(chars[i])
      i += 1
    }
    exp_digits = strip_leading_zeros(raw)
    if exp_digits.length() == 1 && exp_digits[0] == '0' {
      exp_neg = false
    }
  }
  if frac_len > 0 {
    let frac = int_to_digits(frac_len)
    if exp_neg {
      exp_digits = add_digits(exp_digits, frac)
    } else {
      match cmp_digits(exp_digits, frac) {
        order if order < 0 => {
          exp_digits = sub_digits(frac, exp_digits)
          exp_neg = true
        }
        0 => {
          exp_digits = ['0']
          exp_neg = false
        }
        _ => exp_digits = sub_digits(exp_digits, frac)
      }
    }
  }
  let mantissa = strip_leading_zeros(digits)
  // All-zero mantissa is zero regardless of sign or exponent.
  let mut all_zero = true
  for c in mantissa {
    if c != '0' {
      all_zero = false
      break
    }
  }
  if all_zero {
    return zero_key
  }
  // Fold trailing mantissa zeros into the exponent with one string operation.
  let mut trailing = 0
  while mantissa[mantissa.length() - 1 - trailing] == '0' {
    trailing += 1
  }
  let significant = mantissa.length() - trailing
  if trailing > 0 {
    let shift = int_to_digits(trailing)
    if exp_neg {
      match cmp_digits(exp_digits, shift) {
        order if order < 0 => {
          exp_digits = sub_digits(shift, exp_digits)
          exp_neg = false
        }
        0 => {
          exp_digits = ['0']
          exp_neg = false
        }
        _ => exp_digits = sub_digits(exp_digits, shift)
      }
    } else {
      exp_digits = add_digits(exp_digits, shift)
    }
  }
  let builder = StringBuilder()
  if neg {
    builder.write_char('-')
  }
  for k in 0..<significant {
    builder.write_char(mantissa[k])
  }
  builder.write_char('e')
  if exp_neg {
    builder.write_char('-')
  }
  for c in exp_digits {
    builder.write_char(c)
  }
  builder.to_string()
}

///|

///|
fn number_key(number : Double, repr : String?) -> String {
  match repr {
    Some(text) => canonical_number(text)
    // Without a preserved representation (values built in code, not parsed),
    // the Double itself decides; finite values stringify uniquely.
    None =>
      if number.is_finite() {
        canonical_number(number.to_string())
      } else {
        "nonfinite"
      }
  }
}

///|
fn count_difference(counter : Array[Int32]) -> Unit {
  counter[0] += 1
}

///|
fn diff_json(
  a : @json.Json,
  b : @json.Json,
  path : Array[String],
  ignores : Map[String, Bool],
  counter : Array[Int32],
) -> Unit {
  if ignores.contains(path_key(path)) {
    return
  }
  match (a, b) {
    (Object(ma), Object(mb)) => {
      for key, _ in ma {
        if !mb.contains(key) &&
          !ignores.contains(path_key(extend_path(path, key))) {
          count_difference(counter)
        }
      }
      for key, vb in mb {
        let child_path = extend_path(path, key)
        match ma.get(key) {
          Some(va) => diff_json(va, vb, child_path, ignores, counter)
          None =>
            if !ignores.contains(path_key(child_path)) {
              count_difference(counter)
            }
        }
      }
    }
    (Array(aa), Array(ab)) => {
      let length = if aa.length() > ab.length() {
        aa.length()
      } else {
        ab.length()
      }
      for i in 0..<length {
        // Canonical index paths cannot match tokens such as "01" or "-".
        let child_path = extend_path(path, i.to_string())
        if i < aa.length() && i < ab.length() {
          diff_json(aa[i], ab[i], child_path, ignores, counter)
        } else if !ignores.contains(path_key(child_path)) {
          count_difference(counter)
        }
      }
    }
    (Number(na, repr=repra), Number(nb, repr=reprb)) =>
      if number_key(na, repra) != number_key(nb, reprb) {
        count_difference(counter)
      }
    (String(sa), String(sb)) => if sa != sb { count_difference(counter) }
    (True, False) | (False, True) => count_difference(counter)
    (True, True) | (False, False) => ()
    (Null, Null) => ()
    _ => count_difference(counter)
  }
}

///|
fn extend_path(path : Array[String], token : String) -> Array[String] {
  let next : Array[String] = []
  for existing in path {
    next.push(existing)
  }
  next.push(token)
  next
}

///|
pub(all) enum Difference {
  StatusDifference(Int32, Int32)
  BodyKindDifference(String, String)
  JsonBodyDifference(Int32)
  TextBodyDifference
}

///|
/// Never derive Show: only public identifiers live here, but rendering goes
/// through the report package.
pub struct RecordDifference {
  id : String
  meth : String
  differences : Array[Difference]
}

///|
pub struct Report {
  cases : Int32
  records : Array[RecordDifference]
  total_differences : Int32
  differing_cases : Int32
  truncated : Bool
}

///|
fn kind_name(body : @baseline.RecordedBody) -> String {
  match body {
    Uncaptured => "uncaptured"
    Empty => "empty"
    JsonBody(_) => "json"
    TextBody(_) => "text"
  }
}

///|
/// Differing cases are capped in the report; counts and truncation stay exact.
pub let max_report_records : Int32 = 50

///|
/// Compare two already-matched sides. Order follows the observed (case file)
/// order; recorded IDs missing from the observation append at the end.
pub fn compare(
  recorded : Array[@baseline.Record],
  observed : Array[@baseline.Record],
  ignores : Array[Pointer],
) -> Report {
  let ignore_set : Map[String, Bool] = Map([])
  for pointer in ignores {
    ignore_set.set(path_key(pointer.tokens), true)
  }
  let by_id : Map[String, @baseline.Record] = Map([])
  for record in recorded {
    by_id.set(record.id(), record)
  }
  let observed_ids : Map[String, Bool] = Map([])
  let differences : Array[RecordDifference] = []
  let mut total : Int32 = 0
  for observation in observed {
    observed_ids.set(observation.id(), true)
    let record_diffs : Array[Difference] = []
    match by_id.get(observation.id()) {
      None =>
        record_diffs.push(
          BodyKindDifference("missing", kind_name(observation.body())),
        )
      Some(record) => {
        if record.status() != observation.status() {
          record_diffs.push(
            StatusDifference(record.status(), observation.status()),
          )
        }
        let recorded_kind = kind_name(record.body())
        let observed_kind = kind_name(observation.body())
        if recorded_kind != observed_kind {
          record_diffs.push(BodyKindDifference(recorded_kind, observed_kind))
        } else {
          match (record.body(), observation.body()) {
            (JsonBody(a), JsonBody(b)) => {
              let counter : Array[Int32] = [0]
              diff_json(a, b, [], ignore_set, counter)
              if counter[0] > 0 {
                record_diffs.push(JsonBodyDifference(counter[0]))
              }
            }
            (TextBody(a), TextBody(b)) =>
              if a != b {
                record_diffs.push(TextBodyDifference)
              }
            _ => ()
          }
        }
      }
    }
    if record_diffs.length() > 0 {
      total += record_diffs.length()
      differences.push(RecordDifference::{
        id: observation.id(),
        meth: observation.meth(),
        differences: record_diffs,
      })
    }
  }
  for record in recorded {
    if !observed_ids.contains(record.id()) {
      total += 1
      differences.push(RecordDifference::{
        id: record.id(),
        meth: record.meth(),
        differences: [BodyKindDifference(kind_name(record.body()), "missing")],
      })
    }
  }
  let differing_cases = differences.length()
  let truncated = differing_cases > max_report_records
  let kept : Array[RecordDifference] = []
  for i, difference in differences {
    if i >= max_report_records {
      break
    }
    kept.push(difference)
  }
  Report::{
    cases: observed.length(),
    records: kept,
    total_differences: total,
    differing_cases,
    truncated,
  }
}
