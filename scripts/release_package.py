"""Build a release candidate archive and SHA-256 checksums from a built binary.

Usage: python -I scripts/release_package.py --platform <name> <binary> <output-directory>
Copies the executable with LICENSE, README, CHANGELOG and usage docs, runs the
binary's --version once, and writes <archive>.sha256 next to the archive.
Nothing is uploaded; a candidate is still subject to explicit authorization.
"""

import argparse
from pathlib import Path
import hashlib
import shutil
import subprocess
import sys
import tarfile
import tempfile


ROOT = Path(__file__).resolve().parents[1]
INCLUDE = ("LICENSE", "README.md", "CHANGELOG.md", "docs/spec.md", "docs/delivery.md")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", required=True,
                        help="Archive suffix, for example windows-x64 or linux-x64")
    parser.add_argument("binary", type=Path)
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()
    binary = arguments.binary.resolve(strict=True)
    if not binary.is_file():
        raise RuntimeError("Release binary must be a regular file")
    output = arguments.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    version = "unknown"
    try:
        version_result = subprocess.run([str(binary), "--version"], capture_output=True,
                                        text=True, encoding="utf-8", errors="replace",
                                        timeout=30)
        if version_result.returncode:
            raise RuntimeError(version_result.stderr)
        version = version_result.stdout.strip().removeprefix("reqdiff ")
        print(f"Candidate binary reports version: {version}")
    except (OSError, subprocess.TimeoutExpired, RuntimeError) as error:
        raise RuntimeError(f"Release binary failed --version: {error}")
    archive = output / f"reqdiff-{version}-{arguments.platform}.tar.gz"
    with tempfile.TemporaryDirectory(prefix="reqdiff-release-") as directory:
        staging = Path(directory) / f"reqdiff-{version}-{arguments.platform}"
        staging.mkdir()
        shutil.copy2(binary, staging / binary.name)
        for name in INCLUDE:
            source = ROOT / name
            if source.is_file():
                destination = staging / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, destination)
            else:
                raise RuntimeError("Missing required delivery file: " + name)
        with tarfile.open(archive, "w:gz") as bundle:
            bundle.add(staging, arcname=staging.name)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (output / (archive.name + ".sha256")).write_text(
        f"{digest}  {archive.name}\n", encoding="ascii")
    print(f"Candidate archive: {archive}")
    print(f"SHA-256: {digest}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"Release packaging failed: {error}", file=sys.stderr)
        sys.exit(1)
