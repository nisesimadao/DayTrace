<p align="center">
  <img src="assets/daytrace-header.svg" alt="DayTrace — Remember your day." width="100%">
</p>

# DayTrace

DayTrace is an iPhone-first memory timeline that passively records the places and movements that help you remember **what happened today**, then keeps the diary itself human-written.

The product is intentionally not a GPS dashboard. Raw observations, automatic inference, and user-confirmed memories are stored separately so automatic reprocessing never silently overwrites a correction.

## Product principles

- **Diary first.** Location is context, not the destination.
- **User corrections win.** Manual place/time edits survive future timeline rebuilds.
- **Unknown is valid.** Missing evidence becomes a `Gap`; the app does not invent a route.
- **No fake precision.** Uncertain times and places are presented as uncertain.
- **Local first.** The MVP works without a DayTrace account or backend.
- **Low-power by default.** Visits and significant-location changes form the passive recording backbone; detailed route recording is optional.

## Current MVP

- SwiftUI app shell with **Today / History** only
- SwiftData persistence
- Core Location evidence recorder
- `Stay / Move / Gap` canonical timeline
- Place learning after user confirmation
- Long-press Stay editor for place name and arrival/departure time
- Persistent `UserAssertion` layer that protects manual corrections from re-analysis
- Compact day map linked to timeline selection
- Daily reflection editor
- Apple Journaling Suggestions picker integration
- Tracking-health states and privacy-oriented raw-data retention setting
- iOS 26 Liquid Glass only for controls, with a non-glass fallback

## Stack

- Swift 6
- SwiftUI
- SwiftData
- Core Location
- MapKit
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
Today / History / Journal
```

See [`ARCHITECTURE.md`](ARCHITECTURE.md) and [`DESIGN.md`](DESIGN.md) for the current product rules.

## Build

Open `Daytrace.xcodeproj` in Xcode 26 or newer and select the `Daytrace` scheme. The Journaling Suggestions capability must be valid for the signing team used on device builds.

GitHub Actions also performs an unsigned iOS Simulator build on `macos-26`.

## Status

This repository is an early personal beta. The next high-priority work is direct boundary dragging, reversible suppression/undo, stronger Place resolution, raw-evidence cleanup/export, and real-device battery/accuracy testing.
