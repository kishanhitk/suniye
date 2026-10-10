import Foundation

/// A Python stand-in for llama-server. It answers `/health` and
/// `/v1/chat/completions` behind the API key, logs `start`, `term`, and one
/// `request` line per completion to `logURL`, and saves each completion body
/// as `request-<n>.json` next to itself.
enum FakeLlamaServer {
    static func make(
        in directory: URL,
        logURL: URL,
        reply: String = "OK",
        finishReason: String = "stop",
        healthStatus: Int = 200,
        completionStatus: Int = 200,
        startupDelaySeconds: Double = 0,
        terminationDelaySeconds: Double = 0
    ) throws -> URL {
        let scriptURL = directory.appendingPathComponent("fake-llama-server")
        let script = """
        #!/usr/bin/python3
        import json
        import os
        import signal
        import sys
        import time
        import traceback
        from http.server import BaseHTTPRequestHandler, HTTPServer

        log_path = \(try jsonLiteral(logURL.path))
        request_dir = \(try jsonLiteral(directory.path))
        try:
            port = int(sys.argv[sys.argv.index("--port") + 1])
            api_key = sys.argv[sys.argv.index("--api-key") + 1]
            reply = \(try jsonLiteral(reply))
            finish_reason = \(try jsonLiteral(finishReason))
            health_status = \(healthStatus)
            completion_status = \(completionStatus)
            startup_delay_seconds = \(startupDelaySeconds)
            termination_delay_seconds = \(terminationDelaySeconds)
        except Exception:
            with open(log_path, "a", encoding="utf-8") as log:
                log.write("argument_error\\n")
                log.write(traceback.format_exc())
            raise

        def log_line(line):
            with open(log_path, "a", encoding="utf-8") as log:
                log.write(line + "\\n")

        def handle_sigterm(signum, frame):
            log_line("term")
            time.sleep(termination_delay_seconds)
            sys.exit(0)

        signal.signal(signal.SIGTERM, handle_sigterm)
        log_line("start")
        time.sleep(startup_delay_seconds)
        requests = 0

        class Handler(BaseHTTPRequestHandler):
            def _authorized(self):
                return self.headers.get("Authorization") == "Bearer " + api_key

            def do_GET(self):
                if self.path != "/health":
                    self.send_response(404)
                    self.end_headers()
                    return
                self.send_response(health_status if self._authorized() else 401)
                self.end_headers()
                self.wfile.write(b"ok")

            def do_POST(self):
                global requests
                if self.path != "/v1/chat/completions":
                    self.send_response(404)
                    self.end_headers()
                    return
                body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
                if not self._authorized():
                    self.send_response(401)
                    self.end_headers()
                    return
                requests += 1
                with open(os.path.join(request_dir, "request-%d.json" % requests), "wb") as saved:
                    saved.write(body)
                log_line("request")
                if completion_status != 200:
                    self.send_response(completion_status)
                    self.end_headers()
                    return
                payload = json.dumps({
                    "choices": [{"message": {"content": reply}, "finish_reason": finish_reason}],
                    "timings": {"prompt_n": 42, "cache_n": 0, "predicted_n": 7, "prompt_ms": 12.5, "predicted_ms": 30.0},
                }).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            def log_message(self, format, *args):
                pass

        HTTPServer(("127.0.0.1", port), Handler).serve_forever()
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    static func count(of line: String, at logURL: URL) -> Int {
        logContents(at: logURL)
            .split(separator: "\n")
            .filter { $0 == line }
            .count
    }

    static func logContents(at logURL: URL) -> String {
        (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
    }

    /// The JSON body of completion request `number` (1-based).
    static func requestBody(_ number: Int, in directory: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: directory.appendingPathComponent("request-\(number).json"))
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    /// Polls until `line` appears `expectedCount` times. The fake's cold start can
    /// take seconds under CI's parallel-test CPU load.
    static func waitForCount(of line: String, toReach expectedCount: Int, at logURL: URL, timeout: TimeInterval = 15) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if count(of: line, at: logURL) >= expectedCount {
                return true
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return false
    }

    private static func jsonLiteral(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8)!
            .replacingOccurrences(of: "\\/", with: "/")
    }
}
