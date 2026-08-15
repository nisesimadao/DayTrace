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
- Persist the timezone identifier associated with each evidence / memory record.
- `CalendarDay` is a timezone-neutral civil-date key containing only `year/month/day`.
- A record becomes a `CalendarDay` by interpreting its absolute `Date` in **that record's stored timezone** and extracting the resulting year/month/day.
- This keeps History grouped by the local date on which something was experienced without binding the date key itself to whichever timezone the phone uses later.
- `DayInterval` is the timezone-specific projection used when an actual start/end `Date` range is required.
- Overnight stays remain one episode and are clipped only by day projection.
- History, search grouping, journal uniqueness, Markdown export, and past-day detail use these recorded-local-date semantics.
- When creating a new Journal for a historical civil day, recorded Timeline timezone context is preferred; if there is no Timeline context, a Moment Note recorded on that civil day can provide the timezone before falling back to the caller/device timezone.

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
- A remembered one-time in-app attempt to upgrade When In Use authorization to background recording before Settings becomes the recovery path

Detailed updates should eventually become adaptive: wake around likely departure/arrival, sample while useful, then sleep again. Continuous high-accuracy GPS is intentionally not the default.

### Location-history reset cutoff

Location-history reset stores a cutoff timestamp. The production Core Location ingestion path and regression tests share the same cutoff policy:

- location samples older than the cutoff are rejected
- samples at/after the cutoff are accepted normally
- a Visit that ended at/before the cutoff is discarded
- a Visit spanning the cutoff is accepted with its arrival clamped to the cutoff
- an ongoing Visit that began before the cutoff can likewise restart at the cutoff

This prevents a delayed Core Location callback from silently recreating history the user explicitly deleted.

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
- DayTrace can use Apple Maps nearby POI lookup to prefill an unresolved Stay name, and a user can explicitly ask for a place/address suggestion in the Stay editor; both are only candidates and are not treated as confirmed learned Places until the user saves/affirms them.
- Overlapping Stay edits are rejected structurally.
- Raw evidence remains separate from the user's corrected Timeline.

Direct boundary dragging is still deferred because the current Timeline row height is not proportional to elapsed time. A drag gesture must not imply a false pixel-to-time scale.

## Journaling

A recorded calendar day has at most one `JournalEntry`. Saving reconciles accidental duplicates and preserves user-written prose independently from Timeline reprocessing.

`MomentNote` is a separate timestamped memory cue for quick in-the-moment notes. It is shown with recorded local time, included in search/export, and never merged into diary prose automatically.

### Journaling Suggestions

The app only receives suggestion details after a person explicitly chooses a suggestion in the system picker. The picker is a memory cue, not a background data source. The integration is gated with `canImport(JournalingSuggestions)` so the core journal remains usable in environments without the module.

## Evening review reminders

Review reminders are local `UserNotifications`; there is no push backend.

- They are opt-in from Settings, which is also where notification permission is requested.
- Default review time is 21:00 and can be changed.
- Notification title/body contain no visited place names or raw coordinates.
- The app schedules a rolling set of day-specific one-shot requests instead of one repeating request so individual Journal days can be skipped or cancelled.
- Existing Journal days are excluded during refresh.
- Saving/updating a Journal cancels that civil day's pending reminder immediately.
- Deleting a Journal causes the managed reminder schedule to refresh.
- Tapping a DayTrace review notification routes the app to Today, including when the app was backgrounded while History was selected.
- Only DayTrace-managed reminder identifiers are removed when refreshing/disabling the feature.

## History and recall

History remains one app tab but has two shallow modes: **日付** and **マップ**.

Date mode has three entry paths into a recorded day:

- Calendar day
- Recent day row
- Search result

Past-day detail reuses the day map and Timeline presentation, shows Moment Notes, and allows journal editing. Old Timeline editing remains disabled for the rebuild-window reason described above.

History search currently matches visible Timeline title/subtitle text, Journal text, and Moment Notes. Results are grouped once by recorded `CalendarDay` and capped for UI rendering rather than rescanning the entire history per result row.

### Personal Places map

Map mode is a **learned-Place recall surface**, not a raw location map:

- it renders `PlaceRecord` identities that have visible linked Stay episodes
- raw `LocationEvidence` is never rendered as map dots
- nearby unconfirmed Stays are never merged merely because coordinates are close
- visible Stays are grouped once by `placeID` to derive per-Place visit count and most-recent visit
- most-recent date is stored/displayed as the Stay's recorded-local `CalendarDay`, not reformatted through the phone's later current timezone
- map pin and Place-row selection share one selected Place and camera focus state
- `isPrivate` Place names are sanitized on this recall surface
- the selected Place card can open **最後の記録**, reusing the same `HistoricalDayDetailView` used by calendar/search History rather than maintaining a second historical-detail implementation

Truthful city/zoom aggregation is deferred until real usage produces enough learned Places to justify it. Future aggregation must preserve underlying Place identity and must not treat spatial proximity as proof that two Places are the same.

## Export

All export generation is local.

- **JSON**: Timeline, Places, Journal entries, Moment Notes, and UserAssertions. Raw location samples are excluded.
- **Markdown**: human-readable day archive using recorded-local-date projection.
- **GPX**: retained raw `LocationEvidence` only, explicitly chosen by the user. Gaps longer than ten minutes start a new track segment so missing evidence is not rendered as a fake continuous route.

SwiftUI `fileExporter` / `FileDocument` hands the generated file to the system save UI.

## Privacy

- Optional app lock uses `LocalAuthentication` owner authentication (biometrics with system passcode fallback as available).
- App content is covered whenever the scene is inactive/background so App Switcher snapshots do not expose location history or journal text.
- Raw evidence has a separate retention policy from durable Timeline / journal memory.
- Core use requires no backend.
- **Location-history reset** deletes `LocationEvidence`, `VisitEvidence`, `TimelineEpisode`, `UserAssertion`, and `PlaceRecord`, while deliberately preserving `JournalEntry` and `MomentNote`.
- The reset time is persisted as a cutoff. Delayed location samples older than that cutoff are discarded instead of silently repopulating deleted history.
- A Visit that ended before the cutoff is discarded; a Visit spanning the reset can restart at the cutoff so only post-reset history returns.
- Review notification copy is deliberately location-free so a lock-screen notification does not reveal a school, home, shop, or route.
- Raw-only manual deletion is intentionally not exposed yet because deleting raw Visit anchors alone can change survival/re-delivery semantics for recent canonical Stays.

## Regression strategy

The XCTest suite now includes focused coverage for newer semantics rather than only happy-path UI/domain behavior, including:

- civil-day projection across timezone changes and DST boundaries
- delayed Visit retention behavior
- nearby same-name Place reuse versus distant same-name separation
- one-Journal-per-CalendarDay duplicate reconciliation
- historical MomentNote-only Journal timezone anchoring
- location-history reset preserving Journals/Moment Notes and persisting its cutoff
- rejection of pre-cutoff delayed location samples
- clamping of Visits that span the reset cutoff

The cutoff tests exercise the same pure policy used by production Core Location ingestion rather than exposing private delegate internals just for testing.

## Current milestones

### Implemented personal-beta foundation

- passive location evidence recording
- Stay / Move / Gap inference
- user-protected rename / retime / confirmation
- user-invoked Apple Maps candidate lookup for Stay naming
- reversible suppression + undo
- current-location freshness states
- recorded-timezone civil-day projection
- one Journal per CalendarDay
- Place learning and nearby duplicate reuse
- Moment Notes
- History search
- historical day detail
- personal learned-Places map with latest-record navigation
- JSON / Markdown / GPX export
- raw evidence retention cleanup
- app lock + App Switcher privacy cover
- durable location-history reset with delayed-callback cutoff
- improved When In Use → background-recording recovery flow
- diary-first empty Today state
- Timeline selection ↔ map camera/pin synchronization
- privacy-safe configurable evening review reminders
- focused regression coverage for newer data semantics
- CI build + XCTest on iOS Simulator

### Next: harden the beta

- physical-device battery / accuracy tests
- real-device notification permission/delivery/timezone checks
- safer arbitrary-day Timeline regeneration
- historical Stay editing after that regeneration work
- direct boundary editing only with a truthful time interaction model
- adaptive detailed-route recording
- debug / support diagnostics where useful

### Later: richer recall

- photo timeline opt-in
- On This Day
- backup-health UX
- optional iCloud sync
- richer learned-place management / merge UI
