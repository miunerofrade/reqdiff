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

SDK HTTP server currently exposes plain TCP. HTTPS probes use a minimal core TCP+TLS fixture. Its internal-testing-only constructor is narrowly warning-suppressed on the two fixture declarations, not globally and never in product code. PEM/PFX/key fixtures are intentionally PUBLIC synthetic localhost material, not production credentials. PFX password is empty. Test CA must never be installed into the machine trust store. Certificates expire 2036; rotate fixtures before expiry. Windows runtime was verified locally; the stage 3 hosted Windows/Ubuntu run also passed the TLS fixtures. macOS remains untested.

## D006 — Work history and publication

No fabricated or empty commits. Keep implementation, tests and public specifications together; detailed development/verification logs remain local and Git-ignored. Stage 0/1 was committed locally after user authorization; subsequent stage work follows the approved scope. Public push/publication requires separate authorization. Private notes stay outside version control. LICENSE attribution for any reused code must be preserved; using SDK APIs does not mean copying competitor implementations.

## D007 — Bounded, sequential execution

Validate the whole collection and every env reference before the first connection. A new client per case avoids cookie/connection state carrying into later cases. A single 10-second deadline includes connection, TLS, write, headers and body; defer closes every constructed client. Read only a fixed 1 MiB plus one byte and reject overflow. Requests default to identity encoding, preserving explicit Accept-Encoding without SDK decompression; the budget counts entity bytes rather than HTTP chunk framing. The SDK still owns response-header parsing/allocation.

HTTP statuses are data, including redirects and errors; stage 2 has no expected-status assertions. No retries or redirect following. Results are buffered until the whole collection succeeds so execution failures produce only stderr and exit 2. This is an output contract, not rollback: earlier requests may already have effects. Body contents and response headers/reason phrases are never terminal output or persisted by run. The safe summary includes only validated public IDs/methods, numeric status and byte count.

## D008 — Baselines: opt-in bodies, digest matching, exact numbers

Bodies are captured only with explicit `--body auto`; the default records statuses, so casual recording does not persist business data. Response bodies stay out of all terminal/JSON reports even when captured into a baseline file. Request identity uses a SHA-256 digest over a canonical non-secret projection (method, validated path, literal non-credential headers, body kind/content); env/credential headers are excluded. SHA-256 is implemented in-tree from FIPS 180-4 and tested against the official NIST vectors — no third-party crypto dependency and no homemade cipher. A digest is not redaction; baselines remain private.

Number equality never goes through Double. The parser preserves number text, and comparison canonicalizes sign/digits/exponent with pure string arithmetic, so `1`, `1.0`, `1e0` and `-0` behave as specified and 9007199254740992/9007199254740993 differ. JSON Pointer ignores skip subtrees symmetrically instead of deleting elements, keeping array indexes stable. Baseline writing uses create-new temp file, sync, then rename; the preflight refuses existing targets without `--force` before connecting, and a failed publish leaves no partial file. Exit precedence is 2 over 1 over 0: configuration and execution errors suppress stdout even when differences were already found, because a partially observed diff must not look authoritative.

## D009 — Review corrections and delivery checks

Baseline metadata version/status use exact integer tokens, not rounded Double validation. Body schemas are kind-specific; unused cross-kind fields are errors. Request matching checks the stored method as well as the digest. Pointer compilation validates RFC 6901 syntax without guessing container types: object keys `01` and `-` are legal, while array matching uses canonical index tokens only. Ignored single-sided object members and array items are masked at their original paths; indexes never shift.

Temporary files are allocated atomically with CreateNew, retrying fresh names without removing another writer's file. Use mode 0600 at creation, explicitly close before rename, and clean up owned files with defer on failure/cancellation. Input handling checks the path kind before open and the handle kind afterwards, with a bounded cancellable open. The pre-check is not a TOCTOU-free sandbox; file names/directories must remain under the caller's control.

The five-step demo uses Python only to start a synthetic loopback API and invoke the real executable. A separate package smoke check installs from the locally generated source archive into a temporary directory and runs the same demo. These checks prepare distribution without uploading to a registry or releasing a binary.
