# Changelog

All notable changes to this project will be documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [2026-06-21] — Session: Flutter app draft
### Added
- Flutter app scaffold (iOS + Android) with a map-first dark theme.
- Core screens: Explore (map), Saved (feed), Boards, and a Place detail sheet.
- `flutter_map` + CartoDB dark tiles ($0 OSM maps), coral category pins, filter chips.
- Mock Tokyo seed data; "Add a find" link-intake sheet (stub, no backend yet).
- `README.md` documenting the draft, how to run, and next steps.
### Changed
- `ANALYSIS.md`: recorded the Flutter decision and added a UI/Design References section
  (Yaay interaction model + oyado JP concierge aesthetic).
- Android manifest: INTERNET permission + https VIEW query for map tiles and deep links.

