"""Subprocess contracts using synthetic input and stdlib loopback fixtures only."""
import json
import os
from pathlib import Path
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time


BODY_LIMIT = 1024 * 1024
# Public, test-only self-signed material. Never trusted by the client; no openssl
# executable or third-party Python dependency is needed when running the suite.
TLS_CERT = """-----BEGIN CERTIFICATE-----
MIIDCTCCAfGgAwIBAgIUBnqj44HuIxeKDlx5601jq0vAhhQwDQYJKoZIhvcNAQEL
BQAwFDESMBAGA1UEAwwJbG9jYWxob3N0MB4XDTI2MTExMDE0MzU0OVoXDTM2MTEw
NzE0MzU0OVowFDESMBAGA1UEAwwJbG9jYWxob3N0MIIBIjANBgkqhkiG9w0BAQEF
AAOCAQ8AMIIBCgKCAQEAoD/ZrAk2hwIa9h9k6tMZgfWaOYwfo/I6HW0thF99vZJt
47CBiGN7qfDxzJ8Tl0r01nOyBL7Ml1ow4xHSWnVALwHir+YaACeMUbFMwI3PHYcv
IiYgzpjvrvF/iD5fRghdECh38ZYq/38xxyQ6WehCBSm4t6O1BKH9Oy0DTlSaaNVr
B/nL/5mYhDSAg+g4FUIDMZhprLgIxQDmuHWs0IlcGKPhcsFhnj5vVQgP5RyVyzTy
erYSPJOrblXYCBbSEhonPl7VHCS3U26gU31822P4G5H4Vl6LgfD+O670elSJ9DiQ
Ry1fzHF8UZXYJm5G+ZXlP0+HFXdl95NWlZQPx6sdXwIDAQABo1MwUTAdBgNVHQ4E
FgQUZ00edCWZ3XGCJ6jakE/7aXakv9UwHwYDVR0jBBgwFoAUZ00edCWZ3XGCJ6ja
kE/7aXakv9UwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEABWE8
sdV5+9D9IYoKl7dAl16KOs9AW1dEIN6/bI2LTnCboVazdJOfDSr0S2eRe/xM8t3N
JqJfQb09nMMjWceR9Mwa/bTKMUfD2vp8m/2sN+0U8mdqgPy0Wo2EmhuTMpH1izVZ
4/CUQbBchDMT5AVC+eZOfJHp8+jJfdO0r0nqOyhTs1o1L0847JBq/L8ks8UjG5b8
4UnuvOGMcNev6sYn5/W0KJFZ5cz45fiy1kUI/qvrJQA0nXCn1ch9dajdOKPUKZ0O
7e9n/nNR4dsaCGKllLkW6nuUOy0iENR22SJFkFuzPZQkeUzMoyQdUkCX/em5tNLi
CEX9oQCmoqSGrRoFNg==
-----END CERTIFICATE-----
"""
TLS_KEY = """-----BEGIN PRIVATE KEY-----
MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQCgP9msCTaHAhr2
H2Tq0xmB9Zo5jB+j8jodbS2EX329km3jsIGIY3up8PHMnxOXSvTWc7IEvsyXWjDj
EdJadUAvAeKv5hoAJ4xRsUzAjc8dhy8iJiDOmO+u8X+IPl9GCF0QKHfxlir/fzHH
JDpZ6EIFKbi3o7UEof07LQNOVJpo1WsH+cv/mZiENICD6DgVQgMxmGmsuAjFAOa4
dazQiVwYo+FywWGePm9VCA/lHJXLNPJ6thI8k6tuVdgIFtISGic+XtUcJLdTbqBT
fXzbY/gbkfhWXouB8P47rvR6VIn0OJBHLV/McXxRldgmbkb5leU/T4cVd2X3k1aV
lA/Hqx1fAgMBAAECggEALhdvYl4cAuUGIDiTbD9fnNOpklfNWfh34rLeXq6gmgAd
/1lrSHFkxlJ5GeO/XMrAdVY9o8PFUNsuKIGdwUrsNRkTvIgwfk7huzWF3/Rp2BJj
6iyRTxsKBYWMqwFVoe0R523cYe5RW7+X77Fp3yZApv+DE77QeA6nqXee9c67wt77
FezTX1ezyMnhnRQ0H62WdnSyx6pgkpITulRNOdKaHIlZAU/aSG+dXJiqdfLug3uW
P5RYp99wR/iMWLzsH1ERvsQqQvFYdkc3roAMX+hTK4B2jay/JuPprPJXYrXWABG1
LPf1jRhua6VsUSyXSEQeH7rfBjS6zHJj4tCHFU/GEQKBgQDTP4U7XFdP6KtKRkoa
qBL7H5VbKKxQIZKYeNLawqzoHuhfVpzFSsJD8KWvHUKoZZEVH7Bh0o4fjNqwgAtx
5hmoEbA6HWbaUB+x7zJnfAc7JI3bYxpofY5JTBT3QOXTGhTjUmriJ++98nMTiZvN
Z/nBQnAepqAYrSK90ZseO/Y8ZQKBgQDCMozwTKAVzu4/kkGc2Biz3kDAZL1bMF1a
RpbLPB66jbehXTz69DPr/l066KTR2W3zv4o8S2HCNmCq113ooSlqShKFD3qJjMBc
BUjz9s6V9oFGICyThrh539/mLUZJsKrQ2tT7HaYQx4xD1JKxWPVjk1zbqnbrDsa/
3LYSk6BMcwKBgAZEJBeWraBZLnuNijUwNx/r1+pUUogt9sM/EkIa9DYOdKYfU5cm
mIybXs7K92c3XA5cWkcMj9qvuuzxX2WJhclOfQO8S4i+R7Jnff9D1pMSioKvdeET
mFzkPNr4udiBNY1orHL47EueHXu+4Tg+lVH+PoUqPCV/PUCULx2+eZdhAoGAN1BE
urFoq62MSQk0rSMULi9xDBvln5KwFGWkz/Co5AQ3uLuhAe4K1/5UudHIGImw+suk
6TWje7kXYbIEap10+XRtv/6/rWws4kkTFYJIJ4jWG45QhBjMdNJiqOJeceDjVqfu
IDS6t27PMgbbXa5z/s/blCoCw0MrMzz/k1z/PKcCgYBlBFcW8VywteGgVvOlj6NP
lMg+ZETFl4PV+/y1as7K8Hj+D7Vzkr1R7SVrFUpd1Sjr/G9q1OjbN56HnnBj7I0D
m+2QTH4c3FJfcbBER+QKzI7RftBIWZv4ZawyPctCAx/qpJ0o01ycjiLzHHFDJXrB
9bbDuonEaSeMm8LCMRyvZQ==
-----END PRIVATE KEY-----
"""


class PeerClosed(Exception):
    pass


class WireReader:
    def __init__(self, connection, stop):
        self.connection = connection
        self.stop = stop
        self.buffer = bytearray()
        self.deadline = time.monotonic() + 5

    def receive(self):
        while not self.stop.is_set():
            if time.monotonic() >= self.deadline:
                raise AssertionError("fixture request read exceeded five seconds")
            try:
                data = self.connection.recv(65536)
            except socket.timeout:
                continue
            if not data:
                raise PeerClosed()
            self.buffer.extend(data)
            return
        raise PeerClosed()

    def until(self, delimiter, limit=65536):
        while True:
            position = self.buffer.find(delimiter)
            if position >= 0:
                assert position <= limit, "fixture header/line limit exceeded"
                result = bytes(self.buffer[:position])
                del self.buffer[:position + len(delimiter)]
                return result
            assert len(self.buffer) <= limit, "fixture header/line limit exceeded"
            self.receive()

    def exact(self, count):
        assert 0 <= count <= 5 * BODY_LIMIT, "fixture request body limit exceeded"
        while len(self.buffer) < count:
            self.receive()
        result = bytes(self.buffer[:count])
        del self.buffer[:count]
        return result

    def request(self):
        self.deadline = time.monotonic() + 5
        first, *lines = self.until(b"\r\n\r\n").split(b"\r\n")
        method, target, version = first.decode("ascii").split(" ")
        headers = {}
        for line in lines:
            name, value = line.split(b":", 1)
            headers.setdefault(name.decode("ascii").lower(), []).append(value.strip())
        if headers.get("expect") == [b"100-continue"]:
            self.connection.sendall(b"HTTP/1.1 100 Continue\r\n\r\n")
        if b"chunked" in b",".join(headers.get("transfer-encoding", [])).lower():
            chunks = []
            total = 0
            while True:
                count = int(self.until(b"\r\n").split(b";", 1)[0], 16)
                total += count
                assert total <= 5 * BODY_LIMIT
                if not count:
                    while self.until(b"\r\n"):
                        pass
                    break
                chunks.append(self.exact(count))
                assert self.exact(2) == b"\r\n"
            body = b"".join(chunks)
        else:
            lengths = headers.get("content-length", [b"0"])
            assert len(lengths) == 1, "duplicate request Content-Length"
            body = self.exact(int(lengths[0]))
        return {"method": method, "target": target, "version": version,
                "headers": headers, "body": body}


class Loopback:
    """Raw HTTP/1.1 server; accepts reuse so new-connection tests are meaningful."""
    def __init__(self, respond, tls=None, handshake_stall=False):
        self.respond = respond
        self.tls = tls
        self.handshake_stall = handshake_stall
        self.stop = threading.Event()
        self.lock = threading.Lock()
        self.connections = []
        self.workers = []
        self.requests = []
        self.errors = []
        self.active = 0
        self.max_active = 0

    def __enter__(self):
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            self.listener.bind(("127.0.0.1", 0))
            self.listener.listen(16)
            self.listener.settimeout(0.1)
            self.port = self.listener.getsockname()[1]
            scheme = "https" if self.tls or self.handshake_stall else "http"
            self.origin = f"{scheme}://127.0.0.1:{self.port}"
            self.thread = threading.Thread(target=self.accept, daemon=True)
            self.thread.start()
            return self
        except BaseException:
            self.listener.close()
            raise

    def accept(self):
        while not self.stop.is_set():
            try:
                connection, _ = self.listener.accept()
            except socket.timeout:
                continue
            except OSError:
                if not self.stop.is_set():
                    self.errors.append("fixture accept failed")
                return
            connection.settimeout(0.2)
            with self.lock:
                number = len(self.connections)
                if number >= 32:
                    self.errors.append("fixture connection cap exceeded (possible retry loop)")
                    connection.close()
                    return
                self.connections.append(connection)
            worker = threading.Thread(target=self.serve, args=(connection, number), daemon=True)
            self.workers.append(worker)
            worker.start()

    def serve(self, connection, number):
        try:
            if self.handshake_stall:
                self.stop.wait(18)
                return
            if self.tls:
                connection.settimeout(3)
                connection = self.tls.wrap_socket(connection, server_side=True)
                with self.lock:
                    self.connections[number] = connection
                connection.settimeout(0.2)
            reader = WireReader(connection, self.stop)
            while not self.stop.is_set():
                request = reader.request()
                request["connection"] = number
                with self.lock:
                    index = len(self.requests)
                    self.requests.append(request)
                    self.active += 1
                    self.max_active = max(self.max_active, self.active)
                try:
                    again = self.respond(self, connection, request, index)
                finally:
                    with self.lock:
                        self.active -= 1
                if not again:
                    return
        except (PeerClosed, OSError):
            # TLS rejection, a client enforcing its body cap, and timeout cleanup
            # intentionally close sockets before the server finishes writing.
            pass
        except BaseException as error:
            self.errors.append(repr(error))
        finally:
            connection.close()

    def __exit__(self, kind, value, traceback):
        self.stop.set()
        self.listener.close()
        self.thread.join(2)
        for connection in self.connections:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            connection.close()
        for worker in self.workers:
            worker.join(2)
        if kind is None:
            assert not self.thread.is_alive(), "fixture accept thread did not stop"
            assert not any(worker.is_alive() for worker in self.workers), "fixture worker did not stop"
            assert not self.errors, self.errors


def send_bytes(server, connection, data):
    remaining = memoryview(data)
    deadline = time.monotonic() + 5
    while remaining and not server.stop.is_set():
        assert time.monotonic() < deadline, "fixture send exceeded five seconds"
        try:
            count = connection.send(remaining)
        except socket.timeout:
            continue
        if not count:
            raise PeerClosed()
        remaining = remaining[count:]


def response(server, connection, body=b"", status=200, headers=(), head=False):
    fields = [("Content-Length", str(len(body))), ("Connection", "keep-alive"),
              ("X-Response-Marker", "response-header-do-not-print"), *headers]
    wire = f"HTTP/1.1 {status} reason-do-not-print\r\n"
    wire += "".join(f"{name}: {value}\r\n" for name, value in fields) + "\r\n"
    send_bytes(server, connection, wire.encode("ascii") + (b"" if head else body))
    return True


def gated_process(command, env, gate, timeout):
    """Observe stdout while the final response is blocked, then drain both pipes."""
    entered, release = gate
    output, errors = bytearray(), bytearray()
    def drain(stream, destination):
        for byte in iter(lambda: stream.read(1), b""):
            destination.extend(byte)
    with subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as process:
        readers = [threading.Thread(target=drain, args=(stream, destination), daemon=True)
                   for stream, destination in ((process.stdout, output), (process.stderr, errors))]
        for reader in readers:
            reader.start()
        try:
            assert entered.wait(5), "client did not reach the final response gate"
            time.sleep(0.2)  # Give pipe readers time to observe premature output.
            assert not output, "run stdout must be buffered until the whole suite succeeds"
            assert process.poll() is None, "client exited before the suite completed"
            release.set()
            process.wait(timeout=timeout)
        finally:
            release.set()
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
            for reader in readers:
                reader.join(2)
            assert not any(reader.is_alive() for reader in readers), "pipe reader did not stop"
        return subprocess.CompletedProcess(command, process.returncode,
                                           output.decode("utf-8", "replace"),
                                           errors.decode("utf-8", "replace"))


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

        # Proxy and CA overrides from a developer shell must not affect local
        # tests or accidentally make the self-signed certificate trusted.
        for name in list(env):
            if name.lower() in {"http_proxy", "https_proxy", "all_proxy", "no_proxy",
                                "ssl_cert_file", "ssl_cert_dir", "curl_ca_bundle",
                                "requests_ca_bundle"}:
                env.pop(name)
        env["NO_PROXY"] = "127.0.0.1,localhost"
        env["REQDIFF_SMOKE_EMPTY"] = ""
        env["REQDIFF_SMOKE_CONTROL"] = "env-control-do-not-print\r\nX-Injected: value"
        secrets = ("credential-do-not-print", "query-do-not-print",
                   "path-do-not-print", "literal-do-not-print", "body-do-not-print",
                   "response-body-do-not-print", "response-header-do-not-print",
                   "reason-do-not-print", "env-control-do-not-print",
                   "X-Smoke-Private", "X-Injected", "Authorization",
                   "REQDIFF_SMOKE_TOKEN", "REQDIFF_SMOKE_MISSING",
                   "REQDIFF_SMOKE_EMPTY", "REQDIFF_SMOKE_CONTROL")

        def run(args, code, contains="", forbidden=(), *, stdout=None, timeout=8, gate=None):
            nonlocal checks
            command = [str(binary), *args]
            if gate is None:
                result = subprocess.run(command, env=env, text=True, encoding="utf-8",
                                        errors="replace", capture_output=True, timeout=timeout)
            else:
                result = gated_process(command, env, gate, timeout)
            assert result.returncode == code, (args, result.returncode, result.stdout, result.stderr)
            combined = result.stdout + result.stderr
            assert contains in combined, (args, combined)
            for secret in (*secrets, *forbidden):
                assert secret.casefold() not in combined.casefold(), (args, "secret leaked")
            if args and args[0] == "run":
                for origin_part in ("127.0.0.1", "localhost", "http://", "https://"):
                    assert origin_part not in combined.casefold(), (args, "origin leaked")
            if code:
                assert not result.stdout, (args, "errors must go to stderr")
                assert result.stderr.strip(), (args, "failure requires a stderr diagnostic")
            else:
                assert not result.stderr, (args, result.stderr)
            if stdout is not None:
                assert result.stdout.splitlines() == stdout, (args, result.stdout, stdout)
            checks += 1
            return result

        def suite(name, records):
            return case(name, "\n".join(json.dumps(record, ensure_ascii=False) for record in records))

        def expected(records, responses):
            return [f"RUN: {len(records)} case(s); requests completed", *[
                f"{record['id']} {record['method']} status={status} bytes={size}"
                for record, (status, size) in zip(records, responses)]]

        def execute(path, server, *, allow_write=False, code=0, lines=None, **options):
            args = ["run", path, "--base-url", server.origin]
            if allow_write:
                args.append("--allow-write")
            return run(args, code, stdout=lines, forbidden=(server.origin,), **options)

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
        # Keep all 22 stage01 checks above; run preflight must finish the entire
        # input and environment validation before even opening a connection.
        first = {"id": "preflight-first", "method": "GET",
                 "path": "/path-do-not-print?token=query-do-not-print"}
        def ok(server, connection, request, index):
            return response(server, connection, b"response-body-do-not-print")

        with Loopback(ok) as server:
            for command in ("validate", "plan"):
                args = [command, valid]
                if command == "plan":
                    args += ["--base-url", server.origin]
                run(args, 0, "no requests sent")
            run(["run", valid], 2, "invalid arguments")
            run(["run", valid, "--base-url"], 2, "invalid arguments")
            for option in (["--insecure"], ["--timeout", "1"]):
                run(["run", valid, "--base-url", server.origin, *option], 2)
            for origin in ("invalid",
                           f"http://user:credential-do-not-print@127.0.0.1:{server.port}",
                           server.origin + "/path-do-not-print",
                           server.origin + "?token=query-do-not-print",
                           server.origin + "#path-do-not-print",
                           server.origin.replace("http://", "ftp://")):
                run(["run", valid, "--base-url", origin], 2, "origin")
            execute(str(root / "absent"), server, code=2)
            execute(str(root), server, code=2)
            prefix = json.dumps(first) + "\n"
            invalid_inputs = [
                ("run-malformed", prefix + '{"body":"body-do-not-print",'),
                ("run-unknown", prefix + json.dumps(dict(first, id="bad", unknown="body-do-not-print"))),
                ("run-duplicate-id", prefix + json.dumps(first)),
                ("run-duplicate-key", prefix + '{"id":"bad","id":"again","method":"GET","path":"/"}'),
                ("run-bad-path", prefix + json.dumps(dict(first, id="bad", path="//path-do-not-print"))),
                ("run-bad-method", prefix + json.dumps(dict(first, id="bad", method="CONNECT"))),
                ("run-body-conflict", prefix + json.dumps(dict(first, id="bad", body=None, body_text="body-do-not-print"))),
                ("run-header-control", prefix + json.dumps(dict(first, id="bad", headers={"X-Smoke-Private": "literal-do-not-print\r\nX-Injected: value"}))),
                ("run-bad-utf8", prefix.encode("utf-8") + b"\xff"),
                ("run-large-line", prefix + " " * (BODY_LIMIT + 1)),
                ("run-large-file", prefix + " \n" * (5 * BODY_LIMIT // 2 + 1)),
                ("run-empty", "\n \n"),
                ("run-too-many", "\n".join(json.dumps(dict(first, id=f"case-{i}")) for i in range(101))),
            ]
            for name, content in invalid_inputs:
                execute(case(name, content), server, code=2)
            for method in ("POST", "PUT", "PATCH", "DELETE", "OPTIONS"):
                path = suite("run-opt-in-" + method, [first, dict(first, id="write", method=method)])
                execute(path, server, code=2)
            for variable in ("REQDIFF_SMOKE_MISSING", "REQDIFF_SMOKE_EMPTY", "REQDIFF_SMOKE_CONTROL"):
                path = suite("run-env-" + variable, [first, dict(
                    first, id="bad-env", headers={"Authorization": {"env": variable}})])
                execute(path, server, code=2)
            time.sleep(0.2)
        assert not server.connections and not server.requests, "preflight/offline commands opened a socket"

        # GET/HEAD need no opt-in, include exact wire target, literal and env
        # headers, UTF-8 response byte counts, and HEAD's bodyless semantics even
        # when Content-Length describes a hypothetical body larger than the cap.
        read_records = [
            dict(first, id="get", headers={"X-Smoke-Private": "literal-do-not-print",
                 "Authorization": {"env": "REQDIFF_SMOKE_TOKEN"}}),
            {"id": "head", "method": "HEAD", "path": "/head-path-do-not-print"},
        ]
        reply = "response-body-do-not-print:雪".encode("utf-8")
        def reads(server, connection, request, index):
            # A delayed first response exposes speculative/parallel dispatch.
            if index == 0:
                server.stop.wait(0.2)
                assert len(server.requests) == 1, "cases were dispatched concurrently"
                return response(server, connection, reply)
            return response(server, connection, b"x" * (BODY_LIMIT + 1), status=404, head=True)
        with Loopback(reads) as server:
            execute(suite("run-reads", read_records), server,
                    lines=expected(read_records, [(200, len(reply)), (404, 0)]))
        assert [(r["method"], r["target"]) for r in server.requests] == [
            (r["method"], r["path"]) for r in read_records]
        assert len(server.connections) == 2
        assert [r["connection"] for r in server.requests] == [0, 1], "connection was reused"
        received = server.requests[0]
        assert received["headers"]["authorization"] == [b"credential-do-not-print"]
        assert received["headers"]["x-smoke-private"] == [b"literal-do-not-print"]
        assert received["headers"]["host"] == [f"127.0.0.1:{server.port}".encode("ascii")]
        assert all(r["body"] == b"" for r in server.requests)
        assert all("content-type" not in r["headers"] for r in server.requests)

        # Every supported method, both body kinds, no body versus JSON null,
        # empty text versus absent text, explicit Content-Type and numeric tokens.
        numeric_body = ('{"huge":900719925474099312345678901234567890,'
                        '"decimal":1.2300e+42,"tiny":-0.00000000000000000000000000000100,'
                        '"negative_zero":-0,"marker":"body-do-not-print"}')
        text = " body-do-not-print:雪\n "
        body_records = [
            {"id": "get-json", "method": "GET", "path": "/get", "body": {"hello": "雪"}},
            {"id": "head-text", "method": "HEAD", "path": "/head", "body_text": text},
            {"id": "post-absent", "method": "POST", "path": "/absent"},
            {"id": "post-null", "method": "POST", "path": "/null", "body": None},
            {"id": "put-text", "method": "PUT", "path": "/text", "body_text": text},
            {"id": "patch-numbers", "method": "PATCH", "path": "/numbers", "body": "__NUMBER_PAYLOAD__"},
            {"id": "delete", "method": "DELETE", "path": "/delete"},
            {"id": "options-empty-text", "method": "OPTIONS", "path": "/options", "body_text": ""},
            {"id": "post-explicit-json", "method": "POST", "path": "/explicit-json",
             "headers": {"cOnTeNt-TyPe": "application/vnd.reqdiff+json; profile=fixture"},
             "body": "body-do-not-print:雪"},
            {"id": "put-explicit-text", "method": "PUT", "path": "/explicit-text",
             "headers": {"Content-Type": "application/octet-stream"}, "body_text": text},
        ]
        body_input = "\n".join(json.dumps(record, ensure_ascii=False) for record in body_records)
        body_input = body_input.replace('"__NUMBER_PAYLOAD__"', numeric_body)
        def bodies(server, connection, request, index):
            return response(server, connection, status=204)
        with Loopback(bodies) as server:
            execute(case("run-bodies", body_input), server, allow_write=True,
                    lines=expected(body_records, [(204, 0)] * len(body_records)))
        assert [r["method"] for r in server.requests] == [r["method"] for r in body_records]
        assert [r["connection"] for r in server.requests] == list(range(len(body_records)))
        assert len(server.connections) == len(body_records), "one new connection is required per case"
        for record, received in zip(body_records, server.requests):
            assert received["target"] == record["path"]
            if "body_text" in record:
                assert received["body"] == record["body_text"].encode("utf-8")
                default_type = b"text/plain; charset=utf-8"
            elif "body" in record:
                if record["id"] == "patch-numbers":
                    compact = b"".join(received["body"].split())
                    assert compact == numeric_body.encode("utf-8"), "JSON numeric representation changed"
                else:
                    assert json.loads(received["body"]) == record["body"]
                if record["id"] == "post-null":
                    assert received["body"] == b"null", "JSON null became an absent body"
                default_type = b"application/json"
            else:
                assert received["body"] == b""
                assert "content-type" not in received["headers"]
                continue
            explicit = next(iter(record.get("headers", {}).values()), None)
            wanted_type = explicit.encode("ascii") if explicit else default_type
            assert received["headers"]["content-type"] == [wanted_type]

        # HTTP status alone never makes run fail; 302 must not follow Location.
        # The gate also observes stdout after earlier responses have completed.
        statuses = [302, 404, 500, 204]
        status_records = [{"id": f"status-{status}", "method": "GET",
                           "path": f"/status-{status}"} for status in statuses]
        entered, release = threading.Event(), threading.Event()
        def status_reply(server, connection, request, index):
            assert index < len(statuses), "redirect was followed or a request retried"
            if index == len(statuses) - 1:
                entered.set()
                assert release.wait(5), "response gate was not released"
            location = [("Location", server.origin + "/redirect-path-do-not-print?token=query-do-not-print")]
            return response(server, connection, b"" if statuses[index] == 204 else reply,
                            status=statuses[index], headers=location if index == 0 else ())
        with Loopback(status_reply) as server:
            execute(suite("run-statuses", status_records), server, gate=(entered, release),
                    lines=expected(status_records, [(s, 0 if s == 204 else len(reply)) for s in statuses]))
        assert len(server.connections) == len(statuses)
        assert [r["target"] for r in server.requests] == [r["path"] for r in status_records]

        # Exact and limit+1 sizes for length-delimited, chunked, and EOF bodies.
        # Overflows deliberately do not send EOF/a final chunk: a bounded reader
        # must reject upon byte limit+1 rather than waiting for termination.
        three = [{"id": name, "method": "GET", "path": "/" + name}
                 for name in ("first", "edge", "last")]
        for framing in ("length", "chunked", "eof"):
            for extra in (0, 1):
                size = BODY_LIMIT + extra
                def edge_reply(server, connection, request, index, framing=framing, size=size, extra=extra):
                    if index != 1:
                        assert index == 0 or not extra, "overflow did not stop later cases"
                        return response(server, connection, b"ok")
                    header = b"HTTP/1.1 200 reason-do-not-print\r\n"
                    payload = b"x" * size
                    if framing == "length":
                        wire = header + f"Content-Length: {size}\r\n\r\n".encode("ascii") + payload
                    elif framing == "chunked":
                        half = BODY_LIMIT // 2
                        wire = header + b"Transfer-Encoding: chunked\r\n\r\n"
                        for chunk in (payload[:half], payload[half:]):
                            wire += f"{len(chunk):x}\r\n".encode("ascii") + chunk + b"\r\n"
                        if not extra:
                            wire += b"0\r\nX-Trailer: response-header-do-not-print\r\n\r\n"
                    else:
                        wire = header + b"Connection: close\r\n\r\n" + payload
                    send_bytes(server, connection, wire)
                    return framing != "eof" or bool(extra)
                with Loopback(edge_reply) as server:
                    execute(suite(f"run-edge-{framing}-{extra}", three), server,
                            code=2 if extra else 0,
                            lines=None if extra else expected(three, [(200, 2), (200, size), (200, 2)]))
                assert len(server.requests) == (2 if extra else 3), "body cap failstop/retry contract"
                assert len(server.connections) == len(server.requests)

        # A failure after one successful response must discard the whole buffered
        # report, stop before the last case, and never retry the broken request.
        broken_wires = {
            "disconnect": b"",
            "partial-header": b"HTTP/1.1 200 reason-do-not-print\r\nX-Response-Marker: response-header-do-not-print",
            "truncated-length": b"HTTP/1.1 200 reason-do-not-print\r\nContent-Length: 99\r\n\r\nshort",
            "truncated-chunk": b"HTTP/1.1 200 reason-do-not-print\r\nTransfer-Encoding: chunked\r\n\r\n40\r\nshort",
            "invalid-status": b"HTTP/1.1 invalid reason-do-not-print\r\nContent-Length: 0\r\n\r\n",
            "status-upgrade": b"HTTP/1.1 101 Switching Protocols\r\n\r\n",
            "status-out-of-range": b"HTTP/1.1 600 reason-do-not-print\r\nContent-Length: 0\r\n\r\n",
            "status-negative": b"HTTP/1.1 -1 reason-do-not-print\r\nContent-Length: 0\r\n\r\n",
        }
        for name, wire in broken_wires.items():
            def broken(server, connection, request, index, wire=wire):
                if index == 0:
                    return response(server, connection, b"ok")
                assert index == 1, "transport failure was retried or later case sent"
                send_bytes(server, connection, wire)
                return False
            with Loopback(broken) as server:
                execute(suite("run-" + name, three), server, code=2)
            assert len(server.requests) == len(server.connections) == 2, name

        # A reserved but non-listening socket guarantees refusal without racing
        # another process for a recently freed ephemeral port.
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as refused:
            refused.bind(("127.0.0.1", 0))
            origin = f"http://127.0.0.1:{refused.getsockname()[1]}"
            run(["run", valid, "--base-url", origin], 2)

        cert_path, key_path = root / "untrusted.pem", root / "public-test-key.pem"
        cert_path.write_text(TLS_CERT, encoding="ascii")
        key_path.write_text(TLS_KEY, encoding="ascii")
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.load_cert_chain(str(cert_path), str(key_path))
        with Loopback(ok, tls=tls) as server:
            execute(valid, server, code=2)
        assert len(server.connections) == 1 and not server.requests, "untrusted TLS accepted/retried"

        # Real wall-clock timeout checks. Outer guards must exceed the client's
        # fixed ten-second lifecycle deadline; stop.wait makes cleanup immediate.
        def slow_body(server, connection, request, index):
            if index == 0:
                return response(server, connection, b"ok")
            assert index == 1, "timeout retried or sent later case"
            if server.stop.wait(6):
                return False
            send_bytes(server, connection, b"HTTP/1.1 200 reason-do-not-print\r\nContent-Length: 2\r\n\r\nx")
            if server.stop.wait(6):
                return False
            send_bytes(server, connection, b"y")
            return True
        with Loopback(slow_body) as server:
            started = time.monotonic()
            execute(suite("run-total-timeout", three), server, code=2, timeout=25)
            elapsed = time.monotonic() - started
            assert 9 <= elapsed < 14, ("expected fixed ten-second whole-lifecycle timeout", elapsed)
        assert len(server.requests) == len(server.connections) == 2
        with Loopback(ok, handshake_stall=True) as server:
            started = time.monotonic()
            execute(valid, server, code=2, timeout=25)
            elapsed = time.monotonic() - started
            assert 9 <= elapsed < 14, ("TLS handshake must share ten-second deadline", elapsed)
        assert len(server.connections) == 1 and not server.requests
        print(f"CLI smoke: {checks} checks passed")


if __name__ == "__main__":
    main()
