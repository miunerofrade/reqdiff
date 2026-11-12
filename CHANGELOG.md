# Changelog

All notable changes to reqdiff are documented here. Formats follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the module has not had an official release yet, so everything below is unreleased work on `main`.

## [Unreleased]

### Added

- `validate` and redacted offline `plan` for strict JSONL request collections (unique IDs, methods, paths, header/env rules, size budgets).
- `run` for bounded sequential execution: whole-request 10-second deadline, 1 MiB response cap, TLS verification, no retries or redirects, buffered redacted summaries.
- `record` for versioned baselines with status-only capture by default and explicit `--body auto` for bodies (8 MiB aggregate capture budget).
- `diff` against a baseline with ID+SHA-256 request matching, JSON/text/status comparison, strict RFC 6901 `--ignore` pointers, terminal and JSON reports, exit codes 0/1/2 with error precedence.
- Exact decimal number comparison without Double conversion (`1 = 1.0 = 1e0`, `-0 = 0`; adjacent large integers differ).
- Baseline writing via exclusive temporary files, sync/close and rename; Unix files created with mode 0600; no partial files on failure or cancellation.
- Five-step localhost demo (`examples/demo.py`), CLI subprocess contract suite, source archive/package installation checks, and Windows+Ubuntu CI.

### Fixed

- Windows CI PATH handling so PowerShell resolves the MoonBit SDK.
- Ignore semantics now mask single-sided object members and array items at original indexes; pointer tokens such as `01` or `-` match object keys without ever matching array indexes.
- Baseline metadata (version/status) validated as exact integer tokens, not rounded Doubles; cross-kind body fields rejected; concurrent record writers no longer remove each other's temporary files; non-regular inputs (FIFO, directory, junction) rejected before blocking reads.

### Known limitations

- No automatic decompression, proxy support, cookies, retries, redirect following, binary response bodies, or expected-status assertions.
- Baseline bodies and request digests are private data, not redaction guarantees; keep baselines out of version control.
- Supported SDK range is documented from real test runs (moonc v0.10.20 era, CI installs stable latest); an immutable SDK pin is still release work.
- Windows x64 and Ubuntu x64 are the only CI-verified platforms; macOS and ARM are untested.
- Mooncakes registry publication and official binary releases have not happened yet.
