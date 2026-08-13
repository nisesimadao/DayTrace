<p align="center">
  <img src="assets/daytrace-header.svg" alt="DayTrace — Remember your day." width="100%">
</p>

# DayTrace

DayTrace is an iPhone-first memory timeline that passively records the places and movements that help you remember **what happened today**, while keeping the diary itself human-written.

The product is intentionally not a GPS dashboard. Raw observations, automatic inference, and user-confirmed memories are stored separately so reprocessing does not silently overwrite a correction.

## Product principles

- **Diary first.** Location is context, not the destination.
- **User corrections win.** Manual place/time edits survive future timeline rebuilds.
- **Unknown is valid.** Missing evidence becomes a `Gap`; the app does not invent a route.
- **No fake precision.** Uncertain times and places are presented as uncertain.
- **Local first.** The personal beta works without a DayTrace account or backend.
- **Low-power by default.** Visits and significant-location changes form the passive recording backbone; detailed route recording is optional.
- **Recorded local date matters.** Each record is projected into its civil date using the time zone stored with that record rather than assuming the phone's current time zone.

## Current personal beta

- SwiftUI app shell with **Today / History** only
- SwiftData persistence
- Core Location evidence recorder using Visits + significant-change monitoring by default
- Optional detailed route recording
- `Stay / Move / Gap` canonical timeline
- Explicit Gap generation instead of fabricated movement
- Place learning after user confirmation, including nearby same-name Place reuse to reduce GPS-drift duplicates
- Long-press Stay editor for place name and arrival/departure time
- Reversible Stay suppression with undo
- Persistent `UserAssertion` layer that protects manual corrections from re-analysis
- Compact day map linked to timeline selection
- Diary-first empty Today state that does not render an empty world map
- One journal entry per recorded calendar day
- Quick timestamped **Moment Notes**
- Apple Journaling Suggestions picker integration
- History calendar, Recent list, and full past-day detail
- History search across Timeline text, journals, and Moment Notes
- Local JSON backup export
- Human-readable Markdown archive export
- Explicit raw-location GPX export
- Raw-evidence retention policy
- Optional Face ID / Touch ID / device-passcode app lock
- App Switcher privacy cover even when app lock is disabled
- Durable **location-history reset** that removes raw evidence, Timeline, learned Places, and location corrections while preserving Journals and Moment Notes
- A persisted reset cutoff so delayed Core Location callbacks from before a reset cannot silently repopulate deleted history
- One in-app retry path for upgrading When In Use location permission to background recording before falling back to system Settings
- iOS 26 Liquid Glass only for controls, with a non-glass fallback

## Stack

- Swift 6
- SwiftUI
- SwiftData
- Core Location
- MapKit
- LocalAuthentication
- Uniform Type Identifiers / FileDocument export
- Journaling Suggestions
- Minimum deployment target: iOS 18

## Architecture

The core flow is:

```text
Sensor evidence
  ├─ LocationEvidence
  └─ VisitEvidence
        ↓
TimelineEngine
        ↓
TimelineEpisode
  ├─ Stay
  ├─ Move
  └─ Gap
        ↓
UserAssertion (always higher priority)
        ↓
CalendarDay / DayInterval projection
        ↓
Today / History / Search / Journal
```

See [`ARCHITECTURE.md`](ARCHITECTURE.md) and [`DESIGN.md`](DESIGN.md) for the current product rules.

## Build

Open `Daytrace.xcodeproj` in Xcode 26 or newer and select the `Daytrace` scheme. The Journaling Suggestions capability must be valid for the signing team used on device builds.

GitHub Actions performs an unsigned iOS Simulator build and XCTest run on `macos-26`.

## Status

DayTrace is now at a usable personal-beta stage rather than a UI-only prototype. The highest-value remaining work is real-device battery/accuracy testing, safer arbitrary-day Timeline reprocessing before historical Stay editing is enabled, direct-but-truthful boundary editing, stronger learned-place behavior, dedicated regression tests for the newer data semantics, and then richer recall features such as photos / On This Day / optional sync.
