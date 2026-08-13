# Always-listening: motion and interaction spec

Date: 2026-08-14
Status: Proposed. Companion to `always-listening-ux-plan.md`. Values are for the floating
indicator, the transcript bubble, and the menu bar item. The interactive prototype
(`always-listening-ux-review.html`) implements this spec.

## Frequency analysis

Animation decisions follow usage frequency:

| Event | Frequency | Decision |
|---|---|---|
| Escape / Stop control | High; keyboard-initiated | No animation on the cancellation itself. State swaps immediately. |
| Wake → Listening | Tens of times per day | Short, fast entrance. 200 ms, no flourish. |
| Level meter | Continuous while listening | 1:1 with microphone amplitude, spring-smoothed. Never decorative. |
| Listening → Working morph | Tens of times per day | Single pill morphs in place; no exit-and-reenter. |
| Step status text change | Every few seconds during a run | Cross-fade with slight blur, 200 ms. No movement. |
| Terminal flash (Done, Stopped) | Several times per day | Standard entrance, no bounce. |
| Transcript bubble | Once per turn | Standard entrance from the pill, faster exit. |
| First-enable notice, try-wake flow | Once | May be slower and warmer. |

## Principles applied

- **One pill, morphing.** The indicator is one continuous object that changes contents and
  width, not a sequence of panels. State changes morph the pill in place. This preserves
  spatial continuity and makes interruption natural: a wake hit during the Working state
  re-targets the same element.
- **Interruptible by construction.** All state transitions use CSS transitions (retargetable
  mid-flight), never keyframes, for anything that a wake hit, Escape, or a phase change can
  interrupt. Transitions start from the current on-screen value.
- **Spatial consistency.** The pill lives at the bottom screen edge. It enters rising from
  that edge and exits back down the same path. The transcript bubble is anchored to the pill
  (`transform-origin: bottom center`) and enters and exits toward it.
- **No overshoot.** Nothing here is thrown by the user, so nothing bounces. All motion is
  critically damped (strong ease-out, no bounce). The single exception permitted later:
  drag-repositioning of the pill, which may settle with damping 0.8 because the user's
  momentum caused it.
- **Feedback on press.** Every pressable element in the pill (Stop, Cancel, Continue, Open)
  scales to 0.97 on pointer-down at 100 ms. Commit happens on release.
- **Sound in the same frame.** Cue sounds fire on the same frame as the visual state change
  (causality and harmony). Sounds exist only for wake, end of turn, needs input, your turn,
  and completion (utility).

## Values

Base easing tokens:

```css
--ease-out-strong: cubic-bezier(0.23, 1, 0.32, 1);
--ease-in-out-strong: cubic-bezier(0.77, 0, 0.175, 1);
```

| Transition | Properties | Duration | Easing | Notes |
|---|---|---|---|---|
| Pill enter (wake hit) | opacity 0→1, translateY 8px→0, scale 0.97→1 | 200 ms | ease-out-strong | Never from scale(0). Rises from the screen edge. |
| Pill exit (dismiss, timeout) | opacity→0, translateY→8px | 150 ms | ease-out-strong | Exit faster than enter; same path down. |
| Pill morph between states | width, content cross-fade | 250 ms | ease-in-out-strong | Same element; on-screen movement uses in-out. |
| State content cross-fade | opacity, filter blur(0→2px→0) | 200 ms | ease | Blur masks the two-objects-overlapping artifact. |
| Step status text change | opacity, blur 2px | 200 ms | ease | Text swaps in place; no vertical roll. |
| Transcript bubble enter | opacity, translateY 6px→0, scale 0.96→1 | 250 ms | ease-out-strong | Origin bottom center (anchored to pill). |
| Transcript bubble exit | opacity→0 | 150 ms | ease-out-strong | Faster than enter. |
| Press feedback (any control) | scale→0.97 | 100 ms | ease-out-strong | On pointer-down. |
| Terminal flash enter | content cross-fade in the existing pill | 200 ms | ease-out-strong | No bounce; completion is not user momentum. |
| Level meter bars | height, 1:1 with amplitude | continuous | spring, damping 1.0 | Smoothing only; no invented motion. |
| Working shimmer | background-position | 1.8 s loop | linear | Constant motion uses linear. |
| Menu bar ambient wave | scaleY loop | 1.6 s loop | ease-in-out | Small amplitude; hidden under reduced motion. |

Interaction rules:

- **Escape and Stop have zero exit animation on the run itself.** The pill content swaps to
  Stopped immediately; only the eventual auto-dismiss animates.
- **Barge-in cuts speech on the same frame as the wake cue.** The pill morph to Listening
  follows; audio must not outlive the visual state.
- **Tooltip-style instant follow-ups.** If a second transient state occurs within 500 ms of
  the previous one (for example rejected → ready), the second transition skips its animation.

## Reduced motion and accessibility

Under `prefers-reduced-motion: reduce`:

- Pill enter and exit become opacity-only cross-fades at 150 ms. No translate, no scale.
- The pill morph keeps the width change but drops the blur.
- The level meter remains (it communicates state, not decoration) at reduced amplitude.
- The shimmer becomes a static "Working…" label with an opacity pulse no faster than one
  cycle per 2 s.
- The menu bar wave is replaced by a static filled icon variant.

Press-state scaling is kept in all modes; it is comprehension feedback, not motion
decoration. Hover-dependent styles are gated behind `@media (hover: hover)`.

## Explicit non-goals

- No springs with bounce anywhere in v1. Nothing is user-thrown.
- No entrance animation for menu bar state changes; the menu bar swaps icons instantly.
- No animation on keyboard-initiated actions.
- No parallax, no glow pulses, no idle "breathing" on the pill. The pill's presence is the
  signal; extra motion in an always-visible surface becomes noise within a day.
