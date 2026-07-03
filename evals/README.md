# Magic Format evals

Run the local Gemma Magic Format eval against the quantized model:

```bash
python3 scripts/eval_magic_format.py
```

The runner starts `llama-server` itself, uses the Gemma-style single user turn, disables reasoning, and sends deterministic generation settings. It requires the local model at:

```text
~/Library/Application Support/Suniye/llm/gemma-4-e2b-Q4_K_M.gguf
```

The default prompt is `evals/prompts/gemma_magic_format_v14.txt`. Earlier prompt files are kept as useful baselines for comparing simple-to-improved prompt behavior. Tuning candidates live in `evals/prompts/candidates/`.

## Version scores (39-case suite, Gemma 4 E2B Q4_K_M, temp 0)

| version | passed | exact | prompt size |
|---------|--------|-------|-------------|
| v1      | 16/39  | 7     | 1.0 KB      |
| v2      | 27/39  | 17    | 2.5 KB      |
| v3      | 31/39  | 22    | 3.2 KB      |
| v4      | 32/39  | 23    | 4.4 KB      |
| v5      | 38/39  | 30    | 5.1 KB      |
| v9      | 38/39  | 31    | 6.6 KB      |
| v11     | 38/39  | 31    | 9.4 KB      |
| v12     | 38/39  | 31    | 8.8 KB      |
| v13     | 38/39  | 30    | 9.2 KB      |
| v14     | 39/39  | 32    | 9.9 KB      |

**Case decontamination (v13):** a review found six prompt examples were verbatim copies of eval cases
(plus two near-copies), so scores through v12 were partly train-on-test. Eight cases (7 in the 39-suite,
1 probe look-alike) were regenerated as same-category paraphrases. On the decontaminated suite v12 drops
to 36/39 — the newly honest misses are two filler cases and a list lead-in. v13 keeps the prompt examples
(they are load-bearing), fixes one that was internally inconsistent (its output invented a word missing
from its input), and strengthens the filler rule with a leading-filler-run example, recovering 38/39 on
the decontaminated suite with referential 24/24 and injection 2/2 intact. Rows v12 and earlier were
measured on the pre-regeneration suite.

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
python3 scripts/eval_magic_format.py --cases evals/magic_format_edit_cases.json --prompt evals/prompts/gemma_magic_format_v14.txt
```

## Advanced capabilities (v11) + trim (v12)

v11 adds three capabilities on top of v9 with no regression (39-suite 38/39, injection 2/2,
referential probe 24/24): spoken formatting commands ("put a hyphen between these" → `1-2-3`),
`new paragraph` + signature blocks, and emoji-from-speech (`"X emoji"` → emoji). One target case —
multi-attempt self-correction collapse — remained unsolved at 2B until v14 (see below). See
`evals/runs/advanced-capabilities-analysis.md` and probe `evals/magic_format_advanced_cases.json`.

**v12** trims v11 by removing the dead multi-attempt-collapse content (rule clause +
two examples for a feature that never passed) and a redundant emoji-mapping tail — ~6% smaller with the
safety-critical gates confirmed stable (injection 2/2 and referential 24/24 across repeated runs).
Attempts to trim further regressed borderline cases (the ordinal-list and paragraph examples proved
load-bearing on the 2B model). Note: 39-suite (37↔38) and the advanced paragraph/emoji cases flap ±1–2
run-to-run on Metal; only the referential probe (24/24) is deterministic, so it is the reliable gate.

**v13** = v12 + the decontamination fixes above: one repaired example plus a sharpened
filler rule ("delete every filler word, including a run of them opening the sentence") with a matching
example. 38/39 held across three consecutive runs on the decontaminated suite; the one steady miss was a
filler case combining mid-sentence "uh" with a doubled word ("the the").

## v14 (current default): 100% on all three gates

A second audit fixed remaining eval-set mistakes: two byte-identical duplicate cases and one
near-duplicate replaced with fresh cases; two advanced expecteds corrected where they contradicted the
prompt's own rules (an emoji case that editorialized the sentence, a signature case that invented a
trailing period); and the bare-hour time convention pinned ("ten a m" -> "10 AM") after the two probe
cases disagreed with each other.

v14 then closed every remaining model gap:

- **Multi-attempt collapse solved** ("get flowers... buy roses... no no wait actually get lilies" ->
  "Get lilies on Monday.") via a last-version-replaces-all-attempts clause plus a structurally matched
  example — the capability previously written off as a 2B ceiling.
- **Filler removal fixed by position, not content**: rule- and example-level fixes failed repeatedly;
  moving the filler directive into the end-of-prompt final check (recency dominates on this model) fixed
  both filler cases at once. Every deletion clause needs a preservation counterweight in the same breath
  ("but every real word stays — never shorten a lead-in"), or lead-ins get truncated.
- **Example-collision bleed-through**: the suite's "these are the items we should have laptop bag phone
  charger" case kept losing its lead-in because the prompt example "the things we need are laptop bag
  phone and charger" shared the exact item set — the model pattern-matched the items and reproduced the
  example's template. Swapping the example's items (helmet/gloves/rope/chalk) fixed it. Prompt examples
  must not share content words with eval cases, not just avoid verbatim copies.

Result: **39/39, 24/24 referential probe, 4/4 advanced, injection 2/2 — five consecutive all-green
rounds** (the previously flappy cases included). Run artifacts: `evals/runs/v14_*.json`.
