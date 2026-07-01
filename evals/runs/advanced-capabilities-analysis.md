# Advanced dictation-enhancement capabilities — gap analysis vs Magic Format v9

Four advanced dictation use cases (beyond current Magic Format scope) were run through Suniye's local
Gemma v9 prompt with clean text (ASR removed) to see what v9 does today.

Probe set: `evals/magic_format_advanced_cases.json`.

## Results (v9 baseline — before any tuning)

| case | target output | Suniye v9 output | status |
|------|---------------|------------------|--------|
| multi_attempt_correction<br>"get flowers…buy roses, no wait actually get lilies" | `Get lilies on Monday.` | `Get flowers on Monday, buy lilies.` | ❌ wrong — edits locally, doesn't collapse the abandoned attempt |
| emoji<br>"…Yosemite, Yosemite **emoji**" | `Let's go to Yosemite! 🏞️` | `And let's go to Yosemite.` | ❌ unsupported — no emoji, kept "And", no "!" |
| spoken_format_command<br>"one two three, **put a hyphen between these**" | `…how smart you are. 1-2-3.` | `…how smart you are. One, two, three. Put a hyphen between these.` | ❌ unsupported — kept command literal, no digitization |
| paragraphs_signature<br>"…new paragraph, Best, comma, new line, Jane" | full note + `Best,`/`Jane.` | `Hi Jane,\n\n…additions.` (signature dropped) | ⚠️ partial — first "new paragraph" ok, signature block lost |

## The four capability gaps

1. **Emoji from speech** — `"<word> emoji"` → a fitting emoji. v9 has no emoji concept. Standalone feature.
2. **Spoken formatting commands applied to prior content** — "put a hyphen between these",
   number-words → `1-2-3`. **Directly tensions v9's injection resistance**: v9 was hardened to keep
   in-transcript commands literal, so it (correctly, by its own rules) preserved "put a hyphen between
   these." Supporting this means re-drawing the apply-vs-keep-literal boundary — the same tension that
   made the referential-edit work delicate. Highest regression risk.
3. **Multi-attempt self-correction collapse** — "flowers … roses … actually lilies" → just "lilies".
   v9 does adjacent + referential edits but edits the last token locally instead of recognizing the
   whole run as one item being re-decided. Natural extension of the referential work.
4. **"new paragraph" + signature blocks** — v9 knows "new line" and handled one "new paragraph", but
   dropped the trailing `Best, / Jane` signature. Needs robust multi-block letter structure and a fix
   for the tail-truncation.

## Plan

Tune a v10 that adds these while protecting the three existing gates:
39-case suite (currently 38/39, injection 2/2), the 24-case referential probe (12/12, 0 misfire),
and this 4-case advanced probe. Expect #2 to be the hardest (injection tradeoff) and to need
the sharpest own-content-vs-embedded-command boundary.
