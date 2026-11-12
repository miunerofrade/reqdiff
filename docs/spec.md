# reqdiff v0.1 specification

Status: stages 0–2 implemented; baseline recording and comparison remain planned.

## Purpose and non-goals

A native MoonBit CLI for explicit HTTP request collections and, eventually, response-baseline regression checks. Not a general test framework or an original invention of HTTP replay. No proxy, packet capture, traffic mirroring, load testing, GUI, HAR/curl/OpenAPI import, login scripting or production recording in v0.1.

## Implemented commands

```text
reqdiff --help
reqdiff --version
reqdiff validate <cases.jsonl> [--allow-write]
reqdiff plan <cases.jsonl> --base-url <origin> [--allow-write]
reqdiff run <cases.jsonl> --base-url <origin> [--allow-write]
```

`validate` and `plan` are strictly offline: these command paths never create a network client. `validate` checks input and referenced environment variables. `plan` also checks the origin before reading the file and prints a redacted description. Credentials, environment variable names/values, request paths/queries, headers and bodies are omitted from plans. This is intentionally conservative; it is not a raw request preview.

Exit codes: 0 success/help/version; 2 invalid arguments, input, environment, file I/O or request execution failure. HTTP 3xx/4xx/5xx alone do not cause a failure. Exit code 1 is reserved for future comparisons. Errors use stderr and do not echo raw argv, JSON, paths or env values. Unknown and future commands fail, not simulated success. Error coordinates use one-based input lines; line 0 means file/origin-level validation.

## JSONL format

One object per nonblank line; blank lines ignored; at least one case. UTF-8 only, BOM accepted by decoder. File must be regular, maximum 5 MiB read with a fixed limit-plus-one-byte buffer; each line maximum 1 MiB; maximum 100 cases. JSON nesting maximum 64. Duplicate object keys are rejected recursively, including equivalent escaped keys. Unknown top-level or env-reference fields rejected.

```json
{"id":"user-1","method":"GET","path":"/users/1","headers":{"Accept":"application/json","Authorization":{"env":"REQDIFF_TOKEN"}}}
```

- `id`: required string, `[A-Za-z0-9][A-Za-z0-9._-]{0,63}`, unique per file.
- `method`: required uppercase GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS. Only GET/HEAD accepted without `--allow-write`; for `run`, the flag permits actual non-GET/HEAD requests.
- `path`: required string starting with one `/`, optionally query. Absolute URLs, leading `//`, fragment, spaces, backslash, controls, malformed percent escapes and escaped controls/backslash rejected.
- `headers`: optional object. Names are ASCII HTTP tokens, normalized lowercase, case-insensitive duplicates rejected. Values are control-free strings or exactly `{"env":"NAME"}`. Environment variable names follow `[A-Za-z_][A-Za-z0-9_]*`; referenced values must exist, be nonempty and control-free.
- Protocol/cookie/proxy headers are forbidden: Host, Content-Length, Transfer-Encoding, Connection, Cookie, Proxy-Authorization, Proxy-Authenticate, Keep-Alive, TE, Trailer, Upgrade. Header names suggesting authentication/token/secret/API-key require env references. This heuristic does not prove arbitrary custom headers are secret-free.
- `body`: optional arbitrary JSON (explicit null is a body).
- `body_text`: optional string, mutually exclusive with `body`.

`--base-url` is an HTTP(S) origin only: host with optional valid port 1..65535 and optional single trailing slash. No userinfo, paths, query, fragments, controls, spaces or backslashes. Scheme/ASCII DNS host lowercased, numeric port canonicalized. IPv4 and bracketed IPv6 supported; legacy ambiguous numeric host forms rejected. This is syntax validation, not DNS resolution, network isolation, or proof a target is authorized. Unicode host/IDNA and IPv6 zone IDs are out of scope. Encoded paths are checked once, not recursively decoded: transport must not reinterpret validated paths.

## Stage 2 execution

`run` requires an explicit origin. It validates the complete collection and all environment references before making any connection, then executes sequentially with a fresh client per case. No retries, redirects, proxy discovery, cookie persistence or automatic decompression. TLS uses system roots and verifies certificates; there is no insecure/custom-CA CLI option. No production client uses the test-only TLS server adapter.

Each request has a fixed 10-second deadline covering body serialization, connection/DNS/TLS, request write, response headers and response body. Each response body is limited to 1 MiB, enforced with a fixed limit-plus-one-byte buffer; overflow is failure, not truncated success. The budget counts entity bytes after HTTP transfer framing and before content decompression. Default `Accept-Encoding: identity` disables SDK automatic gzip negotiation; explicit Accept-Encoding is preserved without automatic decompression. Response headers/parser allocations are managed by the SDK and are not covered by this body limit.

The validated path is sent unchanged, including percent escapes. Headers resolve env references only in memory. User-Agent is provided at client construction because of the SDK's per-request restriction. JSON bodies use the parser's preserved numeric representation when serialized, with default `Content-Type: application/json`; text bodies use UTF-8 and default `text/plain; charset=utf-8`. Explicit Content-Type takes precedence. A present body uses its encoded Content-Length; no body and JSON null differ. No implicit body or Content-Type is added to bodyless requests.

Success output is buffered until every case completes: `RUN: N case(s); requests completed`, followed by `id METHOD status=CODE bytes=COUNT` per case. It omits the origin, paths/query, header/env names and values, response reason/headers and request/response contents. Case IDs are public output identifiers: do not put secrets in them. Bodies are consumed only for their bounded byte count, not printed or saved; binary responses can therefore be counted without implying baseline/diff support.

HTTP 3xx/4xx/5xx are completed responses, not assertion or regression failures. Final statuses outside 200–599, including unsupported 101 protocol upgrades, are rejected; informational responses are handled by the SDK within the same deadline. A network/TLS/I/O, HTTP framing/protocol, timeout or body-limit error stops execution immediately, suppresses all stdout and returns 2 with safe source coordinates and a fixed description on stderr. No rollback is possible: earlier requests may have taken effect even though no success summary is printed. Every constructed client is closed on success, error and cancellation; partial connection setup is cleaned up by the SDK. GET/HEAD default and writes require explicit opt-in in isolated authorized environments.

## Stage 3 baseline and diff

Commands:

```text
reqdiff record <cases.jsonl> --base-url <origin> --out <file> [--body none|auto] [--force] [--allow-write]
reqdiff diff <cases.jsonl> --base-url <origin> --baseline <file> [--ignore <pointer>]... [--format terminal|json] [--allow-write]
```

`record` executes the collection exactly like `run` (same preflight, ordering, deadline, limits) and writes a versioned baseline. Default `--body none` records only status codes; explicit `--body auto` also records response bodies, which may contain private business data — the help text says so. `diff` re-executes the collection and compares against the baseline; it uses the baseline's recorded body mode and has no `--body` flag.

### Baseline format (v1)

A single strict JSON object: `version` (the integer token `1`, not a rounded fractional or exponent form), `body_mode` (`none`|`auto`), `records` (1..100). Each record: `id` (same rule as cases), `method`, `fingerprint` (`sha256:<64 hex>`), `status` (a plain unsigned integer token within 200..599), and `body` only when `body_mode` is `auto`: `{"kind":"empty"}`, `{"kind":"json","value":<any JSON incl. null>}`, or `{"kind":"text","text":<string>}`. An absent `body` with mode `none` means uncaptured; JSON `null` inside `kind:"json"` is a captured JSON null; `kind:"empty"` is a zero-byte body. Unknown fields, wrong version, duplicate keys (recursively), duplicate IDs, invalid status/kind or mismatched body presence are rejected. Baseline files are bounded: regular file, ≤32 MiB read with a limit-plus-one-byte buffer, JSON depth ≤64, numbers parsed with preserved representation. Recorded bodies originate from capture, which enforces the same 1 MiB per-response limit as `run` plus an 8 MiB aggregate body budget for the whole suite in `auto` mode.

### Request matching

Records match cases by unique ID plus a request fingerprint: SHA-256 over a canonical projection of `v1`, method, as-validated path (including query and percent escapes), literal non-credential headers (lowercased names, sorted, `name:value`), and body kind/content (JSON bodies in stringify form with preserved numbers). Env-referenced headers and credential headers (auth/token/secret/api-key/apikey name heuristic) are excluded entirely; defaults the runner derives (Host, Content-Length, User-Agent, Accept-Encoding) are not part of identity. The fingerprint is stored as a digest — never the projection itself — but a digest is NOT redaction: low-entropy values remain guessable and baselines must still be treated as private. Missing/extra IDs, fingerprint or method mismatch are configuration errors (exit 2) detected BEFORE any connection. Different origins are allowed between record and diff; that is the intended environment-comparison use.

### Capture classification

With `--body auto`: zero-length bodies are `empty`; otherwise a JSON media type (`application/json` or `+json` suffix, parameters allowed) must strictly parse (duplicate keys, depth, malformed JSON are errors); all other responses must be strict UTF-8 (BOM preserved, invalid sequences are errors); a non-identity `Content-Encoding` is an error. No byte replacement, no fallback to success, no binary support. JSON null is preserved distinctly from empty.

### Comparison and reports

Status is always compared. JSON bodies ignore object key order, preserve array order, and distinguish missing/null/type. Numbers compare by exact decimal value canonicalized from the preserved representation (sign, significant digits, decimal exponent): `1 = 1.0 = 1e0`, `-0 = 0`, huge exponents are compared without expansion and without Double conversion. Text bodies compare exactly. `--ignore <pointer>` accepts repeated strict RFC 6901 JSON Pointers (empty string = root, `~0`/`~1` escapes, no wildcard or URI-fragment interpretation). Tokens such as `01`, `-` and `0abc` can match literal object keys; only canonical non-negative decimal tokens match array indexes, so these tokens are no-ops on arrays; unknown pointers are no-ops; ignores apply symmetrically to both trees by skipping subtrees (never deleting elements, so indexes do not shift); ignoring the root masks only the JSON body, never the status. Explicitly ignored subtrees suppress missing/null/type differences inside them.

Reports (terminal and `--format json`) contain only public case IDs, difference categories and counts, numeric statuses, and explicit truncation markers. They never print bodies, JSON keys/pointers/paths, request paths/queries, headers, env names/values or response headers. Output order follows the case file. Terminal summary: `DIFF: N case(s); M difference(s)` with per-record category lines, capped at 50 differing cases with an explicit `report truncated` marker (the difference total counts categories; a JSON category carries its separate differing-location count); identical suites print `IDENTICAL: N case(s); no differences`. `record` prints `RECORDED: N case(s)`; the output path is not echoed.

### Exit codes

0: identical (diff) or baseline written (record). 1: differences found (diff only). 2: invalid arguments/input/environment, baseline file problems, request matching failure, capture/execution error — and 2 takes precedence: an execution error after earlier differences yields exit 2 with no stdout. Differences do not stop later cases; execution errors still fail fast as in `run`.

### Baseline file writing

`record` writes to a unique temporary file in the destination directory, then `sync`, close, and atomic rename onto the target. Without `--force` an existing target is refused before any connection; with `--force` rename replaces it. Exclusive CreateNew reservation retries fresh names; cleanup only touches a file successfully reserved by this writer, including on cancellation. Files are created with Unix mode 0600 (Windows ACL inheritance remains platform-controlled). The output directory must be trusted and not maliciously replaced during writing. No durability claim beyond successful rename is made. Baselines are private data: `.gitignore` excludes baseline directories, and no automatic commit/push covers them.

## Publication boundaries

README/spec/decision notes are AI-assisted engineering documents, not the contest application (which must be authored independently by the entrant). Development logs remain local and Git-ignored. Local commits are made when authorized; public push, Mooncakes publication and registration changes require separate authorization. Module version 0.1.0 is metadata, not a published release. Windows and Ubuntu CI passed for stage 3 in [run 43060730735](https://github.com/miunerofrade/reqdiff/actions/runs/43060730735); later changes require a fresh hosted run. Local packaging and installation checks do not publish or establish registry availability.
