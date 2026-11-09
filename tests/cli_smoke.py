"""Subprocess contract tests. Only synthetic files; no external HTTP requests."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    binary = Path(sys.argv[1]).resolve(strict=True)
    if binary.is_dir():
        candidates = list(binary.rglob("reqdiff.exe")) + [p for p in binary.rglob("reqdiff") if p.is_file()]
        assert len(candidates) == 1, ("expected exactly one executable", candidates)
        binary = candidates[0]
    checks = 0
    with tempfile.TemporaryDirectory(prefix="reqdiff-smoke-") as directory:
        root = Path(directory)
        env = os.environ.copy()
        env["REQDIFF_SMOKE_TOKEN"] = "credential-do-not-print"
        # A stale credential variable must not leak from the caller's environment.
        env.pop("REQDIFF_SMOKE_MISSING", None)

        def case(name, content):
            path = root / name
            path.write_bytes(content if isinstance(content, bytes) else content.encode("utf-8"))
            return str(path)

        valid = case("valid.jsonl", json.dumps({"id": "health", "method": "GET", "path": "/?token=query-do-not-print", "headers": {"Authorization": {"env": "REQDIFF_SMOKE_TOKEN"}}}))

        def run(args, code, contains="", forbidden=()):
            nonlocal checks
            result = subprocess.run([str(binary), *args], env=env, text=True, capture_output=True, timeout=10)
            assert result.returncode == code, (args, result.returncode, result.stdout, result.stderr)
            combined = result.stdout + result.stderr
            assert contains in combined, (args, combined)
            for secret in ("credential-do-not-print", "query-do-not-print", *forbidden):
                assert secret not in combined, (args, "secret leaked")
            if code:
                assert not result.stdout, (args, "errors must go to stderr")
            else:
                assert not result.stderr, (args, result.stderr)
            checks += 1

        run(["--help"], 0, "validate")
        run(["--version"], 0, "0.1.0-dev")
        run([], 2, "invalid arguments")
        run(["run"], 2, "invalid arguments")
        run(["--credential-do-not-print"], 2, "invalid arguments")
        run(["validate", valid], 0, "VALID: 1")
        # No server listens here: successful plan proves it does not attempt a connection.
        run(["plan", valid, "--base-url", "http://127.0.0.1:1"], 0, "no requests sent")
        run(["plan", valid, "--base-url", "https://user:credential-do-not-print@example.test"], 2, "origin")
        run(["plan", str(root / "absent"), "--base-url", "invalid"], 2, "origin")
        run(["plan", valid, "--base-url", "https://0xdocs.example"], 0, "0xdocs.example")
        run(["plan", valid, "--base-url", "https://api.0xteam.example"], 0, "0xteam.example")
        run(["validate", str(root / "absent")], 2, "cannot read input")
        run(["validate", str(root)], 2)
        run(["validate", case("bad-utf8", b"\xff\xfe")], 2, "valid UTF-8")
        run(["validate", case("too-big", b" " * (5 * 1024 * 1024 + 1))], 2, "5 MiB")
        run(["validate", case("empty", "\n \n")], 2, "at least one case")
        run(["validate", case("unknown", '{"id":"x","method":"GET","path":"/","credential-do-not-print":0}')], 2, "unknown")
        run(["validate", case("duplicate", '{"id":"x","id":"y","method":"GET","path":"/"}')], 2)
        run(["validate", case("missing-env", '{"id":"x","method":"GET","path":"/","headers":{"Authorization":{"env":"REQDIFF_SMOKE_MISSING"}}}')], 2, forbidden=("REQDIFF_SMOKE_MISSING",))
        write = case("write", '{"id":"x","method":"POST","path":"/","body":null}')
        run(["validate", write], 2)
        run(["validate", write, "--allow-write"], 0, "VALID: 1")
        run(["plan", write, "--allow-write", "--base-url", "https://example.test"], 0, "POST")
        print(f"CLI smoke: {checks} checks passed")


if __name__ == "__main__":
    main()
