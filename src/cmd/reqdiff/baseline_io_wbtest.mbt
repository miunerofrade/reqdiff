///|
async test "baseline nooverwrite preserves target and skips owned candidates" {
  let dir = @fs.tmpdir(prefix="reqdiff-baseline-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/baseline"
  let occupied = "\{path}.reqdiff-tmp-0"
  @fs.write_text(path, "old")
  @fs.write_text(occupied, "other writer")
  try {
    write_baseline_atomic(path, b"new", false)
    fail("expected nooverwrite rejection")
  } catch {
    InputFailure(message) =>
      assert_eq(message, "baseline already exists; use --force")
    error => raise error
  }
  assert_eq(@fs.read_text(path), "old")
  assert_eq(@fs.read_text(occupied), "other writer")
  assert_eq(@fs.readdir(dir, sort=true), ["baseline", "baseline.reqdiff-tmp-0"])
}

///|
async test "baseline force replaces target and cleans only its own temp" {
  let dir = @fs.tmpdir(prefix="reqdiff-baseline-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/baseline"
  let occupied = "\{path}.reqdiff-tmp-0"
  @fs.write_text(path, "old")
  @fs.write_text(occupied, "other writer")
  write_baseline_atomic(path, b"new", true)
  assert_eq(@fs.read_text(path), "new")
  assert_eq(@fs.read_text(occupied), "other writer")
  assert_eq(@fs.readdir(dir, sort=true), ["baseline", "baseline.reqdiff-tmp-0"])
}

///|
async test "baseline failed rename preserves old target and removes reserved temp" {
  let dir = @fs.tmpdir(prefix="reqdiff-baseline-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/baseline"
  // A regular temporary file cannot replace this nonempty directory on either
  // Windows or Unix. Failure occurs after writing, syncing and closing it.
  @fs.mkdir(path)
  @fs.write_text("\{path}/old", "keep")
  try {
    write_baseline_atomic(path, b"new", true)
    fail("expected rename failure")
  } catch {
    InputFailure(message) => assert_eq(message, "cannot write baseline")
    error => raise error
  }
  assert_eq(@fs.read_text("\{path}/old"), "keep")
  assert_eq(@fs.readdir(dir), ["baseline"])
}

///|
async test "baseline two concurrent writers publish exactly one complete baseline" {
  @async.with_timeout(10000, () => {
    let dir = @fs.tmpdir(prefix="reqdiff-baseline-")
    defer @fs.rmdir(dir, recursive=true)
    for attempt in 0..<8 {
      let path = "\{dir}/baseline-\{attempt}"
      let results : Array[Bool] = []
      @async.with_task_group() <| group => {
        for content in [b"first", b"second"] {
          group.spawn_bg(() => {
            let success = try {
              write_baseline_atomic(path, content, false)
              true
            } catch {
              InputFailure(message) => {
                assert_eq(message, "baseline already exists; use --force")
                false
              }
              error => raise error
            }
            results.push(success)
          })
        }
      }
      assert_eq(results.length(), 2)
      assert_true(results[0] != results[1])
      let stored = @fs.read_text(path)
      assert_true(stored == "first" || stored == "second")
      @fs.remove(path)
      assert_eq(@fs.readdir(dir), [])
    }
  })
}

///|
async test "baseline exhausted candidates leave all foreign files untouched" {
  let dir = @fs.tmpdir(prefix="reqdiff-baseline-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/baseline"
  for attempt in 0..<64 {
    @fs.write_text("\{path}.reqdiff-tmp-\{attempt}", "foreign")
  }
  try {
    write_baseline_atomic(path, b"new", true)
    fail("expected bounded allocation failure")
  } catch {
    InputFailure(message) => assert_eq(message, "cannot write baseline")
    error => raise error
  }
  assert_false(@fs.exists(path))
  assert_eq(@fs.readdir(dir).length(), 64)
  for attempt in 0..<64 {
    assert_eq(@fs.read_text("\{path}.reqdiff-tmp-\{attempt}"), "foreign")
  }
}

///|
async test "bounded input accepts regular files and rejects directories" {
  let dir = @fs.tmpdir(prefix="reqdiff-input-")
  defer @fs.rmdir(dir, recursive=true)
  @fs.write_text("\{dir}/file", "hello")
  assert_eq(read_bounded("\{dir}/file", 5, "too large"), "hello")
  try {
    ignore(read_bounded("\{dir}/file", 4, "too large"))
    fail("expected size rejection")
  } catch {
    InputFailure(message) => assert_eq(message, "too large")
    error => raise error
  }
  try {
    ignore(read_bounded(dir, 5, "too large"))
    fail("expected directory rejection")
  } catch {
    InputFailure(message) => assert_eq(message, "input must be a regular file")
    error => raise error
  }
}

///|
#cfg(all(target="native", platform="windows"))
async test "bounded input rejects Windows directory junctions" {
  @async.with_timeout(5000, () => {
    let dir = @fs.tmpdir(prefix="reqdiff-input-")
    defer @fs.rmdir(dir, recursive=true)
    let target = "\{dir}/directory"
    let link = "\{dir}/junction"
    @fs.mkdir(target)
    let result = @process.run(
      "cmd.exe",
      [
        "/d",
        "/c",
        "mklink",
        "/J",
        link.replace_all(old="/", new="\\"),
        target.replace_all(old="/", new="\\"),
      ],
      stdout=Collect,
      stderr=Collect,
    )
    assert_eq(result.exit_code, 0)
    try {
      ignore(read_bounded(link, 5, "too large"))
      fail("expected junction to directory rejection")
    } catch {
      InputFailure(message) =>
        assert_eq(message, "input must be a regular file")
      error => raise error
    }
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "baseline Unix permissions are 600 after create and force" {
  let dir = @fs.tmpdir(prefix="reqdiff-mode-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/baseline"
  for force in [false, true] {
    if force {
      @fs.chmod(path, 0o644)
    }
    write_baseline_atomic(path, b"private", force)
    // GNU and BSD stat use different flags. Pass the path as an argument,
    // never interpolate it into shell source.
    let result = @process.run(
      "sh",
      [
        "-c", "mode=$(stat -c %a \"$1\" 2>/dev/null) || mode=$(stat -f %Lp \"$1\"); test \"$mode\" = 600",
        "reqdiff-mode", path,
      ],
      stdout=Collect,
      stderr=Collect,
    )
    assert_eq(result.exit_code, 0)
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "bounded input rejects FIFO promptly and keeps regular symlink support" {
  @async.with_timeout(2000, () => {
    let dir = @fs.tmpdir(prefix="reqdiff-input-")
    defer @fs.rmdir(dir, recursive=true)
    let fifo = "\{dir}/fifo"
    let result = @process.run("mkfifo", [fifo], stdout=Collect, stderr=Collect)
    assert_eq(result.exit_code, 0)
    try {
      ignore(read_bounded(fifo, 5, "too large"))
      fail("expected FIFO rejection")
    } catch {
      InputFailure(message) =>
        assert_eq(message, "input must be a regular file")
      error => raise error
    }
    @fs.write_text("\{dir}/regular", "hello")
    @fs.symlink(target="\{dir}/regular", "\{dir}/link")
    assert_eq(read_bounded("\{dir}/link", 5, "too large"), "hello")
    @fs.symlink(target=fifo, "\{dir}/fifo-link")
    try {
      ignore(read_bounded("\{dir}/fifo-link", 5, "too large"))
      fail("expected symlink to FIFO rejection")
    } catch {
      InputFailure(message) =>
        assert_eq(message, "input must be a regular file")
      error => raise error
    }
  })
}
