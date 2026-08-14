# KIS-179 implementation plan: code-mode Computer Use

Date: 2026-08-14. Branch: `kis-179-code-mode`, stacked on `kis-169-always-listening`
(PR #95). Evidence base: `code-mode-recovery-2026-08-14.md` (ChatGPT 26.810.41047)
and `parity-report-chatgpt-2026-08-14.md` (26.727.51351).

## Goal

Replace the ten-tool JSON function-calling contract with a single `node_repl`-style
tool. The model writes JavaScript against a pre-injected `sky.*` API; sequencing and
error handling live in the code, so one model round-trip can perform a short action
batch safely. The native tool backend, observation service, catalog, and action
layers do not change.

## Non-goals

- The window2 and full-desktop API targets (Windows port and hosted-VM surfaces in
  the reference; out of scope).
- The safety layer (per-app approval elicitation, app policy, confirmation
  taxonomy). Deferred by product decision. The bridge built here is the
  interposition point where it lands later, mirroring `withComputerUsePolicy`.
- A bundled Node runtime. The reference ships `cua_node`; Suniye uses
  JavaScriptCore, which ships with macOS.
- Audio recording methods (`SKY_ENABLE_AUDIO` surface in the reference).

## Architecture

One new component plus focused edits:

```
model ── node_repl {code} ──> ComputerUseAgent
                                   │ execute script
                                   ▼
                     ComputerUseScriptRuntime (JavaScriptCore)
                       sky.click(...) ─┐
                       sky.get_app_state(...) ─┤ JSON-encode args
                       nodeRepl.write(...)     │
                                   ▼           ▼
                     ComputerUseModelToolCallDecoder (unchanged schema gate)
                                   ▼
                     ComputerUseToolBackend (unchanged)
```

Design rule carried over from the reference: the JS layer is thin; every `sky.*`
call is one bridge crossing that the host observes. Activity narration, analytics,
audit bookkeeping, and (later) policy all attach at the bridge, never inside JS.

### ComputerUseScriptRuntime

New file `Suniye/Services/ComputerUseScriptRuntime.swift`.

- One `JSContext` per agent run, created lazily on the first `node_repl` call and
  retained for the run ("node_repl state is persistent across calls").
- All JS execution confined to a serial dispatch queue; `JSContext` is not
  thread-safe.
- `sky` is a pre-injected object. Each method converts its single JS argument to
  JSON, runs it through `ComputerUseModelToolCallDecoder.decode(name:arguments:)` —
  the existing schema gate, so argument validation and error text stay identical to
  the function-calling path — and executes through the existing
  `ComputerUseToolServing`. The result resolves the JS promise; thrown Swift errors
  reject it with the localized message, so model code can catch and branch.
- `nodeRepl.write(string)` appends to a per-execution output buffer. `console.log`
  and friends alias to it (BYO models will use console.log regardless of prompt).
- Per bridge call, the runtime reports `(ComputerUseToolCall,
  Result<ComputerUseToolResult, Error>)` to an events callback owned by the agent:
  activity rows, analytics, and audit bookkeeping happen there, exactly where the
  per-tool-call versions live today.
- Screenshot flow: each `get_app_state` executed inside a script records its
  `ComputerUseAppState`; after the script finishes the agent appends screenshot
  messages in call order, same as the function-calling path.

### Execution model

Decided against the reference (`code-mode-recovery-2026-08-14.md`, "Consequence for
Suniye"). The reference uses Node ESM cells + a synthetic-module bridge + meriyah
AST rewriting to persist bindings across calls; that machinery exists because their
`node_repl` is a general REPL loading untrusted packages. Ours is
computer-use-only, so we take the simple path:

- Each `node_repl` call wraps the model source in an async IIFE:
  `(async () => { <code> })()`. Top-level `await` in the source becomes ordinary
  `await` inside the function — no AST rewrite needed.
- **Top-level bindings do not persist across calls** (they are IIFE-local). This is
  a deliberate divergence from the reference, documented in the prompt. `sky` and
  `nodeRepl` persist because they are injected once on the global object. Rationale:
  the reference persists mainly for its bootstrap (which we pre-inject away), and
  its own workflow already tells the model to re-derive element indexes from the
  latest observation each turn.
- `sky` and `nodeRepl.write` are the only injected capabilities. A bare `JSContext`
  has no filesystem, network, or process access, so the model code is sandboxed by
  construction — none of the reference's seatbelt / network-isolation / trust-hash
  apparatus is needed.
- Promise bridging is the crux: each `sky.*` method returns a JS `Promise` backed by
  a Swift continuation; the runtime kicks off the Swift async work, and pumps the
  JSC microtask queue until the top-level IIFE promise settles.
- A synchronous runaway (`while(true){}`) is bounded by
  `JSContextGroupSetExecutionTimeLimit`. A never-settling promise (e.g. the script
  awaits something that never resolves) is bounded by a wall-clock timeout per
  `node_repl` call (default 30 s, from the reference), which fails the tool call
  with a descriptive error.
- The agent's existing run limits stay: 60 steps, 300 s deadline. One `node_repl`
  call counts as the number of `sky.*` bridge calls it made, so a batch cannot
  smuggle unbounded actions past the step cap.

## Contract and prompt changes

- `ComputerUseToolName` gains `nodeRepl = "node_repl"`. The catalog advertises only
  that tool: one required string parameter `code`.
- **Hard cutover.** The function-calling path is removed, not kept as a fallback
  (the ten-tool contract lives on the parity branch history). The agent handles
  exactly one tool — `node_repl` — plus a final text answer. The ten tool calls
  exist only as `sky.*` bridge targets inside a script, decoded by the shared
  decoder. Agent tests are rewritten for the script shape, not preserved.
- `ComputerUseModelInstructions` is rewritten from the reference
  `computer-use-node-repl.md`, with these deltas:
  - No bootstrap section; `sky` and `nodeRepl` are pre-injected.
  - No screenshot-reading section; screenshots attach automatically after the
    script, and `state.screenshot` is described as opaque.
  - Persistence caveat: declarations do not survive between calls; assign without a
    declaration keyword (`state = ...`) for values needed later (consequence of the
    JSC wrapping strategy).
  - `press_key` documentation upgraded to the recovered X-keysym chord text.
  - Suniye's own rules are kept verbatim: frontmost-app, verification discipline,
    existence-is-not-acted-on, no-substitute-app, spoken-answer style, and the
    content-answer rule.
  - `sky.set_voice_activation({enabled})` documented (Suniye-only method).
- Audit prompt texts (`postActionObservationAudit` etc.) reworded from "call
  get_app_state" to the code-mode equivalent.

## Output handling

- The tool result for a `node_repl` call is the concatenated `nodeRepl.write`
  output, plus a trailing error line when the script threw. Empty output with no
  error returns an explicit "(script produced no output)" marker so the model does
  not mistake silence for failure.
- Output is truncated middle-out through the existing
  `ComputerUseModelToolOutput` token cap (policy value unchanged), matching the
  function-calling path.

## Testing

Unit (`ComputerUseScriptRuntimeTests`):
- write capture and console aliasing; result value of a bare expression is not
  echoed (write-driven output only, reference semantics).
- sky bridge round trip against a stub `ComputerUseToolServing`: argument
  validation errors reject; JS `catch` observes the message; valid calls resolve.
- persistence: bare assignment in call 1 readable in call 2; `let` does not leak
  between calls (documents the wrapping strategy).
- top-level await resolves; a rejected bridge promise fails the script with the
  error in output.
- synchronous runaway hits the execution time limit; never-settling promise hits
  the wall-clock timeout.
- executed-call recording order and observation collection.

Agent (`ComputerUseAgentTests` additions):
- a scripted model emitting `node_repl` calls: multi-action script counts steps per
  bridge call; audit machinery fires (post-action observation audit when a script
  acts without a trailing observe); screenshots attach after the script.
- legacy direct tool call still executes (compatibility path).

Contract tests: catalog advertises exactly one tool; schema round-trips.

E2E: `VoiceActivationEndToEndTests` keeps passing with the scripted agent swapped
to emit a `node_repl` script (proves the voice pipeline is agnostic).

## Sequencing

1. `ComputerUseScriptRuntime` + tests (standalone, no contract changes).
2. Contract + decoder + catalog swap; agent integration + audit rewording; tests.
3. Prompt rewrite.
4. Full suite, preview install, live verification (typed chat first, then voice).

## Decisions on record

- **Sync-runaway handling: in-process, accept the gap** (product decision,
  2026-08-14). The public macOS SDK does not expose
  `JSContextGroupSetExecutionTimeLimit` (private API), so a pure-CPU
  `while(true){}` cannot be interrupted in-process. An async hang (hung native
  call or never-settling promise — the realistic failure) is fully recovered by
  the off-queue watchdog; a sync runaway fails the run and leaks one spinning
  thread until app restart. A killable subprocess runner was considered and
  declined for now; revisit only if sync runaways are observed in practice.

## Deferred, tracked

- Per-app approval elicitation at the bridge (safety layer; mirrors
  `withComputerUsePolicy`).
- App-specific instruction injection on first observation (reference
  `appSpecificInstructions` pattern) — cheap, high-value, separate ticket.
- Error-code taxonomy alignment with the recovered `ServerErrorCode` vocabulary.
