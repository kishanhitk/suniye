#!/usr/bin/env python3
"""Local server for the ASR comparison page: saves clips, runs the comparison
test, serves results and stores reviews. No dependencies beyond the stdlib.

    python3 evals/asr-compare/server.py   # then open http://127.0.0.1:8765
"""
import json
import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
CLIPS = HERE / "clips"
CLIPS.mkdir(exist_ok=True)
PORT = int(os.environ.get("PORT", "8765"))


def run_comparison() -> tuple[int, str]:
    env = dict(os.environ, TEST_RUNNER_SUNIYE_ASR_COMPARE_DIR=str(CLIPS))
    cmd = [
        "xcodebuild", "test",
        "-project", "Suniye.xcodeproj", "-scheme", "Suniye",
        "-destination", "platform=macOS,arch=arm64",
        "-derivedDataPath", ".derivedData",
        "-only-testing:SuniyeTests/ASRModelComparisonTests",
        "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES",
    ]
    proc = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True)
    lines = [
        l for l in proc.stdout.splitlines()
        if ("asr-compare:" in l or "error:" in l or "** TEST" in l) and "linkd" not in l and "crashhandler" not in l
    ]
    return proc.returncode, "\n".join(lines[-40:])


ALLOWED_ORIGIN = f"http://127.0.0.1:{PORT}"


class Handler(BaseHTTPRequestHandler):
    def _same_origin(self) -> bool:
        # Browsers send Origin on every POST/DELETE; only the page served from this
        # server may start xcodebuild or write clips on this machine.
        if self.headers.get("Origin") != ALLOWED_ORIGIN:
            self._json(403, {"error": "cross-origin request rejected"})
            return False
        return True

    def _send(self, status: int, body: bytes, content_type: str = "application/json") -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _json(self, status: int, obj) -> None:
        self._send(status, json.dumps(obj).encode())

    def _body(self) -> bytes:
        return self.rfile.read(int(self.headers.get("Content-Length", "0")))

    def do_GET(self) -> None:
        if self.path == "/":
            self._send(200, (HERE / "index.html").read_bytes(), "text/html; charset=utf-8")
        elif self.path == "/clips":
            self._json(200, sorted(p.name for p in CLIPS.glob("*.wav")))
        elif self.path.startswith("/clips/"):
            target = CLIPS / os.path.basename(self.path[len("/clips/"):])
            if target.suffix == ".wav" and target.exists():
                self._send(200, target.read_bytes(), "audio/wav")
            else:
                self._json(404, {"error": "no such clip"})
        elif self.path in ("/results", "/reviews"):
            target = CLIPS / f"{self.path[1:]}.json"
            self._send(200, target.read_bytes() if target.exists() else b"null")
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self) -> None:
        if not self._same_origin():
            return
        if self.path.startswith("/clips/"):
            name = os.path.basename(self.path[len("/clips/"):])
            if not name.endswith(".wav"):
                return self._json(400, {"error": "clip name must end in .wav"})
            (CLIPS / name).write_bytes(self._body())
            self._json(200, {"saved": name})
        elif self.path == "/run":
            code, log = run_comparison()
            self._json(200 if code == 0 else 500, {"exitCode": code, "log": log})
        elif self.path == "/reviews":
            (CLIPS / "reviews.json").write_bytes(self._body())
            self._json(200, {"saved": True})
        else:
            self._json(404, {"error": "not found"})

    def do_DELETE(self) -> None:
        if not self._same_origin():
            return
        if self.path.startswith("/clips/"):
            target = CLIPS / os.path.basename(self.path[len("/clips/"):])
            if target.suffix == ".wav" and target.exists():
                target.unlink()
            self._json(200, {"deleted": target.name})
        else:
            self._json(404, {"error": "not found"})

    def log_message(self, fmt, *args):  # quieter than the default
        sys.stderr.write("%s %s\n" % (self.command, self.path))


if __name__ == "__main__":
    print(f"asr-compare: http://127.0.0.1:{PORT}  (clips in {CLIPS})")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
