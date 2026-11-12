# Delivery and installation

## Current state

The CLI implements offline validation/planning, bounded HTTP execution, baseline recording and response comparison. The original stage 3 commit has successful [Windows and Ubuntu CI](https://github.com/miunerofrade/reqdiff/actions/runs/43060730735). Later changes need their own CI run after an authorized push; an earlier green run is not proof for a new commit.

The source module has version metadata `0.1.0`; the development CLI prints `0.1.0-dev`. Neither is a published release. The project has no Mooncakes registry release, release tag, uploaded executable or installer yet.

## Build and install from source

Use the MoonBit SDK with a native compiler. Local testing uses moonc `v0.10.20+65efd5b93`, moon `0.1.20261104`. CI currently installs stable latest and prints versions; an immutable SDK download pin remains release work.

```sh
moon check --target native --deny-warn
moon build --target native --release --deny-warn
moon install ./src/cmd/reqdiff
reqdiff --version
```

Add `~/.moon/bin` to PATH, or use `moon install ./src/cmd/reqdiff --bin <directory>` and invoke the executable from that directory. Builds are specific to the host OS and architecture. The release executable is under `_build/native/release/build/cmd/reqdiff/` (`reqdiff.exe` on Windows, `reqdiff` on Unix).

Windows requires a working MSVC developer environment. CI uses `ilammy/msvc-dev-cmd` to establish it. Ubuntu needs the normal native C compiler toolchain; the SDK core TLS backend also needs its platform TLS runtime. These are prerequisites, not bundled binary dependencies.

## Local source package verification

```sh
python -I tests/package_smoke.py
```

This check runs `moon package --list`, inspects the generated source archive, rejects private/local files, extracts it into a temporary directory, installs the CLI from that extracted source into a separate temporary bin directory, and runs the five-step localhost demo with that installed binary. It exercises the locally packaged source, not just an executable built in the original checkout. No package is uploaded and no registry sign-in is required.

`moon package` produces `_build/publish/miunerofrade-reqdiff-0.1.0.zip`. The checked archive excludes `docs/development.md`, `.env` and local baseline/report directories. Only synthetic localhost certificate/key fixtures are included. Do not place private request collections outside the documented Git-ignored locations and expect the package builder to infer their sensitivity.

The five-step demo is also independently runnable:

```sh
python -I examples/demo.py _build/native/debug/build
```

It verifies record = 0, identical = 0, changed JSON = 1, explicitly ignored field = 0, and changed request configuration = 2 with zero additional requests. All listeners and files are temporary.

## Release candidate workflow

`.github/workflows/release.yml` is a manual (`workflow_dispatch`) candidate pipeline for Windows x64 and Linux x64. On each platform it builds with `--release`, runs release tests, checks `--version`, runs the five-step demo against the release build, and assembles a versioned archive (executable plus LICENSE, README, CHANGELOG, spec and delivery notes) with a SHA-256 checksum file. The workflow verifies archive contents and the checksum itself. Candidates stay inside the workflow workspace: the pipeline does not create a GitHub Release, tag, or upload artifacts anywhere. Running it is verification only, not publication.

Locally, the same packaging step is available:

```sh
python -I scripts/release_package.py --platform windows-x64 \
  _build/native/release/build/cmd/reqdiff/reqdiff.exe <output-directory>
```

The CLI reports `0.1.0-dev` during development; the module metadata version lives in `moon.mod` (`0.1.0`). Before any formal release, reconcile both with the chosen version and update `CHANGELOG.md`; `tests/package_smoke.py` reads the archive name from `moon.mod`, so packaging follows the metadata version automatically.

## Publication gates still open

- Obtain explicit authorization before pushing, tagging, uploading a binary or publishing to Mooncakes. The candidate pipeline does not create releases; turning a candidate into one is a separate, authorized step.
- Choose the actual release version and reconcile CLI/module version strings.
- Verify the registry namespace, authentication and package policy during the authorized publication step. Local archive installation does not prove registry publication or consumption.
- Build and test OS/architecture-specific release binaries, document runtime requirements, produce checksums and attach them only after approval. No unsigned binary is described as an official release here.
- Resolve reproducible SDK version pinning or state the supported SDK range based on real tests.
- Keep baseline files and local development notes out of the public source and release archives.

A formal contest application must be written independently by the entrant. These technical documents do not replace that application or guarantee acceptance/rewards.
