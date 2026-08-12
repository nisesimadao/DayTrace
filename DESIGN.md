# Daytrace UX / UI contract

This document is a consistency contract for implementation. New screens should not violate it without an explicit product decision.

## Product sentence

**Open Daytrace to answer “What happened today?” — not to inspect GPS logs.**

## Information hierarchy

1. Day and human-readable timeline
2. Uncertainty / items worth checking
3. Journal and memory cues
4. Map as contextual navigation
5. Diagnostics and raw tracking details

The map is never a primary tab.

## Navigation

- **Today** — the current day's projected timeline and journal.
- **History** — calendar and past days.
- Settings is presented from Today's trailing toolbar.
- Search and history map are secondary History actions, not tabs.

## Timeline grammar

Only three primary episode types exist:

- `Stay` — a period at a place.
- `Move` — time between stays when movement is supported by evidence.
- `Gap` — missing or insufficient evidence.

Transport modes, place categories, privacy state, and confidence are attributes — never new top-level timeline card types.

## Confidence language

- Confirmed/high confidence: filled dot + plain place title.
- Inferred/medium: filled dot + normal title; time may say “around”.
- Low confidence: outlined dot + `?` / “Check this place”.

Never expose numeric confidence scores in normal UI.

## Visual system

- Prefer typography, whitespace, and a single timeline rail over stacked cards.
- Content surfaces use standard system backgrounds.
- Liquid Glass is reserved for controls and transient chrome on iOS 26+.
- No decorative gradients are required for the product to feel complete.
- System colors and Dynamic Type are the default.
- Information must remain understandable without color.

## Motion

- Use `snappy` for selection and lightweight control transitions.
- Map and timeline selection share one identity.
- Haptics should communicate confirmation or a snapped time boundary, not decorate scrolling.
- Avoid large modal transitions for simple edits; prefer direct manipulation or sheets.

## Editing

Normal edits create or update `UserAssertion`; they do not mutate raw evidence.

Rules:

1. User assertions always win over inference.
2. Reprocessing must preserve assertions.
3. Editing a boundary changes adjacent episode geometry so overlap is structurally impossible.
4. “Merge stays” and “Merge places” are different operations.
5. Normal deletion is reversible suppression. Raw-data deletion is a separate privacy action.
6. Every drag interaction must have an accessible form/sheet alternative.

## Journal integrity

User-written prose is never rewritten when timeline inference changes. Timeline context can update beside it, but journal text only changes through an explicit user edit.

## Empty and degraded states

- No location permission: Daytrace remains a journal.
- No location evidence: Today still exposes the journal composer.
- Reduced accuracy: show a quiet status, not an alarming error.
- Missing interval: show `Gap`; do not fabricate a route.
- Stale location: show “last confirmed” rather than “current”.

## Privacy

- Lock-screen notification copy avoids place names by default.
- Private places can be redacted from external surfaces.
- Raw evidence and durable memories have separate retention policies.
- Server sync is not required for core use.
