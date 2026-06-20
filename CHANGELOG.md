# Changelog

All notable changes to this project will be documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [2026-06-21] — Session: Gemini extraction + share intake
### Added
- `GeminiService` — Dart port of the event-calendar AI client (model cascade,
  JSON mode @ temperature 0, lenient parse, `GEMINI_BASE_URL` proxy override).
  Config via `--dart-define=GEMINI_API_KEY` / `GEMINI_BASE_URL`.
- `GeocodingService` — free OSM Nominatim forward geocoding for coordinates.
- `PlaceExtractor` — caption/link → Gemini → geocode → `Place`.
- `PlaceStore` (in-memory, `ValueNotifier`) so extracted places show on map/feed.
- "Add a find" sheet now performs real extraction + save (with loading/error UX).
- Android share-sheet intake via `receive_sharing_intent` (SEND text/* filter).
- Web target enabled for quick browser preview (`flutter run -d chrome`).
### Changed
- Map/Feed screens read from `PlaceStore` (live) instead of static mock data.
- README: Gemini config, share intake, and updated next steps.
### Notes
- Verified: `flutter analyze` clean, widget test passes, `flutter build web` ok.

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

