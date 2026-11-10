///|
suberror InputFailure {
  InputFailure(String)
}

///|
async fn read_cases(path : String) -> String {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  if file.kind() != Regular {
    raise InputFailure("input must be a regular file")
  }
  // Read at most the budget plus one byte, even if the file grows after open.
  let buffer = FixedArray::make(@cases.max_file_bytes + 1, b'\x00')
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
  if used > @cases.max_file_bytes {
    raise InputFailure("input exceeds 5 MiB")
  }
  let bytes = Bytes::makei(used, i => buffer[i])
  @utf8.decode(bytes[:]) catch {
    _ => raise InputFailure("input must be valid UTF-8")
  }
}

///|
async fn emit_error(message : String) -> Unit {
  @stdio.stderr.write(@utf8.encode("reqdiff: \{message}\n")[:]) catch {
    _ => ()
  }
}

///|
async fn main {
  let argv = @env.args()
  let action = @cli.parse_args(argv[1:].to_owned())
  match action {
    Display(text) => println(text)
    Invalid => {
      // argparse's original error can echo arbitrary arguments. Keep diagnostics safe.
      emit_error("invalid arguments; use --help or <command> --help")
      @env.exit(2)
    }
    Validate(path, _) | Plan(path, _, _) | Run(path, _, _) => {
      match action {
        Plan(_, origin, _) | Run(_, origin, _) =>
          try {
            let _ = @cases.validate_origin(origin)
          } catch {
            error => {
              emit_error(error.to_string())
              @env.exit(2)
            }
          }
        _ => ()
      }
      let text = read_cases(path) catch {
        InputFailure(message) => {
          emit_error(message)
          @env.exit(2)
        }
        _ => {
          emit_error("cannot read input file")
          @env.exit(2)
        }
      }
      let env = @env.get_env_vars()
      let output = match action {
        Run(_, base, allow_write) => {
          let results = @runner.run(text, base, env, allow_write~) catch {
            @cases.InvalidInput(line, field, reason) => {
              emit_error("line \{line}, field \{field}: \{reason}")
              @env.exit(2)
            }
            @runner.Failed(line, reason) => {
              emit_error("line \{line}, field request: \{reason}")
              @env.exit(2)
            }
            _ => {
              emit_error("request execution failed")
              @env.exit(2)
            }
          }
          @runner.render_run(results)
        }
        _ =>
          @cli.evaluate(action, text, env) catch {
            error => {
              emit_error(error.to_string())
              @env.exit(2)
            }
          }
      }
      println(output)
    }
  }
}
