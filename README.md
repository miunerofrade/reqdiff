# reqdiff

A MoonBit native CLI for HTTP regression checks: validate an explicit request collection, execute it against a development/test API, record a baseline, and compare later responses. `validate`, `plan`, `run`, `record` and `diff` are implemented.

reqdiff reduces HTTP test boilerplate. It is not a general test framework, traffic recorder, mock server or load generator.

## Build and install

Requirements: MoonBit SDK with moonc **v0.10.20** (tested SDK release `2026-11-05`) and a native C compiler. CI has passed on Windows and Ubuntu for [the stage 3 commit](https://github.com/miunerofrade/reqdiff/actions/runs/43060730735). CI installs stable latest and prints actual versions; the SDK is not immutably pinned. No third-party Mooncakes dependency is required.

From the repository root:

```sh
moon check --target native --deny-warn
moon build --target native --deny-warn
moon run src/cmd/reqdiff --target native -- --help
```

Install from your checkout:

```sh
moon install ./src/cmd/reqdiff
reqdiff --help
```

The default installation directory is `~/.moon/bin`; it must be on PATH. To choose another directory, add `--bin <directory>` to `moon install`. Local installation is verified on Windows. Official binary releases and a Mooncakes registry release are not published yet; source archives can be built and installed locally. See [delivery notes](docs/delivery.md).

## Five-step local demo

No separate API or credentials needed. Python 3 is only the demonstration harness; all product behavior runs in the MoonBit executable:

```sh
moon build --target native --deny-warn
python -I examples/demo.py _build/native/debug/build
```

The demo starts a synthetic loopback API on an unused port, creates a temporary collection and baseline, and verifies:

| Step | Behavior | Exit code |
|---|---|---|
| 1 | Record status and JSON body | 0 |
| 2 | Compare unchanged responses | 0 |
| 3 | Compare a changed numeric field | 1 |
| 4 | Ignore that field with JSON Pointer | 0 |
| 5 | Reject changed request semantics before HTTP | 2 |

The server and temporary files are cleaned up at the end.

## Use with your API

Validate or preview the included synthetic collection offline:

```sh
moon run src/cmd/reqdiff --target native -- validate examples/cases.jsonl
moon run src/cmd/reqdiff --target native -- plan examples/cases.jsonl --base-url http://127.0.0.1:8080
```

Expected validation output: `VALID: 2 case(s); no requests sent`. Plans show IDs, methods, counts and the selected origin, omitting paths/queries, headers, bodies and env references. Neither command connects to the API.

After starting a development/test API you control, use the installed CLI:

```sh
reqdiff run examples/cases.jsonl --base-url http://127.0.0.1:8080
```

`run` prints case ID, method, numeric HTTP status and response byte count. Every command that sends requests validates the entire collection and environment first, then executes sequentially with a fresh connection per case. Each request has a **10-second whole-request deadline** and a **1 MiB response body limit**. TLS verification is enabled; there are no retries, redirects or proxy discovery.

Record and compare status codes:

```sh
mkdir baselines
reqdiff record examples/cases.jsonl --base-url http://127.0.0.1:8080 --out baselines/api.json
reqdiff diff examples/cases.jsonl --base-url http://127.0.0.1:8080 --baseline baselines/api.json
```

Add `--body auto` when recording to include response bodies. This is explicit because responses may contain private business data:

```sh
reqdiff record examples/cases.jsonl --base-url http://127.0.0.1:8080 --out baselines/api-with-bodies.json --body auto
reqdiff diff examples/cases.jsonl --base-url http://127.0.0.1:9000 --baseline baselines/api-with-bodies.json --ignore /updated_at --format json
```

`diff` uses the baseline's capture mode. JSON object key order is ignored, array order is preserved and numbers compare exactly (`1 = 1.0 = 1e0`, while adjacent large integers remain distinct). Non-JSON bodies must be UTF-8 text and compare exactly. Empty bodies and JSON null are distinct; binary or compressed body capture is unsupported. Auto capture has an **8 MiB aggregate body budget**; encoded baselines are limited to **32 MiB**.

Baseline matching permits different origins and reordered cases, but rejects changed IDs or request semantics before sending requests. It stores request digests instead of raw requests; a digest is not a redaction guarantee. Env-referenced and credential headers are excluded from request identity. Existing baselines are preserved unless `record --force` is explicit. Recording uses exclusive temporary files, sync/close and rename; Unix baseline files are created with mode 0600. Keep output directories under your control.

Reports contain public IDs, difference categories, counts and numeric statuses, never response values or JSON paths. More than 50 differing cases truncates the listed records with an explicit marker. A difference means changed behavior, which still requires your judgement before updating the baseline.

| Exit code | Meaning |
|---|---|
| 0 | Success, or no differences |
| 1 | `diff` found differences; report is on stdout |
| 2 | Configuration, file or execution error; diagnostic on stderr, stdout empty |

HTTP 3xx/4xx/5xx are received responses, not execution errors by themselves. Execution errors stop subsequent cases and take precedence over earlier differences. **Earlier requests may already have taken effect**; buffered output is not rollback. `run` does not save bodies; `record --body auto` deliberately does. Baselines and reports are ignored by Git in their default directories.

## Request format

One JSON object per nonblank line:

```json
{"id":"health","method":"GET","path":"/health"}
{"id":"profile","method":"GET","path":"/profile","headers":{"Authorization":{"env":"REQDIFF_TOKEN"}}}
```

IDs are unique public output identifiers; do not put secrets in them. `method` and `path` are required. Credential headers require env references, whose values must be present, nonempty and control-free even for offline validation. JSON `body` and UTF-8 `body_text` are optional and mutually exclusive. See [the specification](docs/spec.md) for the complete schema, limits and matching rules.

Non-GET/HEAD methods require explicit `--allow-write` on every command:

```sh
reqdiff validate examples/write.jsonl --allow-write
reqdiff run examples/write.jsonl --base-url http://127.0.0.1:8080 --allow-write
```

The first command is offline; the second sends the write request. Use isolated, authorized targets. JSON bodies default to `application/json`, text bodies to `text/plain; charset=utf-8`; explicit Content-Type takes precedence. No body and JSON null differ. Requests default to identity encoding; explicit Accept-Encoding is preserved without automatic decompression.

## Checks and project structure

```sh
moon test --target native --deny-warn
moon test --target native --release --deny-warn
python -I tests/cli_smoke.py _build/native/debug/build
python -I tests/package_smoke.py
moon fmt
moon info
```

Network tests use dynamic loopback ports and synthetic input, with no external API calls. HTTPS fixtures include **public synthetic test keys**: never use them for production or install their CA into system trust. Python is used for demonstration and process/distribution checks; product logic is MoonBit.

`src/cases` validates requests; `src/cli` parses commands; `src/runner` executes/captures responses; `src/baseline`, `src/compare` and `src/report` implement pure baseline/comparison/report logic; `src/cmd/reqdiff` owns process and file effects. Detailed development logs are kept local and excluded from Git.

- [Specification](docs/spec.md)
- [Stage roadmap](docs/roadmap.md)
- [Engineering decisions](docs/decisions.md)
- [Delivery notes](docs/delivery.md)

These engineering documents are AI-assisted, not the contest application.

## Related tools and provenance

[Hurl](https://github.com/Orange-OpenSource/hurl), [HTTPie](https://github.com/httpie/cli), [moontape](https://github.com/BrainLyh/moontape) and [molt](https://github.com/paveg/molt) are related tools, not implementation code sources. HTTP replay and regression testing are established techniques; reqdiff does not claim novelty or ecosystem priority. The implementation uses MoonBit core APIs.

## License

Apache-2.0. See [LICENSE](LICENSE).
