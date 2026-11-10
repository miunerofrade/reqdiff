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

## Planned stage 3

`record --out` and `diff --baseline`: versioned snapshots, no overwrite without explicit force, match by case ID plus non-secret request semantics; different origins allowed for environment comparison. Save only explicitly requested response state/body, not credentials/cookies. Snapshots may contain private business data even after redaction.

JSON comparisons ignore object key order, preserve array order and distinguish missing/null/types. Numeric policy must be verified and specified before release; no claim of arbitrary precision via Double conversion. Non-JSON UTF-8 text compared exactly; binary response bodies initially unsupported. Explicit JSON Pointer ignores (with ~0/~1 escaping) apply symmetrically, without wildcard scripts. Report truncation is explicit. Future exit code 1 means differences, 2 execution/configuration error (error takes precedence).

## Publication boundaries

README/spec/decision notes are AI-assisted engineering documents, not the contest application (which must be authored independently by the entrant). Development logs remain local and Git-ignored. Local commits are made when authorized; public push, Mooncakes publication and registration changes require separate authorization. Module version 0.1.0 is metadata, not a published release. Windows native verified locally; Linux CI configured but not yet run.
