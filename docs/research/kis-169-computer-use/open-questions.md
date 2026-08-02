# KIS-169 open questions

## DMG questions

- What exact model and prompt produce Computer Use actions?
- Which service owns the complete agent loop?
- Which native API captures the target window in each state?
- How does the helper resolve an app name to one window?
- What exact signal means user intervention?
- What cancels an in-flight native action?
- Which actions require approval in the full production policy?
- How does browser control differ in its wire protocol?

## Suniye product questions

- Should the first model run locally, remotely, or through a user-selected provider?
- Does the local-first promise cover screenshots and AX text?
- Should Suniye control one selected app or the whole desktop?
- Which action classes are safe without approval?
- Should persistent approvals exist in the first release?
- Should Suniye support locked-screen operation?
- Should the first release support browser-specific semantics?

## Implementation gates

- Do not choose a screenshot API until a macOS 14 test proves the required output.
- Do not add a helper process until the permission model proves that it is needed.
- Do not connect a model until the typed decision schema and safety policy are fixed.
- Do not enable persistent approval until audit and revocation behavior are specified.

## Phase 0 live validation

- Does `CGWindowListCreateImage` capture the selected window after Screen Recording grant?
- Does AX window geometry match CG window geometry for the target apps?
- Which target apps expose a complete enough AX tree for the first read-only preview?
- Should Phase 1 use a target picker or only the current frontmost application?
