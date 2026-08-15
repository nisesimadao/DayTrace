# DayTrace 1.0

Publisher: nisesimadao

First stable release of DayTrace, a diary-first location journal for iPhone.

Included: automatic location timeline, tracking diagnostics, Today corrections, historical browsing and editing, Journal and Moment Notes, review reminders, privacy controls, export, On This Day, and Small and Medium Home Screen widgets.

## IPA

The GitHub Release includes an **unsigned IPA** plus its SHA-256 checksum. Re-sign the IPA with your own Apple ID / Apple Developer identity using a sideloading tool before installing it on a stock iPhone. A directly installable signed build is not produced because this repository does not contain Apple distribution certificates or provisioning profiles.

## Highlights

- Replaced the character-style mark with a calm page-and-route symbol across the app icon, in-app wordmark, and README header.
- Movement duration now uses the previous Stay departure and next Stay arrival whenever route evidence confirms movement; a late first GPS sample no longer shortens the displayed trip.
- Joined the live current-location transition into one continuous Timeline and normalized its rail height, row spacing, selection feedback, shared corner radii, and screen gutters.
- Refined Today and History around the diary-first hierarchy; the learned-places map is now a secondary History destination instead of a nested tab.
- Adopted native iOS 26 Liquid Glass for controls and navigation, with system-material fallbacks on iOS 18–25 and Reduce Motion-aware transitions.
- Removed status-area branding so content never collides with Dynamic Island or notch hardware.
- Added vertical swipe navigation to the History calendar month label, alongside explicit previous/next month buttons.
- Added a Debug-only Settings tool that installs or removes deterministic seven-day demo data without touching personal records.
- Hide Journaling Suggestions from Debug builds when the signing entitlement is unavailable while preserving it for Release builds.
- Prefill unresolved Stay names with nearby Apple Maps POI suggestions while keeping them unconfirmed until the user reviews/saves them.
