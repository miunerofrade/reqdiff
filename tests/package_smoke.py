"""Build/install the local Mooncakes source archive without publishing it."""

from pathlib import Path, PurePosixPath
import subprocess
import tempfile
import zipfile
import sys


ROOT = Path(__file__).resolve().parents[1]


def run(arguments, cwd, timeout=180):
    result = subprocess.run(arguments, cwd=cwd, capture_output=True, text=True,
                            encoding="utf-8", errors="replace", timeout=timeout)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout


def main():
    run(["moon", "package", "--list"], ROOT)
    archive = ROOT / "_build" / "publish" / "miunerofrade-reqdiff-0.1.0.zip"
    with tempfile.TemporaryDirectory(prefix="reqdiff-package-") as directory:
        temporary = Path(directory)
        source = temporary / "source"
        source.mkdir()
        with zipfile.ZipFile(archive) as package:
            names = [PurePosixPath(name.replace("\\", "/")) for name in package.namelist()]
            for name in names:
                if name.is_absolute() or ".." in name.parts:
                    raise RuntimeError("Unexpected archive member path")
                if ("development.md" in name.parts or
                        any(part in {".git", ".env", "baselines", "reports", "_build"}
                            for part in name.parts) or
                        any(part.startswith(".env.") for part in name.parts)):
                    raise RuntimeError("Private/local material entered the source archive")
            # Normalize Windows-created zip names on Unix before extracting.
            for item, name in zip(package.infolist(), names):
                destination = source.joinpath(*name.parts)
                if item.is_dir():
                    destination.mkdir(parents=True, exist_ok=True)
                else:
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_bytes(package.read(item))
        modules = list(source.rglob("moon.mod"))
        if len(modules) != 1:
            raise RuntimeError("Expected exactly one module in the source archive")
        module = modules[0].parent
        for required in ("LICENSE", "README.md", "examples/demo.py", "docs/delivery.md"):
            if not (module / required).is_file():
                raise RuntimeError("Missing delivery file: " + required)
        installed = temporary / "bin"
        installed.mkdir()
        run(["moon", "install", str(module / "src" / "cmd" / "reqdiff"),
             "--bin", str(installed)], module)
        binaries = [path for path in installed.iterdir()
                    if path.name in {"reqdiff", "reqdiff.exe"} and path.is_file()]
        if len(binaries) != 1:
            raise RuntimeError("Expected exactly one installed executable")
        output = run([sys.executable, "-I", str(module / "examples" / "demo.py"),
                      str(binaries[0])], temporary, timeout=60)
        if "PASS: all five expected exit codes matched" not in output:
            raise RuntimeError("Installed archive did not pass the demonstration")
        print("Package smoke: source archive excludes private files; isolated install and five-step demo passed")
    print("Package smoke: temporary source and installed binary cleaned up; nothing published")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.TimeoutExpired, zipfile.BadZipFile) as error:
        print("Package smoke failed:", error, file=sys.stderr)
        sys.exit(1)
