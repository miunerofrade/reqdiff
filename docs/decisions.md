# Engineering decisions

## D001 — Native first, standard library first

Use the SDK's async/http, async/fs, argparse and JSON packages, not shell calls to curl or a second HTTP stack. Native networking is the target; do not advertise wasm-gc/JS runtime support. Actual initial SDK: moonc v0.10.20. These APIs are evolving. Official dated/versioned download probes returned HTTP403, so a reproducible SDK pin has NOT been verified. CI explicitly uses stable latest (not nightly), prints its versions, and must not be described as an exact SDK lock. Resolve toolchain pinning before a release.

## D002 — Split pure validation from effectful adapters

`cases` parses and validates Strings/Maps without filesystem, sockets or environment reads. `cli` parses explicit argv using argparse.parse_outcome and evaluates offline commands with explicit input/env. `runner` preflights collections and owns HTTP execution; it returns safe response summaries without printing. `cmd/reqdiff` owns bounded file reading, real environment access, stdout/stderr and exit. `capabilities` is test-only network proof and a TLS fixture, not product transport.

## D003 — Redacted offline plan

Default plans display case IDs/methods and metadata counts, not raw paths/queries/body/header/env contents. We prefer an incomplete preview to accidentally publishing tokens via terminal output. The selected origin is displayed because it has already rejected userinfo/query/path. Validation cannot establish network authorization.

## D004 — Limits enforced before unbounded file reads

Open only a regular file and read a maximum of 5 MiB plus one byte. No check-size-then-read-all race. Individual JSONL lines limited to 1 MiB, max100 cases, JSON depth64. Error messages describe static rules and source coordinates, not parser errors containing private JSON.

## D005 — Test-only local TLS adapter

SDK HTTP server currently exposes plain TCP. HTTPS probes use a minimal core TCP+TLS fixture. Its internal-testing-only constructor is narrowly warning-suppressed on the two fixture declarations, not globally and never in product code. PEM/PFX/key fixtures are intentionally PUBLIC synthetic localhost material, not production credentials. PFX password is empty. Test CA must never be installed into the machine trust store. Certificates expire 2036; rotate fixtures before expiry. Linux/macOS adapter was checked against SDK source, but only Windows runtime was verified locally.

## D006 — Work history and publication

No fabricated or empty commits. Keep implementation, tests and public specifications together; detailed development/verification logs remain local and Git-ignored. Stage 0/1 was committed locally after user authorization; subsequent stage work follows the approved scope. Public push/publication requires separate authorization. Private notes stay outside version control. LICENSE attribution for any reused code must be preserved; using SDK APIs does not mean copying competitor implementations.

## D007 — Bounded, sequential execution

Validate the whole collection and every env reference before the first connection. A new client per case avoids cookie/connection state carrying into later cases. A single 10-second deadline includes connection, TLS, write, headers and body; defer closes every constructed client. Read only a fixed 1 MiB plus one byte and reject overflow. Requests default to identity encoding, preserving explicit Accept-Encoding without SDK decompression; the budget counts entity bytes rather than HTTP chunk framing. The SDK still owns response-header parsing/allocation.

HTTP statuses are data, including redirects and errors; stage 2 has no expected-status assertions. No retries or redirect following. Results are buffered until the whole collection succeeds so execution failures produce only stderr and exit 2. This is an output contract, not rollback: earlier requests may already have effects. Body contents and response headers/reason phrases are never terminal output or persisted by run. The safe summary includes only validated public IDs/methods, numeric status and byte count.
