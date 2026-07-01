#!/usr/bin/env python3
"""Run local Magic Format evals against a llama.cpp OpenAI-compatible server."""

from __future__ import annotations

import argparse
import difflib
import json
import os
import re
import shutil
import socket
import statistics
import subprocess
import sys
import time
import urllib.error
import urllib.request
from collections import defaultdict
from pathlib import Path


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
    parser.add_argument("--cases", type=Path, default=Path("evals/magic_format_cases.json"))
    parser.add_argument("--prompt", type=Path, default=Path("evals/prompts/gemma_magic_format_v12.txt"))
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    parser.add_argument("--server", default=shutil.which("llama-server") or "/opt/homebrew/bin/llama-server")
    parser.add_argument("--threshold", type=float, default=0.92)
    parser.add_argument("--max-tokens", type=int, default=256)
    parser.add_argument("--timeout", type=float, default=45)
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


def start_server(server: str, model: Path) -> tuple[subprocess.Popen[bytes], str, float]:
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
        "4096",
        "--parallel",
        "1",
        "--reasoning",
        "off",
        "--no-webui",
        "--log-disable",
    ]
    process = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    ready_ms = wait_until_healthy(base_url, process, timeout=90)
    return process, base_url, ready_ms


def normalize(text: str) -> str:
    normalized = text.strip().replace("’", "'").replace("–", "-")
    normalized = re.sub(r"[ \t]+", " ", normalized)
    normalized = re.sub(r"\n{2,}", "\n", normalized)
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


def generate(base_url: str, prompt: str, transcript: str, max_tokens: int, timeout: float) -> tuple[str, float]:
    user_content = f"{prompt}\n\n<transcript>\n{transcript}\n</transcript>"
    payload = {
        "model": "gemma-4-e2b-q4",
        "messages": [
            {"role": "user", "content": user_content},
        ],
        "temperature": 0,
        "top_k": 1,
        "top_p": 1,
        "max_tokens": max_tokens,
        "stream": False,
    }
    request = urllib.request.Request(
        f"{base_url}/v1/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    started = time.perf_counter()
    with urllib.request.urlopen(request, timeout=timeout) as response:
        body = json.loads(response.read().decode("utf-8"))
    latency_ms = (time.perf_counter() - started) * 1000
    choice = body["choices"][0]
    message = choice.get("message") or {}
    content = message.get("content") or choice.get("text") or ""
    return content.strip(), latency_ms


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


def main() -> int:
    args = parse_args()
    if not Path(args.server).exists():
        print(f"llama-server not found: {args.server}", file=sys.stderr)
        return 2
    if not args.model.exists():
        print(f"model not found: {args.model}", file=sys.stderr)
        return 2

    cases = load_cases(args.cases)
    prompt = args.prompt.read_text(encoding="utf-8").strip()

    process: subprocess.Popen[bytes] | None = None
    try:
        process, base_url, ready_ms = start_server(args.server, args.model)
        results = []
        for case in cases:
            try:
                actual, latency_ms = generate(
                    base_url,
                    prompt,
                    case["input"],
                    max_tokens=args.max_tokens,
                    timeout=args.timeout,
                )
                exact, similarity, structure_matches = score_output(actual, case["expected"])
                passed = structure_matches and (exact or similarity >= args.threshold)
                error = None
            except (TimeoutError, urllib.error.URLError, RuntimeError, KeyError, json.JSONDecodeError) as exc:
                actual = ""
                latency_ms = 0.0
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
                    "passed": passed,
                    "error": error,
                }
            )

        exact_count = sum(1 for result in results if result["exact"])
        pass_count = sum(1 for result in results if result["passed"])
        latencies = [result["latency_ms"] for result in results if result["latency_ms"] > 0]
        print(f"Prompt: {args.prompt}")
        print(f"Cases: {len(results)}")
        print(f"Server ready: {ready_ms:.0f} ms")
        print(f"Exact: {exact_count}/{len(results)}")
        print(f"Passed @ {args.threshold:.2f}: {pass_count}/{len(results)}")
        if latencies:
            print(
                "Latency ms: "
                f"avg={statistics.mean(latencies):.0f} "
                f"median={statistics.median(latencies):.0f} "
                f"max={max(latencies):.0f}"
            )

        by_category: dict[str, list[dict[str, object]]] = defaultdict(list)
        for result in results:
            by_category[str(result["category"])].append(result)
        print("\nBy category:")
        for category in sorted(by_category):
            rows = by_category[category]
            passed = sum(1 for row in rows if row["passed"])
            exact = sum(1 for row in rows if row["exact"])
            print(f"- {category}: exact={exact}/{len(rows)} passed={passed}/{len(rows)}")

        failures = [result for result in results if not result["passed"]]
        if failures:
            print("\nFailures:")
            for result in failures:
                print(f"\n{result['id']} [{result['category']}] similarity={result['similarity']}")
                if result["error"]:
                    print(f"error: {result['error']}")
                print(f"input:    {result['input']}")
                print(f"expected: {result['expected']}")
                print(f"actual:   {result['actual']}")

        if args.json_output:
            args.json_output.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")

        return 0 if pass_count == len(results) else 1
    finally:
        if process and not args.keep_server:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()


if __name__ == "__main__":
    raise SystemExit(main())
