# Engineering decisions

## D001 — Native first, standard library first

Use the SDK's async/http, async/fs, argparse and JSON packages, not shell calls to curl or a second HTTP stack. Native networking is the target; do not advertise wasm-gc/JS runtime support. Actual initial SDK: moonc v0.10.20. These APIs are evolving. Official dated/versioned download probes returned HTTP403, so a reproducible SDK pin has NOT been verified. CI explicitly uses stable latest (not nightly), prints its versions, and must not be described as an exact SDK lock. Resolve toolchain pinning before a release.

## D002 — Split pure validation from effectful adapters

`cases` parses and validates Strings/Maps without filesystem, sockets or environment reads. `cli` parses explicit argv using argparse.parse_outcome and evaluates explicit input/env. `cmd/reqdiff` owns bounded file reading, real environment access, stdout/stderr and exit. `capabilities` is test-only network proof, not product transport.

## D003 — Redacted offline plan

Default plans display case IDs/methods and metadata counts, not raw paths/queries/body/header/env contents. We prefer an incomplete preview to accidentally publishing tokens via terminal output. The selected origin is displayed because it has already rejected userinfo/query/path. Validation cannot establish network authorization.

## D004 — Limits enforced before unbounded file reads

Open only a regular file and read a maximum of 5 MiB plus one byte. No check-size-then-read-all race. Individual JSONL lines limited to 1 MiB, max100 cases, JSON depth64. Error messages describe static rules and source coordinates, not parser errors containing private JSON.

## D005 — Test-only local TLS adapter

SDK HTTP server currently exposes plain TCP. HTTPS probes use a minimal core TCP+TLS fixture. Its internal-testing-only constructor is narrowly warning-suppressed on the two fixture declarations, not globally and never in product code. PEM/PFX/key fixtures are intentionally PUBLIC synthetic localhost material, not production credentials. PFX password is empty. Test CA must never be installed into the machine trust store. Certificates expire 2036; rotate fixtures before expiry. Linux/macOS adapter was checked against SDK source, but only Windows runtime was verified locally.

## D006 — Work history and publication

No fabricated or empty commits. Keep specifications and actual command outcomes with the implementation. Stage0/1 remains uncommitted until user review; private contest notes stay outside this repository. LICENSE attribution for any reused code must be preserved; using SDK APIs does not mean copying competitor implementations.
