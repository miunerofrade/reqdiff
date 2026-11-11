///|
suberror InputFailure {
  InputFailure(String)
}

///|
// Regular file only; reads at most limit + 1 bytes with a fixed buffer, so a
// file that grows after open cannot turn into an unbounded read.
async fn read_bounded(
  path : String,
  limit : Int32,
  over_limit : String,
) -> String {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  if file.kind() != Regular {
    raise InputFailure("input must be a regular file")
  }
  let buffer = FixedArray::make(limit + 1, b'\x00')
  let mut used = 0
  while used < buffer.length() {
    let count = file.read_into(
      buffer,
      offset=used,
      max_len=buffer.length() - used,
    )
    if count == 0 {
      break
    }
    used += count
  }
  if used > limit {
    raise InputFailure(over_limit)
  }
  let bytes = Bytes::makei(used, i => buffer[i])
  @utf8.decode(bytes[:]) catch {
    _ => raise InputFailure("input must be valid UTF-8")
  }
}

///|
async fn read_cases(path : String) -> String {
  read_bounded(path, @cases.max_file_bytes, "input exceeds 5 MiB")
}

///|
async fn read_baseline(path : String) -> String {
  read_bounded(path, @baseline.max_baseline_bytes, "baseline exceeds 32 MiB")
}

///|
// Write content to a unique temporary file next to the target, sync, close,
// then rename onto the target. Never leaves a partial file; without force the
// rename (and a pre-check) refuses to replace an existing baseline.
async fn write_baseline_atomic(
  path : String,
  content : Bytes,
  force : Bool,
) -> Unit {
  let mut temp = ""
  for attempt in 0..<64 {
    let candidate = "\{path}.reqdiff-tmp-\{attempt}"
    if @fs.exists(candidate) {
      continue
    }
    temp = candidate
    break
  }
  if temp is "" {
    raise InputFailure("cannot write baseline")
  }
  let published = try {
    let file = @fs.open(temp, mode=WriteOnly, create_mode=CreateNew)
    defer file.close()
    file.write(content[:])
    file.sync()
    @fs.rename(temp, path, replace=force)
    true
  } catch {
    _ => false
  }
  if !published {
    @fs.remove(temp, allow_missing=true)
    if !force && @fs.exists(path) {
      raise InputFailure("baseline already exists; use --force")
    }
    raise InputFailure("cannot write baseline")
  }
}
