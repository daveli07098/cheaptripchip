# Changelog

All notable changes to this project will be documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [2026-09-07] — Session: emoji categories, map sheet, light + dark themes
### Added
- Emoji as the category marker everywhere (pins, chips, cards, boards, detail
  header) with `Semantics` labels on every emoji site (WCAG 1.4.1); new `cafe`
  category.
- `rating`, `reviewCount`, `priceRange`, `photoUrls` on `Place`; extractor
  prompt asks Gemini for them with lenient parsing; card shows
  `4.7 ★ (85) · ¥600–1,400 · Restaurant`.
- Persistent 3-state place-list sheet over the map (`PlaceListSheet`,
  peek/half/full) with pin → row sync and sheet-aware camera padding.
- Grid marker clustering (`marker_clustering.dart`) and `MapPin`/`ClusterPin`
  with 48 dp tap targets and accessible names ("4 places, tap to zoom in").
- Light theme alongside dark: `AppTheme.light`/`dark`, `ThemeController`
  (system → light → dark toggle in the app bar), brightness-aware category
  colours and Positron/Dark Matter tile switching.
- `env/dev.example.json` + `--dart-define-from-file` wiring for local secrets
  (`env/*.json` git-ignored; VS Code launch picks up `env/dev.json`).
- CLAUDE.md: `chrome-devtools` MCP pre-authorised for design references and
  web-preview inspection, with read-only guardrails.
### Fixed
- `home_shell.dart` `catchError` return-type analyzer warning.
### Known issues (from the 2026-09-07 headless UX review)
- CARTO basemap tiles now require an API key — every tile is watermarked.
- Gemini key's Cloud Console API restrictions exclude the Generative Language
  API (`API_KEY_SERVICE_BLOCKED`); extraction returns 403 until fixed.
- Floating "Add a find" button occludes sheet rows, feed cards and the map
  attribution control; sheet drag handle does not drag; light-theme chips
  still use the dark surface colour.
- Boards still reads `MockData`, not `PlaceStore`; favourite/share are no-ops;
  theme choice does not persist across launches.
### Notes
- Verified: `flutter analyze` clean, widget test passes, `flutter build web` ok.

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

