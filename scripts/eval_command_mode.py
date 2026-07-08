#!/usr/bin/env python3
"""Command Mode tool-call eval against a llama.cpp OpenAI-compatible server.

Single-turn: given the brain prompt + a screen observation + short history, the
model must emit ONE `{"tool","arguments"}` call. We score valid-JSON rate,
tool-name accuracy, and argument match — the signal that drives dedicated-model
selection (Phase 6). Mirrors `eval_magic_format.py`'s server/health scaffolding.
"""

from __future__ import annotations

import argparse
import json
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
    parser.add_argument("--cases", type=Path, default=Path("evals/command_mode_cases.json"))
    parser.add_argument("--prompt", type=Path, default=Path("evals/prompts/command_mode_v1.txt"))
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    parser.add_argument("--server", default=shutil.which("llama-server") or "/opt/homebrew/bin/llama-server")
    parser.add_argument("--max-tokens", type=int, default=128)
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
        server, "--model", str(model), "--host", "127.0.0.1", "--port", str(port),
        "--ctx-size", "4096", "--parallel", "1", "--reasoning", "off",
        "--no-webui", "--log-disable",
    ]
    process = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    ready_ms = wait_until_healthy(base_url, process, timeout=90)
    return process, base_url, ready_ms


def build_instructions(prompt: str, history: list[str], observation: str) -> str:
    """Reproduce `LocalLLMAgentBrain`'s instruction assembly (static prompt block
    from the file, then the runtime history + screen)."""
    recent = "\n".join(history[-6:])
    return (
        f"{prompt}\n"
        "Recent steps (oldest first, most recent last):\n"
        f"{recent}\n"
        "Current screen:\n"
        f"{observation}"
    )


def generate(base_url: str, instructions: str, utterance: str, max_tokens: int, timeout: float) -> tuple[str, float]:
    # Single user message (Gemma runs without a system role when --jinja is off),
    # matching the Magic Format eval's proven transport.
    user_content = f"{instructions}\n\n<task>\n{utterance}\n</task>"
    payload = {
        "model": "gemma-4-e2b-q4",
        "messages": [{"role": "user", "content": user_content}],
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


def extract_tool_call(raw: str) -> dict | None:
    """Tolerant brace-matched JSON extraction, mirroring the Swift ToolCallParser:
    take the first balanced {...} and parse it."""
    start = raw.find("{")
    if start < 0:
        return None
    depth = 0
    in_string = False
    escaped = False
    for i in range(start, len(raw)):
        ch = raw[i]
        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            continue
        if ch == '"':
            in_string = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                try:
                    obj = json.loads(raw[start : i + 1])
                    return obj if isinstance(obj, dict) else None
                except json.JSONDecodeError:
                    return None
    return None


def normalize_value(key: str, value: object) -> str:
    text = str(value).strip().lower()
    if key == "keys":
        # Chord-normalize so "Command+T" == "cmd+t" (KeyChord.parse accepts both).
        text = text.replace(" ", "")
        for long, short in (("command", "cmd"), ("option", "opt"), ("control", "ctrl"), ("return", "enter")):
            text = text.replace(long, short)
        parts = text.split("+")
        if len(parts) > 1:
            *mods, base = parts
            text = "+".join(sorted(mods) + [base])
    return text


def score(raw: str, expected_tool: str, expected_args: dict) -> dict:
    call = extract_tool_call(raw)
    valid_json = isinstance(call, dict) and isinstance(call.get("tool"), str)
    tool = call.get("tool") if valid_json else None
    if valid_json and isinstance(call.get("arguments"), dict):
        args = call["arguments"]
    elif valid_json:
        # Mirror ToolCallParser's flattened-args tolerance: a model may drop the
        # "arguments" wrapper and put the arg at the top level.
        args = {k: v for k, v in call.items() if k != "tool"}
    else:
        args = {}
    tool_match = valid_json and tool == expected_tool
    args_match = True
    for key, want in expected_args.items():
        if key not in args or normalize_value(key, args[key]) != normalize_value(key, want):
            args_match = False
            break
    return {
        "valid_json": bool(valid_json),
        "tool": tool,
        "tool_match": bool(tool_match),
        "args_match": bool(args_match),
        "passed": bool(tool_match and args_match),
    }


def load_cases(path: Path) -> list[dict]:
    cases = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(cases, list):
        raise ValueError("cases file must contain a JSON array")
    required = {"id", "category", "utterance", "observation", "expected_tool", "expected_args"}
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
                instructions = build_instructions(prompt, case.get("history", []), case["observation"])
                actual, latency_ms = generate(base_url, instructions, case["utterance"], args.max_tokens, args.timeout)
                scored = score(actual, case["expected_tool"], case["expected_args"])
                error = None
            except (TimeoutError, urllib.error.URLError, RuntimeError, KeyError, json.JSONDecodeError) as exc:
                actual, latency_ms = "", 0.0
                scored = {"valid_json": False, "tool": None, "tool_match": False, "args_match": False, "passed": False}
                error = str(exc)
            results.append({**case, "actual": actual, "latency_ms": round(latency_ms), **scored, "error": error})

        total = len(results)
        valid = sum(1 for r in results if r["valid_json"])
        tool_ok = sum(1 for r in results if r["tool_match"])
        passed = sum(1 for r in results if r["passed"])
        latencies = [r["latency_ms"] for r in results if r["latency_ms"] > 0]

        print(f"Prompt: {args.prompt}")
        print(f"Model:  {args.model.name}")
        print(f"Cases: {total}")
        print(f"Server ready: {ready_ms:.0f} ms")
        print(f"Valid JSON:     {valid}/{total}")
        print(f"Tool accuracy:  {tool_ok}/{total}")
        print(f"Passed (tool+args): {passed}/{total}")
        if latencies:
            print(f"Latency ms: avg={statistics.mean(latencies):.0f} median={statistics.median(latencies):.0f} max={max(latencies):.0f}")

        by_category: dict[str, list[dict]] = defaultdict(list)
        for r in results:
            by_category[str(r["category"])].append(r)
        print("\nBy category:")
        for category in sorted(by_category):
            rows = by_category[category]
            print(f"- {category}: passed={sum(1 for x in rows if x['passed'])}/{len(rows)}")

        failures = [r for r in results if not r["passed"]]
        if failures:
            print("\nFailures:")
            for r in failures:
                print(f"\n{r['id']} [{r['category']}]  valid_json={r['valid_json']} tool={r['tool']!r} (want {r['expected_tool']!r})")
                if r["error"]:
                    print(f"error: {r['error']}")
                print(f"utterance: {r['utterance']}")
                print(f"actual:    {r['actual'][:240]}")

        if args.json_output:
            args.json_output.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")

        return 0 if passed == total else 1
    finally:
        if process and not args.keep_server:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()


if __name__ == "__main__":
    raise SystemExit(main())
