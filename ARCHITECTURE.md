# Daytrace architecture

## Data layers

```text
Core Location / journaling context / direct user input
                    |
                    v
             Sensor Evidence
                    |
                    v
              TimelineEngine
                    |
                    v
         Stay / Move / Gap episodes
                    |
             + UserAssertion
                    |
                    v
            Canonical Timeline
                    |
                    v
       CalendarDay / DayInterval projection
                    |
                    v
 Today / History / Search / Journal / Export
```

## Truth precedence

1. User assertion
2. High-confidence inferred episode
3. Raw sensor evidence
4. Unknown (`Gap`)

Raw evidence is evidence, not canonical truth. It remains separately persisted so inference algorithms can improve later without redefining what the user explicitly corrected.

## Time model

- Persist absolute `Date` values.
- Persist the timezone identifier associated with evidence / memory.
- `CalendarDay` represents a recorded civil day (`year/month/day/time-zone`) rather than the phone's current calendar day.
- `DayInterval` is a projection, not a stored ownership relationship.
- Overnight stays remain one episode and are clipped only by day projection.
- History, search grouping, journal uniqueness, Markdown export, and past-day detail use the recorded day/time-zone semantics.

## Persistence

SwiftData models:

- `LocationEvidence`
- `VisitEvidence`
- `PlaceRecord`
- `TimelineEpisode`
- `UserAssertion`
- `JournalEntry`
- `MomentNote`

The current beta is local-only. A future CloudKit configuration can be added to the `ModelContainer`, but sync must never be required to launch, record, review, or journal.

## Location recorder

Current behavior uses:

- Visit monitoring as the durable stay signal
- Significant-change monitoring as the passive movement signal
- A one-shot foreground location snapshot when the app opens
- Continuous standard location updates only when **Detailed routes** is explicitly enabled
- A raw-evidence retention policy, with Visit retention based on the visit's actual departure/arrival time rather than delayed callback delivery time

Detailed updates should eventually become adaptive: wake around likely departure/arrival, sample while useful, then sleep again. Continuous high-accuracy GPS is intentionally not the default.

## Timeline inference

`TimelineEngine` currently rebuilds the recent window and maintains three primary episode kinds:

- `Stay` — supported by Visit evidence and optionally resolved to a learned Place
- `Move` — a transition interval with retained location samples
- `Gap` — a transition interval without enough evidence; no route is fabricated

Place resolution rejects very inaccurate Visits and can reuse a nearby existing user-confirmed Place with the same name to avoid duplicate learned places caused by GPS drift.

### Reprocessing invariant

`TimelineEngine` must never delete or overwrite an episode protected by an active `UserAssertion` in a way that discards the user's correction.

The current rebuild window is intentionally recent. Historical Timeline detail is therefore read-only: editing an old Stay before arbitrary-day transition regeneration exists could leave old `Move` / `Gap` geometry stale. Historical editing should only be unlocked after the engine can rebuild a selected day/range safely.

## Editing model

Normal edits affect canonical memory, not raw evidence:

- Rename / arrival / departure corrections create or update `UserAssertion` records.
- Stay suppression is reversible and represented as an assertion.
- Confirmation can learn a reusable Place.
- Overlapping Stay edits are rejected structurally.
- Raw evidence remains separate from the user's corrected Timeline.

Direct boundary dragging is still deferred because the current Timeline row height is not proportional to elapsed time. A drag gesture must not imply a false pixel-to-time scale.

## Journaling

A recorded calendar day has at most one `JournalEntry`. Saving reconciles accidental duplicates and preserves user-written prose independently from Timeline reprocessing.

`MomentNote` is a separate timestamped memory cue for quick in-the-moment notes. It is shown with recorded local time, included in search/export, and never merged into diary prose automatically.

### Journaling Suggestions

The app only receives suggestion details after a person explicitly chooses a suggestion in the system picker. The picker is a memory cue, not a background data source. The integration is gated with `canImport(JournalingSuggestions)` so the core journal remains usable in environments without the module.

## History and recall

History has three entry paths into a recorded day:

- Calendar day
- Recent day row
- Search result

Past-day detail reuses the day map and Timeline presentation, shows Moment Notes, and allows journal editing. Old Timeline editing remains disabled for the rebuild-window reason described above.

History search currently matches visible Timeline title/subtitle text, Journal text, and Moment Notes. Results are grouped once by recorded `CalendarDay` and capped for UI rendering rather than rescanning the entire history per result row.

## Export

All export generation is local.

- **JSON**: Timeline, Places, Journal entries, Moment Notes, and UserAssertions. Raw location samples are excluded.
- **Markdown**: human-readable day archive using recorded day/time-zone projection.
- **GPX**: retained raw `LocationEvidence` only, explicitly chosen by the user. Gaps longer than ten minutes start a new track segment so missing evidence is not rendered as a fake continuous route.

SwiftUI `fileExporter` / `FileDocument` hands the generated file to the system save UI.

## Privacy

- Optional app lock uses `LocalAuthentication` owner authentication (biometrics with system passcode fallback as available).
- App content is covered whenever the scene is inactive/background so App Switcher snapshots do not expose location history or journal text.
- Raw evidence has a separate retention policy from durable Timeline / journal memory.
- Core use requires no backend.

Explicit destructive deletion controls are still being finalized. The UI must not claim that raw-only deletion preserves canonical Timeline unless the engine can guarantee that detached recent Stay episodes will survive future rebuilds without duplicate re-delivery.

## Current milestones

### Implemented personal-beta foundation

- passive location evidence recording
- Stay / Move / Gap inference
- user-protected rename / retime / confirmation
- reversible suppression + undo
- current-location freshness states
- recorded-time-zone day projection
- one Journal per CalendarDay
- Place learning and nearby duplicate reuse
- Moment Notes
- History search
- historical day detail
- JSON / Markdown / GPX export
- raw evidence retention cleanup
- app lock + App Switcher privacy cover
- diary-first empty Today state
- CI build + XCTest on iOS Simulator

### Next: harden the beta

- physical-device battery / accuracy tests
- explicit privacy deletion controls
- safer arbitrary-day Timeline regeneration
- historical Stay editing after that regeneration work
- dedicated regression tests for timezone/DST, delayed Visits, Place reuse, Journal uniqueness, and deletion semantics
- direct boundary editing only with a truthful time interaction model
- adaptive detailed-route recording
- debug / support diagnostics where useful

### Later: richer recall

- photo timeline opt-in
- On This Day
- backup-health UX
- optional iCloud sync
- richer learned-place management / merge UI
