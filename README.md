# reqdiff

A MoonBit native CLI for HTTP request collections. **Current stage: offline validation and planning only.** Request execution, baseline recording and response comparison are planned, not implemented.

reqdiff aims to reduce boilerplate for HTTP regression checks; it is not a replacement for pytest, a traffic recorder, a mock server or a load generator.

## Build and run

Requirements: MoonBit SDK with moonc **v0.10.20** (tested SDK release `2026-11-05`), and a working native C compiler. Windows native is verified locally; Linux is configured in CI but has not yet run. No third-party Mooncakes dependency is required for stage0/1.

From this repository root:

```sh
moon check --target native --deny-warn
moon build --target native
moon run src/cmd/reqdiff --target native -- --help
moon run src/cmd/reqdiff --target native -- validate examples/cases.jsonl
moon run src/cmd/reqdiff --target native -- plan examples/cases.jsonl --base-url http://127.0.0.1:8080
```

Expected validation output:

```text
VALID: 2 case(s); no requests sent
```

Plans are intentionally redacted: they identify cases and methods, but do not print request paths/queries, headers, bodies or env references. No server needs to be running for either command.

## Request format

One JSON object per nonblank line:

```json
{"id":"health","method":"GET","path":"/health"}
{"id":"profile","method":"GET","path":"/profile","headers":{"Authorization":{"env":"REQDIFF_TOKEN"}}}
```

IDs must be unique. `method` and `path` are required. Credential headers use env references, not literal tokens. Referenced environment variables must be present and nonempty even during offline validation; their values are not printed. See [the specification](docs/spec.md) for the full schema, limits and restrictions.

Non-GET/HEAD methods require explicit opt-in for validation/planning:

```sh
moon run src/cmd/reqdiff --target native -- validate examples/write.jsonl --allow-write
```

This does not send the request. It is not an assurance that a future write request is safe or authorized.

## Status and tests

Implemented: `--help`, `--version`, `validate`, `plan`; strict JSONL/schema/env/origin/header/path validation; size budgets; safe diagnostics; local HTTP/HTTPS capability tests.

Not implemented: `run`, `record`, `diff`, snapshots, response comparisons, JSON reports, package publication or binary releases. Unknown commands return exit code2. Success/help/version return0. Errors use stderr.

```sh
moon test --target native --deny-warn
moon test --target native --release --deny-warn
moon fmt
moon info
```

The test-only capabilities package binds dynamic localhost ports. HTTPS fixtures contain **public synthetic test keys**; never use them for production or install their CA into your system trust store. Product CLI does not import the HTTP client. Python3 is used only by `tests/cli_smoke.py` to test the compiled executable; all product logic is MoonBit.

## Development

- [Specification](docs/spec.md)
- [Stage roadmap](docs/roadmap.md)
- [Engineering decisions](docs/decisions.md)
- [Actual development and verification log](docs/development.md)

Core reusable validation is in `src/cases`; command parsing/evaluation in `src/cli`; effectful process/file handling in `src/cmd/reqdiff`. These engineering documents are AI-assisted, not a contest application.

## Related tools and provenance

[Hurl](https://github.com/Orange-OpenSource/hurl), [HTTPie](https://github.com/httpie/cli), [moontape](https://github.com/BrainLyh/moontape) and [molt](https://github.com/paveg/molt) are related tools, not code sources for this implementation. HTTP replay and regression testing are established techniques; reqdiff does not claim novelty or ecosystem priority. The implementation uses MoonBit core APIs.

## License

Apache-2.0. See [LICENSE](LICENSE).
