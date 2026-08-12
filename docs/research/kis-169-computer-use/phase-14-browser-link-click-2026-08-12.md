# Phase 14: browser link primary-click correction

Date: 2026-08-12

## Reported failure

- `[Verified]` Debug session `CU-93344C32D67F` belongs to the final request to verify whether a
  tab or window had opened. It executed one `get_app_state` call and no click call.
- `[Verified]` The preceding session `CU-434CC0F6B888` observed the portfolio, issued an indexed
  click on the `Gita GPT` link, observed no navigation, tried a coordinate click, and still
  observed the portfolio page.
- `[Verified]` Both click calls returned the normal action-completed result even though the next
  observations did not show the requested destination.

## Reference comparison

- `[Verified]` The mounted reference runtime observed the same Helium portfolio page and exposed
  the `Gita GPT` card as an Accessibility link.
- `[Verified]` Its indexed click activated that link. The next observation reported a `Gita GPT`
  window at `gita.kishans.in`.
- `[Verified]` The recovered native architecture supports semantic Accessibility clicks and
  process-scoped synthesized pointer fallback without requiring the controlled app to remain
  frontmost.

## Correction

- `[Verified]` Suniye previously attempted to set `AXSelected` before trying `AXPress` for every
  single indexed primary click.
- `[Implemented]` Suniye now tries `AXPress` first. It uses settable `AXSelected` only when the
  element does not expose press semantics. If neither semantic operation is available, the
  existing process-scoped pointer fallback remains unchanged.
- `[Implemented]` Repeated clicks continue to use repeated `AXPress`; selection remains a
  single-click-only fallback.
- `[Inferred]` The selection-first order could return success without activation for a selectable
  element and matches the reported hover/focus-like symptom. The old run did not log the chosen
  native branch, so it does not prove that this was the branch taken in that historical failure.

## Validation

- `[Verified]` Focused Accessibility-tree and action-service suites execute 21 tests with zero
  failures. A regression test fixes the semantic order as press followed by single-selection
  fallback.
- `[Verified live]` The updated Preview was installed, the prior process was terminated, and a
  fresh installed process ran the natural instruction: `In Helium, click the Gita GPT project
  link on the current portfolio page and verify that it opens.`
- `[Verified live]` Session `CU-73FFF3CFD120` performed `get_app_state`,
  `click(element_index: 79)`, and a fresh `get_app_state`, then reported that the destination
  opened.
- `[Verified live]` An independent reference-runtime observation confirmed that Helium was at
  `gita.kishans.in` after Suniye's click.
- `[Verified]` The full suite executes 1,095 tests with 2 skipped and zero failures. Gated coverage
  is 88.27% (13,458/15,246), above the 80% floor. E2E preflight and smoke pass.

## Scope retained

- `[Retained]` No browser-specific matcher, URL shortcut, deterministic task handling, forced app
  activation, target lock, or special case for this website was added.
- `[Retained]` Model tools, prompt, observation freshness, coordinate conversion, and synthesized
  pointer behavior are unchanged.
