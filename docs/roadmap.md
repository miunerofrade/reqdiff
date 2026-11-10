# Delivery stages

Progress reflects working code, not intended features. No fixed commit quota.

## Stage 0 — foundations

- [x] Update and record actual SDK; native core API inspection.
- [x] Independent project/Git directory and private notes moved outside repository.
- [x] JSON/argparse/fs/http reuse, license/spec/decisions/development log.
- [x] Normal native tests for localhost HTTP, bounded reads, cancellation, filesystem cleanup and HTTPS trusted/untrusted CA.

## Stage 1 — offline usable slice

- [x] `--help`, `--version`, `validate`, redacted `plan`.
- [x] Strict JSONL/schema/environment/origin/header/path/size validation.
- [x] Pure tests, native CLI subprocess checks, synthetic examples.
- [x] Windows/Linux native CI definition; actual hosted run pending push/authorization.
- [x] Review initial commit contents and privacy boundary; keep stages 0/1 as one buildable delivery.
- [ ] Obtain separate approval before public upload.

## Stage 2 — real HTTP execution

- [x] `run` with explicit origin, method opt-in, no retries/redirects.
- [x] Request lifecycle limits, TLS verification, client cleanup and safe diagnostics.
- [x] Localhost integration cases for empty/large/delayed/disconnected responses; native debug/release and CLI subprocess verification on Windows.

## Stage 3 — baseline and diff (not implemented)

- [ ] Versioned baseline, explicit recording and overwrite protection.
- [ ] Status/JSON/text comparison and JSON Pointer exclusions.
- [ ] Safe terminal/JSON reports and mixed error/difference exit code precedence.
- [ ] Pure numeric policy, missing/null/types/arrays and tampered baseline tests.

## Stage 4 — complete demo and delivery (not implemented)

- [ ] Local healthy/broken API demonstration with expected exit codes.
- [ ] Real Windows/Linux CI results; reproducible install/build instructions.
- [ ] Verify Mooncakes consumption/publishing and platform binary distribution.
- [ ] User approval before release/publication; separate entrant-authored application.
