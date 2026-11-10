# reqdiff

A MoonBit native CLI for explicit HTTP request collections. **Current stage: offline validation/planning and real HTTP execution.** Baseline recording and response comparison are planned.

reqdiff aims to reduce boilerplate for HTTP regression checks; it is not a replacement for pytest, a traffic recorder, a mock server or a load generator.

## Build and run

Requirements: MoonBit SDK with moonc **v0.10.20** (tested SDK release `2026-11-05`), and a working native C compiler. Windows native is verified locally; Linux is configured in CI but has not yet run. No third-party Mooncakes dependency is required.

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

`validate` and `plan` remain offline: no server needs to be running. Plans identify cases and methods without printing request paths/queries, headers, bodies or env references.

To send the collection to a development/test API you control, start that API first, then run:

```sh
moon run src/cmd/reqdiff --target native -- run examples/cases.jsonl --base-url http://127.0.0.1:8080
```

`run` sends one request at a time with a fresh connection for each case. Every request has a 10-second whole-request deadline and a 1 MiB response body limit. TLS certificate verification is enabled; there are no retries or redirects. Output includes only case ID, method, status and response byte count, for example:

```text
RUN: 2 case(s); requests completed
health GET status=200 bytes=2
user-1 GET status=200 bytes=19
```

These response values are illustrative; your API determines them. HTTP 3xx/4xx/5xx are completed responses, not execution failures. Transport/protocol errors, timeout and oversized bodies stop the collection with exit code 2 and no stdout. **Earlier requests may already have taken effect**; buffered output does not make execution transactional. Response contents are not printed or saved.

## Request format

One JSON object per nonblank line:

```json
{"id":"health","method":"GET","path":"/health"}
{"id":"profile","method":"GET","path":"/profile","headers":{"Authorization":{"env":"REQDIFF_TOKEN"}}}
```

IDs must be unique. `method` and `path` are required. Credential headers use env references, not literal tokens. Referenced environment variables must be present and nonempty even during offline validation; their values are not printed. Every case and environment reference is checked before `run` connects. See [the specification](docs/spec.md) for the full schema, limits and restrictions.

Non-GET/HEAD methods require explicit opt-in for every command:

```sh
moon run src/cmd/reqdiff --target native -- validate examples/write.jsonl --allow-write
moon run src/cmd/reqdiff --target native -- run examples/write.jsonl --base-url http://127.0.0.1:8080 --allow-write
```

The first command is offline; the second sends the write request. Use isolated, authorized targets. JSON bodies default to `application/json`; text bodies default to `text/plain; charset=utf-8`, unless Content-Type is explicitly supplied. No body and JSON `null` are distinct. Requests default to `Accept-Encoding: identity`; explicit encodings are preserved and responses are counted without automatic decompression.

## Status and tests

Implemented: `--help`, `--version`, `validate`, `plan`, `run`; strict JSONL/schema/env/origin/header/path validation; input/response size budgets; safe diagnostics; local HTTP/HTTPS and CLI integration tests.

Not implemented: `record`, `diff`, snapshots, response comparisons, JSON reports, package publication or binary releases. Success/help/version return 0; invalid input or execution failures return 2 on stderr. Exit code 1 is reserved for future comparisons.

```sh
moon test --target native --deny-warn
moon test --target native --release --deny-warn
python -I tests/cli_smoke.py _build/native/debug/build
moon fmt
moon info
```

Network tests bind dynamic localhost ports and do not call external APIs. HTTPS fixtures contain **public synthetic test keys**; never use them for production or install their CA into your system trust store. The test-only TLS server adapter is absent from the product transport. Python 3 is used only by `tests/cli_smoke.py` to test the compiled executable; all product logic is MoonBit.

## Development

- [Specification](docs/spec.md)
- [Stage roadmap](docs/roadmap.md)
- [Engineering decisions](docs/decisions.md)

Pure validation is in `src/cases`; command parsing/offline evaluation in `src/cli`; HTTP execution in `src/runner`; process/file handling in `src/cmd/reqdiff`. Local development logs are excluded from Git. These engineering documents are AI-assisted, not a contest application.

## Related tools and provenance

[Hurl](https://github.com/Orange-OpenSource/hurl), [HTTPie](https://github.com/httpie/cli), [moontape](https://github.com/BrainLyh/moontape) and [molt](https://github.com/paveg/molt) are related tools, not code sources for this implementation. HTTP replay and regression testing are established techniques; reqdiff does not claim novelty or ecosystem priority. The implementation uses MoonBit core APIs.

## License

Apache-2.0. See [LICENSE](LICENSE).
