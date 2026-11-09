///|
pub(all) enum Action {
  Display(String)
  Validate(String, Bool)
  Plan(String, String, Bool)
  Invalid
}

///|
fn command() -> @argparse.Command {
  @argparse.Command(
    "reqdiff",
    version="0.1.0-dev",
    about="Offline HTTP request collection validation and planning. No requests are sent.",
    subcommand_required=true,
    subcommands=[
      @argparse.Command(
        "validate",
        about="Validate a JSONL request collection without network access.",
        flags=[
          @argparse.FlagArg(
            "allow-write",
            about="Permit non-GET/HEAD cases in the input; does not execute them.",
          ),
        ],
        positionals=[
          @argparse.PositionArg(
            "cases",
            num_args=@argparse.ValueRange::single(),
          ),
        ],
      ),
      @argparse.Command(
        "plan",
        about="Show a redacted offline plan. Paths, queries, bodies and credentials are omitted.",
        flags=[
          @argparse.FlagArg(
            "allow-write",
            about="Permit non-GET/HEAD cases in the input; does not execute them.",
          ),
        ],
        options=[
          @argparse.OptionArg(
            "base-url",
            required=true,
            about="Explicit HTTP(S) origin, for example http://127.0.0.1:8080",
          ),
        ],
        positionals=[
          @argparse.PositionArg(
            "cases",
            num_args=@argparse.ValueRange::single(),
          ),
        ],
      ),
    ],
  )
}

///|
pub fn parse_args(argv : Array[String]) -> Action {
  match @argparse.parse_outcome(command(), argv=argv[:]) {
    Help(text) | Version(text) => Display(text)
    Failed(_) => Invalid
    Parsed(matches) =>
      match matches.subcommand {
        Some((name, sub)) => {
          let file = sub.values.get("cases").unwrap_or([])
          if file.length() != 1 {
            return Invalid
          }
          let allow_write = sub.flags.get("allow-write").unwrap_or(false)
          if name == "validate" {
            Validate(file[0], allow_write)
          } else if name == "plan" {
            let base = sub.values.get("base-url").unwrap_or([])
            if base.length() != 1 {
              return Invalid
            }
            Plan(file[0], base[0], allow_write)
          } else {
            Invalid
          }
        }
        None => Invalid
      }
  }
}

///|
pub fn help_text() -> String {
  command().render_help()
}

///|
pub fn evaluate(
  action : Action,
  text : String,
  env : Map[String, String],
) -> String raise @cases.ValidationError {
  match action {
    Display(text) => text
    Validate(_, allow_write) => {
      let cases = @cases.parse_cases(text, allow_write~)
      @cases.validate_env(cases, env)
      "VALID: \{cases.length()} case(s); no requests sent"
    }
    Plan(_, base, allow_write) => {
      let origin = @cases.validate_origin(base)
      let cases = @cases.parse_cases(text, allow_write~)
      @cases.validate_env(cases, env)
      let lines = [
        "PLAN: \{cases.length()} case(s); no requests sent",
        "origin: \{origin}",
      ]
      for line in @cases.render_plan(cases) {
        lines.push(line)
      }
      lines.join("\n")
    }
    Invalid => ""
  }
}
