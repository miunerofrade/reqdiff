///|
/// Record index is zero for file-level problems, one-based otherwise.
/// Messages carry only static descriptions, never baseline contents.
pub(all) suberror BaselineError {
  InvalidBaseline(Int32, String, String)
  RequestMismatch(Int32)
}

///|
pub fn BaselineError::to_string(self : BaselineError) -> String {
  match self {
    InvalidBaseline(index, field, reason) =>
      match index {
        0 => "field \{field}: \{reason}"
        index => "record \{index}, field \{field}: \{reason}"
      }
    RequestMismatch(index) =>
      "line \{index}: request no longer matches the baseline"
  }
}

///|
pub fn BaselineError::output(self : BaselineError, logger : &Logger) -> Unit {
  logger.write_string(self.to_string())
}

///|
pub impl Show for BaselineError with fn output(self, logger) {
  self.output(logger)
}

///|
#derive(Eq)
pub(all) enum BodyMode {
  NoBodies
  AutoBodies
}

///|
/// Explicit promotion keeps derived Eq methods callable under --deny-warn.
pub extend BodyMode with Eq::{not_equal, equal}

///|
fn body_mode_name(mode : BodyMode) -> String {
  match mode {
    NoBodies => "none"
    AutoBodies => "auto"
  }
}

///|
/// Uncaptured is only valid with NoBodies; Empty is a captured zero-byte body,
/// distinct from a captured JSON null.
pub(all) enum RecordedBody {
  Uncaptured
  Empty
  JsonBody(@json.Json)
  TextBody(String)
}

///|
/// Never derive Show: recorded bodies may contain private response data.
pub struct Record {
  id : String
  meth : String
  fingerprint : String
  status : Int32
  body : RecordedBody
}

///|
/// Construct from validated capture or parse results; callers own validation.
pub fn Record::make(
  id : String,
  meth : String,
  fingerprint : String,
  status : Int32,
  body : RecordedBody,
) -> Record {
  { id, meth, fingerprint, status, body, }
}

///|
/// Symmetric comparison input; construct via Record::make.
pub struct Baseline {
  mode : BodyMode
  records : Array[Record]
}

///|
pub fn Baseline::make(mode : BodyMode, records : Array[Record]) -> Baseline {
  { mode, records, }
}

///|
pub fn Baseline::mode(self : Baseline) -> BodyMode {
  self.mode
}

///|
pub fn Baseline::records(self : Baseline) -> Array[Record] {
  self.records
}

///|
/// Read-only accessors; constructors stay package-private via parse/encode.
pub fn Record::id(self : Record) -> String {
  self.id
}

///|
pub fn Record::meth(self : Record) -> String {
  self.meth
}

///|
pub fn Record::status(self : Record) -> Int32 {
  self.status
}

///|
pub fn Record::body(self : Record) -> RecordedBody {
  self.body
}
