# Computer Use task evals

Scored end-to-end evals: real agent, real model, real machine. Task prompts enter
as text at the post-ASR handoff (disfluencies included, since that is what
production tasks look like); success is a per-task verifier — a shell probe of
machine state or a regex over the spoken answer. Results are a **rate**, tracked
across changes, never a CI gate: the model is stochastic.

The eval logic lives in `ComputerUseEvalEngine` and is shared by both lanes.

## Host lane — quick checks and hardware truths

Runs on your Mac. Keep it small: hardware-dependent tasks (battery health, some
System Settings panes that do not exist in a VM) live here.

```
scripts/run_computer_use_evals.sh            # runs the existing test-host binary
scripts/run_computer_use_evals.sh --rebuild  # rebuild first, then re-grant TCC
```

The ad-hoc-signed XCTest host loses its Accessibility / Screen Recording grants on
every rebuild (the signature changes), so the default avoids rebuilding. After a
`--rebuild`, re-grant both to `.derivedData/Build/Products/Debug/Suniye.app` before
the next sweep. Tasks: `tasks.json`.

## VM lane — bulk, aggressive, unattended

Runs inside a disposable macOS guest (Tart / Virtualization.framework), so tasks
can be mutating, destructive, and multi-app — `tasks-vm.json` has its own set.
Every trial starts from the identical golden state; no cross-trial pollution.

```
scripts/setup_cu_eval_vm.sh                  # one-time: build the golden image
SUNIYE_CU_EVAL_API_KEY=sk-... \
  scripts/run_computer_use_evals_vm.sh       # clone -> run -> pull results -> destroy
```

The runner is a standalone app (`SuniyeEvalRunner`, bundle id
`dev.suniye.evalrunner`) linking the same agent stack without the dictation/audio
machinery, so the guest needs no Xcode. TCC is pre-granted by bundle id in the
golden image, so re-signed runner builds keep their permissions.

## Environment

| Variable | Default | Meaning |
| --- | --- | --- |
| `SUNIYE_CU_EVAL_MODEL` | `openai/gpt-5.6-luna` | model id |
| `SUNIYE_CU_EVAL_ENDPOINT` | OpenRouter | chat-completions URL |
| `SUNIYE_CU_EVAL_API_KEY` | app keychain (host only) | model key; required in the VM |
| `SUNIYE_CU_EVAL_TASKS` | `tasks.json` / `tasks-vm.json` | task file |

Results: `evals/runs/cu_eval_<stamp>.json`.
