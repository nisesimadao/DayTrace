# Daytrace architecture

## Data layers

```text
Core Location / user import / journaling context
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
              Day projection
                    |
                    v
       Today / History / Journal UI
```

## Truth precedence

1. User assertion
2. High-confidence inferred episode
3. Raw sensor evidence
4. Unknown (`Gap`)

Raw evidence is evidence, not canonical truth. It remains separately persisted so inference algorithms can be upgraded later.

## Time model

- Persist absolute `Date` values.
- Persist the timezone identifier associated with evidence / memory.
- `DayInterval` is a projection, not a stored ownership relationship.
- Overnight stays remain one episode and are clipped only by the UI projection.

## Persistence

SwiftData models:

- `LocationEvidence`
- `VisitEvidence`
- `PlaceRecord`
- `TimelineEpisode`
- `UserAssertion`
- `JournalEntry`
- `MomentNote`

The current MVP is local-only. A future CloudKit configuration can be added to the `ModelContainer`, but sync must not be required to launch or journal.

## Location recorder

Current first pass combines:

- Visit monitoring
- Significant-change monitoring
- Standard location updates with 100m distance filtering and automatic pause

The next pass should make standard updates adaptive: sleep while stationary, increase sampling around departure/arrival, then sleep again. Continuous high-accuracy GPS is intentionally not the default.

## Reprocessing invariant

`TimelineEngine` must never delete an episode protected by an active `UserAssertion`. A production-grade engine will eventually regenerate into a new candidate timeline and reconcile assertions by stable episode/evidence anchors rather than relying only on IDs.

## Journaling Suggestions

The app only receives suggestion details after a person explicitly chooses a suggestion in the system picker. The picker is a memory cue, not a background data source.

## Planned milestones

### M1 — usable personal beta
- robust place naming / learned regions
- direct retiming, rename, suppress, split, merge
- undo
- explicit Gap generation
- current-location freshness
- debug timeline inspector
- physical-device battery tests

### M2 — durable memory
- export JSON / GPX / Markdown
- raw evidence retention cleanup
- app lock / privacy redaction
- iCloud sync opt-in
- backup health

### M3 — richer recall
- photo timeline opt-in
- Moment Notes
- search
- On This Day
- optional adaptive detailed routes
