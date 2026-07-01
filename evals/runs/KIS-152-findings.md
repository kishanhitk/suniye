# KIS-152 — Referential self-correction edits: feasibility findings

**Question:** Can Gemma-4-E2B apply long-range *referential* edits ("change the name to Jane")
in-prompt, without misfiring on look-alike content and without regressing the 39-case suite?

**Method:** Built a 24-case probe set (`evals/magic_format_edit_cases.json`): 12 `referential_edit`
(edit should apply) + 12 `edit_lookalike_content` (must stay verbatim). Compared shipped **v5**
against candidate **v6** (v5 + one referential-edit rule + 4 examples distinct from the probe cases).
Ran v6 against the full 39-case suite as a regression guard.

## Results

| metric | v5 (shipped) | v6 (candidate) |
|---|---|---|
| referential_edit recall (pass @0.92) | 6/12 | **7/12** |
| edit_lookalike misfire (pass = no misfire) | 12/12 (0 misfire) | 12/12 (**0 misfire**) |
| 39-case regression | 38/39 | **37/39** |
| injection_resistance (safety) | 2/2 | 2/2 |

## Reading

- **Safety is fine.** 0 misfires on look-alikes in both versions; the guard clauses
  (routed / reported / lead-in stays literal) hold and injection_resistance stays 2/2.
  The risk here is **not** safety.
- **Recall barely moved: 6 → 7 of 12.** v5 already applies *pronoun-adjacent* edits
  ("make it Tuesday", "change it to green") via its existing adjacent-correction rule.
  v6 added exactly **one** descriptive-reference case ("change the recipient to Bob").
  The rest still fail — the model keeps both halves: *"Add three chairs. Wait, change three to five."*
- **The flagship demo case still fails.** `ref_edit_demo_001` applies the *time* edit (8→10)
  but not the *name* edit (Joe→Jane) and drops the "comma / new line" formatting.
  The competitor's headline behavior does not reproduce at 2B.
- **v6 costs a regression.** It broke the say-quote case (`"Ship it"` → literal "Quote ship it").
  Adding 4 examples displaced an existing capability — the documented 2B capacity ceiling
  (see `evals/README.md`: v5's fix "traded away the say-quote case, a capacity limit of the 2B model").

## Verdict

**Prompt-only referential edits are a dead end at Gemma-4-E2B.** Descriptive long-range edits
are applied unreliably (no clean pattern to which ones work), the headline demo doesn't reproduce,
and the rule costs a net regression for ~zero reliable gain. The blocker is **model capacity**, not
prompt wording or safety.

## Recommendation

1. **Do not merge v6** into the shipped prompt — it regresses the 39-suite (38→37) for no reliable recall.
2. **Defer the feature to the selectable-cleanup-model work** (larger user-selected model). Referential
   editing is a capability that a bigger model can plausibly do; gate the feature to capable models
   rather than forcing it on the 2B default.
3. **Keep this probe set as the acceptance gate** — when a larger model is wired in, re-run
   `magic_format_edit_cases.json`; ship the feature only if recall clears a bar (e.g. ≥10/12) while
   misfire stays 0/12.
4. Not recommended: a deterministic regex pre-pass — disambiguating edit-intent from look-alike
   content is exactly what regex fails at, reintroducing the misfire risk the LLM currently avoids.

## Artifacts

- Probe set: `evals/magic_format_edit_cases.json`
- Candidate prompt: `evals/prompts/gemma_magic_format_v6.txt`
- Runs: `evals/runs/v5_probe.json`, `evals/runs/v6_probe.json`, `evals/runs/v6_regression.json`
