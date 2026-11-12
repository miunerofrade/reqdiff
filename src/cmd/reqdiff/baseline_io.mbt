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
  // Follow symlinks consistently: links to regular files remain supported.
  // Prestat avoids blocking on ordinary FIFO input, but is not TOCTOU-free:
  // the path can change before open. Bound that cancellable open as well,
  // then verify the opened handle rather than trusting the path check.
  let file = @async.with_timeout(10000, () => {
    if @fs.kind(path, follow_symlink=true) != Regular {
      raise InputFailure("input must be a regular file")
    }
    @fs.open(path, mode=ReadOnly)
  })
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
// Reserve a temporary file next to the target using atomic CreateNew, sync,
// explicitly close, then publish with an atomic rename. Only a successfully
// reserved temporary file belongs to this writer and may be cleaned up.
// This assumes the output directory is not being maliciously modified.
async fn write_baseline_atomic(
  path : String,
  content : Bytes,
  force : Bool,
) -> Unit {
  for attempt in 0..<64 {
    let temp = "\{path}.reqdiff-tmp-\{attempt}"
    let file = Some(
      @fs.open(temp, mode=WriteOnly, create_mode=CreateNew, permission=0o600),
    ) catch {
      // Never remove a candidate when exclusive creation failed: another
      // writer (or a pre-existing file) owns it. Retry a fresh candidate.
      _ => None
    }
    guard file is Some(file) else { continue }
    let mut published = false
    defer {
      file.close()
      // Defer also runs for cancellation, which ordinary catch does not catch.
      if !published {
        @fs.remove(temp, allow_missing=true)
      }
    }
    let completed = try {
      file.write(content[:])
      file.sync()
      file.close()
      @fs.rename(temp, path, replace=force)
      published = true
      true
    } catch {
      _ => false
    }
    if !completed {
      if !force && @fs.exists(path) {
        raise InputFailure("baseline already exists; use --force")
      }
      raise InputFailure("cannot write baseline")
    }
    return
  }
  raise InputFailure("cannot write baseline")
}
