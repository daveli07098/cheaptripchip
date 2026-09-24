# Changelog

All notable changes to this project will be documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Trip sharing (`TripShare`): `cheaptripchip://import` app links, a portable
  `.cheaptrip.json` file, KML for Google My Maps, and Google Maps
  place/route URLs.
- Export sheet (`ExportSheet`) from a share button on every board card and a
  "Share all saved" action on the Saved tab: Share link (text includes a
  Google Maps route fallback; disabled with a hint when the link would be too
  long), Share file, Export to Google My Maps (.kml + import hint), Open route
  in Google Maps (first 11 stops).
- Import: incoming app links (`app_links`), shared text containing a link and
  shared `.cheaptrip.json` files open a preview sheet (`ImportSheet`) before
  the Gemini path; "Import from link" on the Boards tab (paste dialog, also
  works on web). `ImportService.importBundle` saves new places, reuses saved
  ones (same name case-insensitively within 50 m), and creates a 📥 board with
  one "Shared" section; the app then switches to Boards and reports counts.
- Platform config: Android VIEW filter for `cheaptripchip://import` and a SEND
  filter for `application/json`; iOS `CFBundleURLTypes` for the scheme; Flutter
  built-in deep linking turned off on both (app_links handles links).
  `docs/firebase-setup.md` step 7 now adds Google Sign-In's reversed client id
  as a second entry in the existing `CFBundleURLTypes` array.
- Tests: import/dedupe service and export sheet options (51 total).
### Changed
- `BoardStore.createBoard` takes optional `sections`, so a pre-filled board is
  written in one upsert (a loop of `addPlaceToBoard` can race the repository
  echo).
- firebase_core_web 3.11.0 → 3.12.0 (lockfile only): 3.11.0 doesn't compile
  for web under Flutter 3.41.7 (`isA` on `Object`) — pre-existing, unrelated
  to this feature.
### Notes
- Not verified: on-device deep links (Android/iOS cold and warm start), sharing
  a `.cheaptrip.json` file into the app, and the native share sheets. Verified
  by unit/widget tests and `flutter build web`.

## [2026-09-14] — Session: multi-user accounts (Google sign-in + Firestore)
### Added
- Firebase Auth with the Google provider (`AuthService`: web popup, mobile via
  google_sign_in 7) and Cloud Firestore per-user storage under
  `users/{uid}/places` and `users/{uid}/boards` (`FirestorePlaceRepository`,
  `FirestoreBoardRepository`), behind `PlaceRepository`/`BoardRepository`
  interfaces so the backend can be swapped in one file.
- Guest mode: with no Firebase project configured the app runs exactly as
  before on local, mock-seeded repositories; `lib/firebase_options.dart` is a
  stub that `flutterfire configure` overwrites.
- `BoardStore` (create board, add place to board/section) and a working
  "Add to board" picker with "New board…"; Boards reads the store.
- Account button (map chip row + Saved/Boards app bars) and account sheet
  with not-configured / signed-out / signed-in states; favourite/board writes
  go through the repositories.
- `Place`/`Board`/`BoardSection` JSON (de)serialization with lenient parsing.
- `firestore.rules` (owner-only), `firebase.json`, `docs/firebase-setup.md`
  (11-step console + CLI checklist), iOS deployment target 15.0.
- Tests: JSON round-trips, store behaviour with injected repositories (16 total).
### Changed
- Empty states distinguish "no finds yet" from an empty category filter or
  search with no matches.
### Notes
- Deliberate: guest data is not uploaded on sign-in; signing in switches to
  the Firestore-backed stores.
- Verified in the headless web preview: guest mode, account sheet (unconfigured
  state), board picker and new-board flow. Not verified: real Google sign-in,
  Firestore sync, rules — they need the Firebase project from the setup doc.
- Gemini key remains client-side; a Cloud Functions proxy (Blaze plan) is next.

## [2026-09-07] — Session: UX review fixes
### Changed
- Map tiles: OpenStreetMap by default via `MAP_TILE_URL` compile-time define
  (CARTO now requires a key); dark theme uses flutter_map's dark tile filter.
  OSM's tile policy is for development/light use — set `MAP_TILE_URL` to a
  keyed provider before release.
- "Add a find" moved into the map sheet header; the floating button now shows
  only on Saved/Boards, whose lists gained bottom padding so it covers nothing.
- Place-list sheet is one `CustomScrollView`, so the drag handle and header
  drag the sheet; peek raised 0.18 → 0.22 for the taller header.
- Light theme: unselected category chips use the theme surface/outline colours.
- Map attribution follows the sheet's top edge and stays visible.
- Selected map pin: 1.25× with an on-surface ring, `selected` semantics.
- Initial camera fits every place (was a hardcoded centre/zoom that clipped
  the easternmost pin).
- Theme toggle also available in the map's chip row (`ThemeToggleButton`).
- Feed card badge reads "Pinned" with a tooltip instead of "1 match".
- Extraction errors: 403 / blocked-API responses map to an actionable message.
### Added
- Theme mode persists via `shared_preferences` (loaded before first frame).
- Favourite toggle (`Place.isFavorite`, `PlaceStore.toggleFavorite`) and Share
  via `share_plus` in the place detail sheet, with accessible names.
- Boards reads the live `PlaceStore`; unsorted places appear in an automatic
  "New finds" board grouped by category (`newFindsBoard`, unit-tested).
### Notes
- Re-verified in a headless phone-size web preview: no tile watermark, handle
  drag, row → pin, sheet row → detail, favourite toggle, theme persisted across
  reload. Gemini extraction still needs the key's API restriction lifted in
  Google Cloud Console.
- Web builds: after adding plugins, a stale `web_plugin_registrant.dart` hid
  the shared_preferences web implementation until `flutter clean`.

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

