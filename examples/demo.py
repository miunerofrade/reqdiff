"""Stage 4 demo harness; all product behavior runs in the MoonBit executable.

Usage: python -I examples/demo.py <reqdiff executable or build directory>
Only synthetic data and a temporary loopback HTTP server are used.
"""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def find_binary(argument):
    binary = Path(argument).resolve(strict=True)
    if binary.is_dir():
        candidates = [p for name in ("reqdiff.exe", "reqdiff")
                      for p in binary.rglob(name) if p.is_file()]
        if len(candidates) != 1:
            raise RuntimeError("Build directory must contain exactly one reqdiff executable.")
        binary = candidates[0]
    if not binary.is_file():
        raise RuntimeError("Executable must be a regular file.")
    return binary


def main():
    if len(sys.argv) != 2:
        print("Usage: python -I examples/demo.py <executable or build directory>")
        return 2
    binary = find_binary(sys.argv[1])
    env = os.environ.copy()
    # Never send loopback traffic through a proxy inherited from the shell.
    for name in list(env):
        if name.lower() in {"http_proxy", "https_proxy", "all_proxy", "no_proxy"}:
            env.pop(name)
    env["NO_PROXY"] = env["no_proxy"] = "127.0.0.1,localhost"
    lock = threading.Lock()
    state = {"broken": False, "requests": 0}

    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(5)

        def do_GET(self):
            with lock:
                state["requests"] += 1
                value = 2 if state["broken"] else 1
            body = json.dumps({"changed-field": value, "stable": "demo"}).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format, *args):
            pass

    print("Synthetic loopback demo; product logic runs in the supplied MoonBit binary.")
    root = None
    try:
        with tempfile.TemporaryDirectory(prefix="reqdiff-demo-") as directory:
            root = Path(directory)
            cases = root / "cases.jsonl"
            baseline = root / "baseline.json"
            request = {"id": "demo", "method": "GET", "path": "/demo"}
            cases.write_text(json.dumps(request) + "\n", encoding="utf-8")
            server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            try:
                thread.start()
                origin = f"http://127.0.0.1:{server.server_port}"

                def step(number, label, arguments, expected, requests=1):
                    with lock:
                        before = state["requests"]
                    result = subprocess.run(
                        [str(binary), *arguments], env=env, cwd=root,
                        capture_output=True, timeout=20,
                    )
                    with lock:
                        after = state["requests"]
                    print(f"Step {number}/5: {label} | expected exit={expected}, "
                          f"actual exit={result.returncode}", flush=True)
                    print(f"  Server requests: {before} -> {after} "
                          f"(expected increase={requests})", flush=True)
                    # Do not echo child output: failures may include local paths.
                    if result.returncode != expected or after - before != requests:
                        raise RuntimeError(f"Step {number} failed its exit/request-count check.")

                common = [str(cases), "--base-url", origin]
                step(1, "record --body auto", ["record", *common,
                     "--out", str(baseline), "--body", "auto"], 0)
                diff = ["diff", *common, "--baseline", str(baseline)]
                step(2, "diff healthy responses", diff, 0)
                with lock:
                    state["broken"] = True
                step(3, "diff broken response (numeric field changed)", diff, 1)
                step(4, "diff --ignore /changed-field",
                     [*diff, "--ignore", "/changed-field"], 0)
                request["path"] = "/different-demo-path"
                cases.write_text(json.dumps(request) + "\n", encoding="utf-8")
                step(5, "changed request path: configuration error before HTTP",
                     diff, 2, requests=0)
            finally:
                if thread.ident is not None:
                    server.shutdown()
                server.server_close()
                if thread.ident is not None:
                    thread.join(timeout=5)
                    if thread.is_alive():
                        raise RuntimeError("Server thread did not stop.")
    finally:
        if root is not None and not root.exists():
            print("Temporary request collection and baseline cleaned up.", flush=True)
    print("PASS: all five expected exit codes matched: 0/0/1/0/2; server stopped.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except subprocess.TimeoutExpired:
        print("FAIL: reqdiff exceeded the 20-second subprocess timeout.", file=sys.stderr)
        sys.exit(1)
    except (OSError, RuntimeError) as error:
        # OSError text can expose user paths; only print our own safe messages.
        message = str(error) if isinstance(error, RuntimeError) else type(error).__name__
        print(f"FAIL: {message}", file=sys.stderr)
        sys.exit(1)
