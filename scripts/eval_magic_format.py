#!/usr/bin/env python3
"""Run local Magic Format evals against a llama.cpp OpenAI-compatible server.

Requests are uncapped by default, matching the app: the model runs to its
end-of-turn or the context window. A case whose answer stops on a length limit
(`finish_reason == "length"`) fails regardless of similarity, because the app
rejects such output and falls back to the raw transcript. Each request gets the
app's own deadline (30 s plus one second per 80 input characters) unless
--timeout overrides it.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import ctypes
import difflib
import json
import os
import re
import shutil
import socket
import statistics
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from collections import defaultdict
from pathlib import Path
from typing import Any


DEFAULT_MODEL = (
    Path.home()
    / "Library"
    / "Application Support"
    / "Suniye"
    / "llm"
    / "gemma-4-e2b-Q4_K_M.gguf"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cases", type=Path, nargs="+", default=[Path("evals/magic_format_cases.json")])
    parser.add_argument("--rounds", type=int, default=1, help="times to run each cases file on the one server")
    parser.add_argument(
        "--server-arg",
        action="append",
        default=[],
        help="extra llama-server argument; repeat it (use --server-arg=--flag for a value that starts with a dash)",
    )
    parser.add_argument("--prompt", type=Path, default=Path("evals/prompts/gemma_magic_format_v14.txt"))
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    parser.add_argument("--server", default=shutil.which("llama-server") or "/opt/homebrew/bin/llama-server")
    parser.add_argument("--threshold", type=float, default=0.92)
    parser.add_argument("--max-tokens", type=int, help="cap output tokens; omitted by default, like the app")
    parser.add_argument(
        "--timeout",
        type=float,
        help="request deadline in seconds; default mirrors the app: 30 + len(input)/80",
    )
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--keep-server", action="store_true")
    return parser.parse_args()


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def wait_until_healthy(base_url: str, process: subprocess.Popen[bytes], timeout: float) -> float:
    start = time.perf_counter()
    deadline = start + timeout
    while time.perf_counter() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"llama-server exited with code {process.returncode}")
        try:
            with urllib.request.urlopen(f"{base_url}/health", timeout=1) as response:
                if 200 <= response.status < 300:
                    return (time.perf_counter() - start) * 1000
        except Exception:
            time.sleep(0.2)
    raise TimeoutError("Timed out waiting for llama-server /health")


class MemoryWatch:
    """Polls the resident size of one process and reads its peak physical footprint."""

    RUSAGE_INFO_V4 = 4
    RESIDENT_SIZE = 6
    LIFETIME_MAX_PHYS_FOOTPRINT = 28

    def __init__(self, pid: int) -> None:
        self.pid = pid
        self.peak_rss = 0
        self.peak_footprint = 0
        self._libproc = ctypes.CDLL("/usr/lib/libproc.dylib")
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._poll, daemon=True)
        self._thread.start()

    def _read(self) -> None:
        buffer = (ctypes.c_uint64 * 64)()
        if self._libproc.proc_pid_rusage(self.pid, self.RUSAGE_INFO_V4, ctypes.byref(buffer)) != 0:
            return
        fields = buffer[2:]
        self.peak_rss = max(self.peak_rss, fields[self.RESIDENT_SIZE])
        self.peak_footprint = max(self.peak_footprint, fields[self.LIFETIME_MAX_PHYS_FOOTPRINT])

    def _poll(self) -> None:
        while not self._stop.wait(0.1):
            self._read()

    def stop(self) -> None:
        self._read()
        self._stop.set()
        self._thread.join()


def start_server(server: str, model: Path, extra_args: list[str]) -> tuple[subprocess.Popen[bytes], str, float]:
    port = free_port()
    base_url = f"http://127.0.0.1:{port}"
    args = [
        server,
        "--model",
        str(model),
        "--host",
        "127.0.0.1",
        "--port",
        str(port),
        "--ctx-size",
        "16384",
        "--parallel",
        "1",
        "--reasoning",
        "off",
        "--no-webui",
        "--log-disable",
        *extra_args,
    ]
    process = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    ready_ms = wait_until_healthy(base_url, process, timeout=90)
    return process, base_url, ready_ms


# Mirrors Suniye/MagicFormat/MagicFormatParagraphBreaks.swift, which the app applies
# around every Magic Format request.
NOUN_PHRASE_WORDS = [
    "a", "an", "the", "this", "that", "each", "every", "another", "any", "one", "no", "some", "more",
    "my", "your", "our", "their", "his", "her", "its",
    "whole", "entire", "short", "long", "next", "last", "first", "final", "brand", "separate", "fresh", "extra",
]
NOUN_FOLLOWERS = [
    "break", "breaks", "spacing", "style", "format", "formatting", "mark", "symbol", "tag",
    "setting", "button", "key", "command", "indent",
]
PARAGRAPH_COMMAND = re.compile(
    r"(?i)\s*"
    + "".join(rf"(?<!\b{word} )" for word in NOUN_PHRASE_WORDS)
    + r"\bnew\s+paragraph\b(?!\s+(?:"
    + "|".join(NOUN_FOLLOWERS)
    + r")\b)[\s,.;:]*"
)


def apply_paragraph_breaks(transcript: str) -> str:
    applied = PARAGRAPH_COMMAND.sub("\n\n", transcript)
    return re.sub(r"\n{3,}", "\n\n", applied).strip()


def blank_line_gap_count(text: str) -> int:
    lines = text.splitlines()
    return sum(1 for before, after in zip(lines, lines[1:]) if before.strip() and not after.strip())


def separate_paragraphs(answer: str, dictated_count: int) -> str:
    if dictated_count == 0 or blank_line_gap_count(answer) > 0:
        return answer
    lines = [line for line in answer.splitlines() if line]
    if len(lines) != dictated_count + 1:
        return answer
    return "\n\n".join(line.strip() for line in lines)


def capitalize_paragraph_starts(text: str) -> str:
    lines = text.split("\n")
    for index in range(1, len(lines)):
        if lines[index - 1].strip() or not lines[index].strip():
            continue
        first_word = lines[index].split()[0] if lines[index].split() else ""
        if lines[index][:1].islower() and not any(ch.isupper() for ch in first_word):
            lines[index] = lines[index][0].upper() + lines[index][1:]
    return "\n".join(lines)


def normalize(text: str) -> str:
    normalized = text.strip().replace("’", "'").replace("–", "-")
    normalized = re.sub(r"[ \t]+", " ", normalized)
    return normalized


def line_signature(text: str) -> list[tuple[str, str]]:
    signature: list[tuple[str, str]] = []
    for raw_line in normalize(text).splitlines():
        line = raw_line.strip()
        numbered = re.match(r"^(\d+)\.\s+(.*)$", line)
        if numbered:
            signature.append(("numbered", normalize_list_text(numbered.group(2))))
        elif line.startswith("- "):
            signature.append(("bullet", normalize_list_text(line[2:])))
        else:
            signature.append(("text", normalize_list_text(line)))
    return signature


def normalize_list_text(text: str) -> str:
    value = normalize(text).lower()
    value = re.sub(r"[\.:]+$", "", value)
    return value


def list_structure_matches(actual: str, expected: str) -> bool:
    if "\n" not in expected:
        return True
    return line_signature(actual) == line_signature(expected)


def score_output(actual: str, expected: str) -> tuple[bool, float, bool]:
    actual_norm = normalize(actual)
    expected_norm = normalize(expected)
    structure_matches = list_structure_matches(actual, expected)
    if actual_norm == expected_norm:
        return True, 1.0, structure_matches
    similarity = difflib.SequenceMatcher(None, actual_norm.lower(), expected_norm.lower()).ratio()
    return False, similarity, structure_matches


def read_within(request: urllib.request.Request, deadline_seconds: float) -> bytes:
    """Fetch the whole response under one wall-clock deadline, like the app.

    urlopen's timeout bounds each socket operation, so a server that trickles
    bytes could run past the budget; a thread plus a bounded wait cannot.
    """
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
        future = pool.submit(
            lambda: urllib.request.urlopen(request, timeout=deadline_seconds).read()
        )
        try:
            return future.result(timeout=deadline_seconds)
        except concurrent.futures.TimeoutError as exc:
            future.cancel()
            raise TimeoutError(f"request exceeded {deadline_seconds:.1f}s deadline") from exc


def generate(
    base_url: str, prompt: str, transcript: str, max_tokens: int | None, timeout: float
) -> tuple[str, float, str | None, dict[str, Any]]:
    user_content = f"{prompt}\n\n<transcript>\n{transcript}\n</transcript>"
    payload = {
        "model": "gemma-4-e2b-q4",
        "messages": [
            {"role": "user", "content": user_content},
        ],
        "temperature": 0,
        "top_k": 1,
        "top_p": 1,
        "stream": False,
    }
    if max_tokens is not None:
        payload["max_tokens"] = max_tokens
    request = urllib.request.Request(
        f"{base_url}/v1/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    started = time.perf_counter()
    body = json.loads(read_within(request, timeout).decode("utf-8"))
    latency_ms = (time.perf_counter() - started) * 1000
    choice = body["choices"][0]
    message = choice.get("message") or {}
    content = message.get("content") or choice.get("text") or ""
    server_numbers = dict(body.get("timings") or {})
    server_numbers["reasoning_chars"] = len(message.get("reasoning_content") or "")
    return content.strip(), latency_ms, choice.get("finish_reason"), server_numbers


def load_cases(path: Path) -> list[dict[str, str]]:
    cases = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(cases, list):
        raise ValueError("cases file must contain a JSON array")
    required = {"id", "category", "input", "expected"}
    for case in cases:
        missing = required.difference(case)
        if missing:
            raise ValueError(f"case missing keys {sorted(missing)}: {case}")
    return cases


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    position = fraction * (len(ordered) - 1)
    low = int(position)
    high = min(low + 1, len(ordered) - 1)
    return ordered[low] + (ordered[high] - ordered[low]) * (position - low)


def run_cases(base_url: str, prompt: str, cases: list[dict[str, str]], args: argparse.Namespace) -> list[dict[str, Any]]:
    results = []
    for case in cases:
        server_numbers: dict[str, Any] = {}
        try:
            transcript = apply_paragraph_breaks(case["input"])
            answer, latency_ms, finish_reason, server_numbers = generate(
                base_url,
                prompt,
                transcript,
                max_tokens=args.max_tokens,
                timeout=args.timeout or 30 + len(case["input"]) / 80,
            )
            actual = capitalize_paragraph_starts(separate_paragraphs(answer, blank_line_gap_count(transcript)))
            exact, similarity, structure_matches = score_output(actual, case["expected"])
            truncated = finish_reason == "length"
            passed = structure_matches and not truncated and (exact or similarity >= args.threshold)
            error = None
        except (TimeoutError, urllib.error.URLError, RuntimeError, KeyError, json.JSONDecodeError) as exc:
            actual = ""
            latency_ms = 0.0
            finish_reason = None
            truncated = False
            exact = False
            similarity = 0.0
            structure_matches = False
            passed = False
            error = str(exc)

        results.append(
            {
                **case,
                "actual": actual,
                "latency_ms": round(latency_ms),
                "exact": exact,
                "similarity": round(similarity, 3),
                "structure_matches": structure_matches,
                "finish_reason": finish_reason,
                "truncated": truncated,
                "passed": passed,
                "error": error,
                "server": server_numbers,
            }
        )
    return results


def summarize(results: list[dict[str, Any]]) -> dict[str, Any]:
    latencies = [float(result["latency_ms"]) for result in results if result["latency_ms"]]
    injection = [result for result in results if result["category"] == "injection_resistance"]
    drafted = sum(int(result["server"].get("draft_n") or 0) for result in results)
    accepted = sum(int(result["server"].get("draft_n_accepted") or 0) for result in results)
    predicted = sum(int(result["server"].get("predicted_n") or 0) for result in results)
    predicted_ms = sum(float(result["server"].get("predicted_ms") or 0) for result in results)
    return {
        "cases": len(results),
        "passed": sum(1 for result in results if result["passed"]),
        "exact": sum(1 for result in results if result["exact"]),
        "truncated": sum(1 for result in results if result["truncated"]),
        "errors": sum(1 for result in results if result["error"]),
        "with_reasoning_text": sum(1 for result in results if result["server"].get("reasoning_chars")),
        "injection_passed": sum(1 for result in injection if result["passed"]),
        "injection_cases": len(injection),
        "latency_p50_ms": round(percentile(latencies, 0.5)) if latencies else None,
        "latency_p90_ms": round(percentile(latencies, 0.9)) if latencies else None,
        "latency_avg_ms": round(statistics.mean(latencies)) if latencies else None,
        "latency_max_ms": round(max(latencies)) if latencies else None,
        "predicted_tokens": predicted,
        "decode_tokens_per_second": round(predicted / predicted_ms * 1000, 1) if predicted_ms else None,
        "draft_tokens": drafted,
        "draft_tokens_accepted": accepted,
    }


def print_report(cases_path: Path, round_index: int, results: list[dict[str, Any]], summary: dict[str, Any]) -> None:
    print(f"\n=== {cases_path} round {round_index + 1}")
    print(f"Exact: {summary['exact']}/{summary['cases']}")
    print(f"Passed: {summary['passed']}/{summary['cases']}")
    print(f"Truncated: {summary['truncated']}/{summary['cases']}")
    print(
        "Latency ms: "
        f"avg={summary['latency_avg_ms']} p50={summary['latency_p50_ms']} "
        f"p90={summary['latency_p90_ms']} max={summary['latency_max_ms']}"
    )
    by_category: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for result in results:
        by_category[str(result["category"])].append(result)
    print("By category:")
    for category in sorted(by_category):
        rows = by_category[category]
        passed = sum(1 for row in rows if row["passed"])
        exact = sum(1 for row in rows if row["exact"])
        print(f"- {category}: exact={exact}/{len(rows)} passed={passed}/{len(rows)}")
    failures = [result for result in results if not result["passed"]]
    if failures:
        print("Failures:")
        for result in failures:
            print(f"\n{result['id']} [{result['category']}] similarity={result['similarity']}")
            if result["error"]:
                print(f"error: {result['error']}")
            if result["truncated"]:
                print("truncated: output stopped on a length limit")
            print(f"input:    {result['input']}")
            print(f"expected: {result['expected']}")
            print(f"actual:   {result['actual']}")


def main() -> int:
    args = parse_args()
    if not Path(args.server).exists():
        print(f"llama-server not found: {args.server}", file=sys.stderr)
        return 2
    if not args.model.exists():
        print(f"model not found: {args.model}", file=sys.stderr)
        return 2

    suites = [(path, load_cases(path)) for path in args.cases]
    prompt = args.prompt.read_text(encoding="utf-8").strip()

    process: subprocess.Popen[bytes] | None = None
    watch: MemoryWatch | None = None
    try:
        process, base_url, ready_ms = start_server(args.server, args.model, args.server_arg)
        watch = MemoryWatch(process.pid)
        print(f"Prompt: {args.prompt}")
        print(f"Model: {args.model}")
        print(f"Server ready: {ready_ms:.0f} ms")

        # The app sends this request before the first dictation, so the first
        # scored case reads the prompt from the server's cache as in the app.
        warmup: dict[str, Any] = {}
        try:
            _, warmup_ms, _, warmup_numbers = generate(base_url, prompt, "warm up", max_tokens=8, timeout=120)
            warmup = {"latency_ms": round(warmup_ms), "server": warmup_numbers}
        except (TimeoutError, urllib.error.URLError, RuntimeError, KeyError, json.JSONDecodeError) as exc:
            warmup = {"error": str(exc)}
        print(f"Warm-up request: {warmup}")

        runs = []
        for round_index in range(args.rounds):
            for cases_path, cases in suites:
                results = run_cases(base_url, prompt, cases, args)
                summary = summarize(results)
                print_report(cases_path, round_index, results, summary)
                runs.append({"cases_file": str(cases_path), "round": round_index + 1, "summary": summary, "results": results})

        watch.stop()
        report = {
            "model": str(args.model),
            "model_bytes": args.model.stat().st_size,
            "server": args.server,
            "server_args": args.server_arg,
            "prompt": str(args.prompt),
            "server_ready_ms": round(ready_ms),
            "warmup": warmup,
            "peak_rss_bytes": watch.peak_rss,
            "peak_footprint_bytes": watch.peak_footprint,
            "runs": runs,
        }
        print(f"\nPeak RSS: {watch.peak_rss / 1e6:.0f} MB, peak footprint: {watch.peak_footprint / 1e6:.0f} MB")
        if args.json_output:
            args.json_output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

        return 0 if all(run["summary"]["passed"] == run["summary"]["cases"] for run in runs) else 1
    finally:
        if watch:
            watch.stop()
        if process and not args.keep_server:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()


if __name__ == "__main__":
    raise SystemExit(main())
