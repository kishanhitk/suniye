# Magic Format evals

Run the local Gemma Magic Format eval against the quantized model:

```bash
python3 scripts/eval_magic_format.py
```

The runner starts `llama-server` itself, uses the Gemma-style single user turn, disables reasoning, and sends deterministic generation settings. It requires the local model at:

```text
~/Library/Application Support/Suniye/llm/gemma-4-e2b-Q4_K_M.gguf
```

The default prompt is `evals/prompts/gemma_magic_format_v11.txt`. Earlier prompt files are kept as useful baselines for comparing simple-to-improved prompt behavior. Tuning candidates live in `evals/prompts/candidates/`.

## Version scores (39-case suite, Gemma 4 E2B Q4_K_M, temp 0)

| version | passed | exact | prompt size |
|---------|--------|-------|-------------|
| v1      | 16/39  | 7     | 1.0 KB      |
| v2      | 27/39  | 17    | 2.5 KB      |
| v3      | 31/39  | 22    | 3.2 KB      |
| v4      | 32/39  | 23    | 4.4 KB      |
| v5      | 38/39  | 30    | 5.1 KB      |
| v9      | 38/39  | 31    | 6.6 KB      |
| v11     | 38/39  | 31    | 8.1 KB      |

Notable: v4 scored 0/2 on injection resistance (its list-request examples taught the model to obey transcript-embedded commands); v5 restored it to 2/2. v5's only failure is an ambiguous ordinal parse ("…out of these first books pen notebook"); fixing it traded away the say-quote case, a capacity limit of the 2B model.

## Referential self-correction (KIS-152)

v9 adds long-range referential edits ("Hi Joe … actually change the name to Jane" → "Hi Jane") while
matching v5 on the 39-case suite (v9 fixes the ordinal-list case but trades one filler case — net 38/39,
injection resistance still 2/2). Measured on a dedicated 24-case probe set
(`evals/magic_format_edit_cases.json`: 12 apply + 12 must-stay-literal look-alikes):

| prompt | referential recall | look-alike misfire | 39-suite | injection |
|--------|--------------------|--------------------|----------|-----------|
| v5     | 6/12               | 0/12               | 38/39    | 2/2       |
| v6     | 7/12               | 0/12               | 37/39    | 2/2       |
| v7     | 10/12              | 1/12               | 33/39    | 1/2 (broke) |
| v8     | 10/12              | 0/12               | 38/39    | 2/2       |
| v9     | **12/12**          | **0/12**           | **38/39**| **2/2**   |

Tuning arc: v6 (buried rule) barely moved recall. v7 (procedural "apply corrections first") hit 10/12
recall but generalized into obeying embedded commands — injection dropped to 1/2 and a reported-speech
look-alike misfired. v8 sharply separated "apply the speaker's own draft edit" from "obey commands /
reported speech" via dedicated counter-examples, recovering all safety at 10/12. v9 added a
described-target→draft-item mapping rule (the *name* is the person's name, the *place* is the location…)
plus greeting-name and location examples, landing the last two cases (the two-edit demo and an
unlabeled field reference) for full 12/12 with zero regressions. See `evals/runs/KIS-152-findings.md`.

Run the probe set with:

```bash
python3 scripts/eval_magic_format.py --cases evals/magic_format_edit_cases.json --prompt evals/prompts/gemma_magic_format_v11.txt
```

## Advanced capabilities (v11)

v11 adds three capabilities on top of v9 with no regression (39-suite 38/39, injection 2/2,
referential probe 24/24): spoken formatting commands ("put a hyphen between these" → `1-2-3`),
`new paragraph` + signature blocks, and emoji-from-speech (`"X emoji"` → emoji). One target case —
multi-attempt self-correction collapse — remains unsolved at 2B. See
`evals/runs/advanced-capabilities-analysis.md` and probe `evals/magic_format_advanced_cases.json`.
