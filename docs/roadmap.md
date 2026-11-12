# Delivery stages

Progress reflects working code and actual checks. No fixed commit quota.

## Stage 0 — foundations

- [x] Update and record SDK; inspect native core APIs.
- [x] Independent project/Git directory; private notes outside version control.
- [x] Reuse core JSON/argparse/fs/http; license, specification and decisions.
- [x] Localhost HTTP/HTTPS, bounded reads, cancellation and filesystem probes.

## Stage 1 — offline usable slice

- [x] `--help`, `--version`, `validate`, redacted `plan`.
- [x] Strict JSONL/schema/environment/origin/header/path/size validation.
- [x] Pure tests, native CLI subprocess checks and synthetic examples.
- [x] Windows/Ubuntu CI; [stage 3 run passed on both](https://github.com/miunerofrade/reqdiff/actions/runs/43060730735).
- [x] Reviewed contents and privacy boundary before the authorized initial public push.

## Stage 2 — real HTTP execution

- [x] `run` with explicit origin, method opt-in, no retries/redirects.
- [x] Lifecycle limits, TLS verification, client cleanup and safe diagnostics.
- [x] Localhost empty/large/delayed/disconnected response integration tests.

## Stage 3 — baseline and diff

- [x] Versioned baselines, explicit recording and overwrite protection.
- [x] Status/JSON/text comparison and JSON Pointer exclusions.
- [x] Redacted terminal/JSON reports and error/difference exit precedence.
- [x] Exact decimal numeric policy, missing/null/types/arrays and tampered baselines.
- [x] Review regressions for negative-zero exponents, symmetric ignores of missing nodes, strict metadata/body schema and concurrent writers.

## Stage 4 — demo and delivery preparation

- [x] Five-step localhost healthy/changed API demo with verified exit codes and cleanup.
- [x] README for the complete workflow; recorded Windows/Ubuntu CI evidence.
- [x] Local CLI installation and source package inspection/isolated installation check.
- [x] CI definitions for the demo and source package verification.
- [x] Release candidate workflow (manual dispatch) building/testing Windows x64 and Linux x64 archives with checksums, without publishing.
- [x] CHANGELOG recording capabilities, fixes and known limitations.
- [x] Hosted CI green for the review/delivery changes ([run 43245838411](https://github.com/miunerofrade/reqdiff/actions/runs/43245838411)); each future push needs its own fresh run.
- [ ] Verify Mooncakes registry publication/consumption when publication is authorized.
- [ ] Select release version, resolve SDK pinning and publish tested platform binaries/checksums with approval.
- [ ] Separate entrant-authored contest application; never submit these AI-assisted engineering notes as that application.

Packaging and local installation are complete preparation steps; registry publication and official binary distribution remain open. See [delivery notes](delivery.md).
