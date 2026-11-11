///|
pub(all) enum Action {
  Display(String)
  Validate(String, Bool)
  Plan(String, String, Bool)
  Run(String, String, Bool)
  Record(String, String, String, Bool, Bool, Bool)
  Diff(String, String, String, Array[String], String, Bool)
  Invalid
}

///|
fn single(values : Array[String]) -> String? {
  if values.length() == 1 {
    Some(values[0])
  } else {
    None
  }
}

///|
fn cases_positional() -> @argparse.PositionArg {
  @argparse.PositionArg("cases", num_args=@argparse.ValueRange::single())
}

///|
fn allow_write_flag(about : StringView) -> @argparse.FlagArg {
  @argparse.FlagArg("allow-write", about~)
}

///|
fn base_url_option() -> @argparse.OptionArg {
  @argparse.OptionArg(
    "base-url",
    required=true,
    about="Explicit HTTP(S) origin, for example http://127.0.0.1:8080",
  )
}

///|
fn command() -> @argparse.Command {
  @argparse.Command(
    "reqdiff",
    version="0.1.0-dev",
    about="Validate, plan, execute or baseline explicit HTTP request collections.",
    subcommand_required=true,
    subcommands=[
      @argparse.Command(
        "validate",
        about="Validate a JSONL request collection without network access.",
        flags=[
          allow_write_flag(
            "Permit non-GET/HEAD cases in the input; does not execute them.",
          ),
        ],
        positionals=[cases_positional()],
      ),
      @argparse.Command(
        "plan",
        about="Show a redacted offline plan. Paths, queries, bodies and credentials are omitted.",
        flags=[
          allow_write_flag(
            "Permit non-GET/HEAD cases in the input; does not execute them.",
          ),
        ],
        options=[base_url_option()],
        positionals=[cases_positional()],
      ),
      @argparse.Command(
        "run",
        about="Send requests sequentially to an authorized origin. No retries or redirects.",
        flags=[
          allow_write_flag(
            "Explicitly permit non-GET/HEAD requests to the target.",
          ),
        ],
        options=[base_url_option()],
        positionals=[cases_positional()],
      ),
      @argparse.Command(
        "record",
        about="Execute the collection and write a response baseline. Bodies are stored only with --body auto and may contain private data.",
        flags=[
          allow_write_flag(
            "Explicitly permit non-GET/HEAD requests to the target.",
          ),
          @argparse.FlagArg("force", about="Replace an existing baseline file."),
        ],
        options=[
          base_url_option(),
          @argparse.OptionArg(
            "out",
            required=true,
            about="Baseline file to write; must not exist unless --force",
          ),
          @argparse.OptionArg(
            "body",
            about="Capture response bodies: none (default) or auto",
          ),
        ],
        positionals=[cases_positional()],
      ),
      @argparse.Command(
        "diff",
        about="Re-execute the collection and compare with a baseline. Reports show counts, never contents.",
        flags=[
          allow_write_flag(
            "Explicitly permit non-GET/HEAD requests to the target.",
          ),
        ],
        options=[
          base_url_option(),
          @argparse.OptionArg(
            "baseline",
            required=true,
            about="Baseline file previously written by record",
          ),
          @argparse.OptionArg(
            "ignore",
            action=@argparse.Append,
            about="JSON Pointer subtree to ignore during JSON comparison; repeatable",
          ),
          @argparse.OptionArg(
            "format",
            about="Report format: terminal (default) or json",
          ),
        ],
        positionals=[cases_positional()],
      ),
    ],
  )
}

///|
fn body_auto(values : Array[String]) -> Bool? {
  match values {
    [] => Some(false)
    ["none"] => Some(false)
    ["auto"] => Some(true)
    _ => None
  }
}

///|
fn report_format(values : Array[String]) -> String? {
  match values {
    [] => Some("terminal")
    ["terminal"] => Some("terminal")
    ["json"] => Some("json")
    _ => None
  }
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
          let base = single(sub.values.get("base-url").unwrap_or([]))
          if name == "validate" {
            Validate(file[0], allow_write)
          } else if base is None {
            Invalid
          } else if name == "plan" {
            Plan(file[0], base.unwrap(), allow_write)
          } else if name == "run" {
            Run(file[0], base.unwrap(), allow_write)
          } else if name == "record" {
            let out = single(sub.values.get("out").unwrap_or([]))
            let body = body_auto(sub.values.get("body").unwrap_or([]))
            let force = sub.flags.get("force").unwrap_or(false)
            match (out, body) {
              (Some(out), Some(body_auto)) =>
                Record(
                  file[0],
                  base.unwrap(),
                  out,
                  body_auto,
                  force,
                  allow_write,
                )
              _ => Invalid
            }
          } else if name == "diff" {
            let baseline = single(sub.values.get("baseline").unwrap_or([]))
            let format = report_format(sub.values.get("format").unwrap_or([]))
            match (baseline, format) {
              (Some(baseline), Some(format)) =>
                Diff(
                  file[0],
                  base.unwrap(),
                  baseline,
                  sub.values.get("ignore").unwrap_or([]),
                  format,
                  allow_write,
                )
              _ => Invalid
            }
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
    Run(_, _, _) =>
      raise @cases.InvalidInput(
        0, "command", "run requires the async execution adapter",
      )
    Record(_, _, _, _, _, _) =>
      raise @cases.InvalidInput(
        0, "command", "record requires the async execution adapter",
      )
    Diff(_, _, _, _, _, _) =>
      raise @cases.InvalidInput(
        0, "command", "diff requires the async execution adapter",
      )
    Invalid => ""
  }
}
