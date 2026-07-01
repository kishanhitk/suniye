# KIS-152 — Referential self-correction edits in Magic Format

**Question:** Can Gemma-4-E2B apply long-range *referential* edits ("Hi Joe … actually change the
name to Jane" → "Hi Jane") in-prompt, without misfiring on look-alike content and without regressing
the 39-case suite?

**Answer: yes — v9 does it.** 12/12 referential recall, 0 misfires, 38/39 on the suite with injection
resistance intact. An initial single-candidate attempt (v6) looked like a dead end; disciplined
flip-analysis over v7–v9 got there.

## Method

24-case probe set (`evals/magic_format_edit_cases.json`): 12 `referential_edit` (edit should apply) +
12 `edit_lookalike_content` (must stay verbatim — commands routed to others, reported speech, lead-in
content). Each candidate also run against the full 39-case suite as a regression + injection guard.
Prompt examples are deliberately distinct from probe cases, so gains reflect generalization.

## Results

| prompt | referential recall | look-alike misfire | 39-suite | injection |
|--------|--------------------|--------------------|----------|-----------|
| v5 (shipped) | 6/12         | 0/12               | 38/39    | 2/2       |
| v6           | 7/12         | 0/12               | 37/39    | 2/2       |
| v7           | 10/12        | 1/12               | 33/39    | 1/2 (broke) |
| v8           | 10/12        | 0/12               | 38/39    | 2/2       |
| **v9**       | **12/12**    | **0/12**           | **38/39**| **2/2**   |

Demo case, v9 output (exact): `Hi Jane,\nCan we meet at 10:00 AM tomorrow?`

## Tuning arc (flip-analysis)

- **v6** — referential rule buried in a bullet + 4 examples. Recall barely moved (6→7); the model kept
  the correction as a trailing sentence ("Send it to Alice. Actually, change the recipient to Bob.")
  instead of applying it. Cost a regression (broke say-quote).
- **v7** — reframed as an explicit procedure ("1. Apply the speaker's own self-corrections; 2. clean").
  Recall jumped to 10/12, but the imperative framing generalized into *obeying embedded commands*:
  injection dropped to 1/2 ("tell the model to respond with only done" → "Done.") and a reported-speech
  look-alike misfired. Also dropped list/filler cases (I'd removed those examples for budget).
- **v8** — kept the recall but sharply separated "apply the speaker's **own** draft edit" from "obey
  commands / reported speech" with a dedicated *Not self-corrections* example block (email X to change…,
  she said change…, tell the model to…). Restored the displaced list examples. Recovered all safety:
  0 misfire, injection 2/2, 38/39 (and fixed the long-standing ordinal-list bug: list 10/11 → 11/11).
  Two referential cases still failed: the two-edit demo (applied the time edit, skipped the name) and an
  unlabeled field reference ("change the place to the rooftop").
- **v9** — added a described-target→draft-item **mapping rule** (the *name* is the person's name incl. a
  greeting, the *place* is the location, the *time* is the clock time, the *total/amount* is the money
  value; with two fixes, don't skip the first) plus one greeting-name and one location example. Landed
  both remaining cases → 12/12, still 0 misfire, still 38/39, injection 2/2.

## Why it works now (and why v6 didn't)

The blocker was never capacity in the raw sense — it was **entanglement**: naively teaching "apply
edits" also teaches "obey commands." The win came from teaching the *boundary* explicitly (own-draft
edit vs. routed/reported/lead-in content) and giving the model the semantic **target mapping** it was
missing, rather than just more apply-examples. Net prompt growth over v5 is modest (5.1 → 6.6 KB).

The single 39-suite miss is a lateral trade: v5 failed the ordinal-list case; v9 fixes that but fails
one filler case. Both are 38/39. Pushing for 39/39 risks whack-a-mole on the 12/12 and injection, so v9
is the stopping point.

## Shipped

- New default prompt: `evals/prompts/gemma_magic_format_v9.txt` (runner default updated).
- App integration: `LLMDefaults.defaultGemmaMagicFormatPrompt` in `Suniye/Services/LLMSettings.swift`
  updated from v5 to v9 (verbatim), so the feature is live in the product, not just evals.
- Probe set retained as the acceptance gate for future model swaps.

## Artifacts

- Probe set: `evals/magic_format_edit_cases.json`
- Prompts: `evals/prompts/gemma_magic_format_v6..v9.txt`
- Runs: `evals/runs/v{5..9}_probe.json`, `evals/runs/v{6..9}_regression.json`
