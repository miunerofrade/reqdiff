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
    Record(path, origin, out, body_auto, force, allow_write) => {
      try {
        let _ = @cases.validate_origin(origin)
      } catch {
        error => {
          emit_error(error.to_string())
          @env.exit(2)
        }
      }
      let exists = @fs.exists(out) catch {
        _ => {
          emit_error("cannot inspect baseline target")
          @env.exit(2)
        }
      }
      if exists && !force {
        emit_error("baseline already exists; use --force")
        @env.exit(2)
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
      let mode = if body_auto {
        @baseline.AutoBodies
      } else {
        @baseline.NoBodies
      }
      let records = @runner.capture(text, origin, env, mode~, allow_write~) catch {
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
      let encoded = @baseline.encode(@baseline.Baseline::make(mode, records))
      let content = @utf8.encode(encoded)
      if content.length() > @baseline.max_baseline_bytes {
        emit_error("encoded baseline exceeds 32 MiB")
        @env.exit(2)
      }
      // Never publish a baseline that the strict reader cannot consume.
      try {
        let _ = @baseline.parse(encoded)
      } catch {
        error => {
          emit_error(error.to_string())
          @env.exit(2)
        }
      }
      write_baseline_atomic(out, content, force) catch {
        InputFailure(message) => {
          emit_error(message)
          @env.exit(2)
        }
        _ => {
          emit_error("cannot write baseline")
          @env.exit(2)
        }
      }
      println("RECORDED: \{records.length()} case(s)")
    }
    Diff(path, origin, baseline_path, ignores, format, allow_write) => {
      try {
        let _ = @cases.validate_origin(origin)
      } catch {
        error => {
          emit_error(error.to_string())
          @env.exit(2)
        }
      }
      let baseline_text = read_baseline(baseline_path) catch {
        InputFailure(message) => {
          emit_error(message)
          @env.exit(2)
        }
        _ => {
          emit_error("cannot read baseline file")
          @env.exit(2)
        }
      }
      let baseline = @baseline.parse(baseline_text) catch {
        error => {
          emit_error(error.to_string())
          @env.exit(2)
        }
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
      let (_, cases) = @runner.preflight(text, origin, env, allow_write~) catch {
        error => {
          emit_error(error.to_string())
          @env.exit(2)
        }
      }
      // Configuration errors must surface before any connection is made.
      @baseline.check_match(baseline, cases) catch {
        error => {
          emit_error(error.to_string())
          @env.exit(2)
        }
      }
      let pointers = @compare.compile_ignores(ignores) catch {
        error => {
          emit_error(error.to_string())
          @env.exit(2)
        }
      }
      let observed = @runner.capture_cases(
        origin,
        cases,
        env,
        mode=@baseline.Baseline::mode(baseline),
      ) catch {
        @runner.Failed(line, reason) => {
          emit_error("line \{line}, field request: \{reason}")
          @env.exit(2)
        }
        _ => {
          emit_error("request execution failed")
          @env.exit(2)
        }
      }
      let report = @compare.compare(
        @baseline.Baseline::records(baseline),
        observed,
        pointers,
      )
      let output = if format == "json" {
        @report.render_json(report)
      } else {
        @report.render_terminal(report)
      }
      println(output)
      if report.total_differences > 0 {
        @env.exit(1)
      }
    }
  }
}
