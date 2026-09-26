# Changelog

All notable changes to this project will be documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Move a place between personal boards: the row ⋮ menu on a personal
  board ("Move to board…" / "Remove from board"), a long-press on the row,
  or "Move to another board" on the place page opened from that board. The
  board picker opens in move mode (source tagged "Current", tap a target or
  create a new board), the row collapses out, and `BoardStore.movePlace`
  takes it off the source and onto the target's category section in one
  optimistic update and one repository write (`BoardRepository.upsertAll`:
  a single change event locally, one atomic `WriteBatch` on Firestore) —
  no frame shows the place on both boards or neither. "Moved to …" with
  UNDO (`undoMove`, restores both boards exactly) shows on the Boards tab or
  the place page once the picker has closed. Shared boards keep the
  existing add/remove flow.
- Shared-board ratings: on a shared board's place page every member (owner,
  editor or viewer) rates the place — "Ratings / 評分" shows "Your rating"
  (editable stars + remark box) with every other current member's rating
  read-only below it (avatar/initial, name, "Owner" tag, score badge,
  remark), an "Avg 7.5 · 3 ratings" line at 2+ ratings, and "No one else
  has rated this yet" when alone. The owner's score/notes baked into the
  shared copy (`includeOwnerNotes`) stand in as their entry (for other
  members, not the owner themself) until they rate.
  Stored at `sharedBoards/{id}/places/{placeId}/ratings/{uid}`
  (`PlaceRating`, `SharedBoardRepository.watchRatings/setRating/
  deleteRating`, `SharedBoardStore.setMyRating`); a score is required, so
  clearing your stars deletes your rating and the remark box stays disabled
  until you rate. Replaces the owner-only review section.
- firestore.rules: ratings — any member reads a board's ratings; each user
  creates/updates/deletes only `ratings/{their uid}` with an allow-listed
  body (`uid`/`placeId` matching the path, int score 1..10, notes ≤ 1000,
  name ≤ 100); non-members and removed members get nothing. 6 new emulator
  tests (34 total). Not deployed yet.
- Category chip on the place page ("🍽️ Restaurant ▾"): tap to pick any
  category from a bottom sheet (`PlaceStore.updateCategory`); the cuisine
  sub-type chip sits next to it for restaurants. Switching away keeps the
  saved cuisine pick (the chip just hides) and switching back restores it
  or the keyword guess. Read-only chip on shared boards.
- Collaborative shared boards with roles (signed-in only). ⋮ → "Share
  board…" MOVES a personal board to top-level `sharedBoards/{id}` (board +
  place copies in `sharedBoards/{id}/places`, same place ids; your own
  places stay in Saved; scores/notes/favourite/photo marker stripped unless
  the owner turns on "Include my scores & notes"). Roles: owner (everything),
  editor (add/remove places & sections), viewer (read only + "Save to my
  places", deduped via `ImportService.isDuplicate`). Sharing sheet: link
  Off / View only / Can edit, Copy / Share / Reset link, members with role
  dropdown and remove, "Stop sharing" (back to a personal board, places
  others added are saved to Saved, everyone else loses access); non-owners
  see their role and "Leave board". Boards tab badges: "Shared · 3 people" /
  "Shared by Ann · View only". Live via `SharedBoardStore` snapshot
  listeners, bound on auth in main.dart. Guests get "Sign in to share".
- Invite links `https://cheaptripchip-api.vercel.app/b/{id}?c={code}` and
  `cheaptripchip://board/{id}?c={code}` (`BoardInviteLink`), handled via
  app_links and the share sheet: sign in if needed, then a blind self-join
  (the rules check the invite code and link role server-side). Android: new
  custom-scheme intent filter and an `autoVerify` App Links filter for
  `/b/`. iOS: the existing `cheaptripchip` scheme covers board links;
  universal links are a TODO (needs an Apple team).
- server/: `GET /b/:id` landing page (no board data; "Open in
  CheapTripChip" button + one scripted attempt, CSP-pinned, no-store,
  noindex, no-referrer; malformed ids/codes → 404) and
  `/.well-known/assetlinks.json` with the debug keystore's SHA-256 (add the
  release key before shipping). vitest covers both.
- firestore.rules: `sharedBoards` — members read (the Boards-tab query is
  `memberIds` array-contains); create only as sole owner; owner updates
  anything but `ownerId`; editors only `sections`; self-join only with the
  current invite code, the link's role, and nothing but self added;
  members may remove only themself; `members`/`memberIds` must stay in sync
  with exactly one owner. Place copies: member read, owner/editor write,
  allow-listed keys and capped field sizes. 25 emulator tests in
  `rules-test/` (`npm run test:emulator`).
- Filter the map by location: the ☰ drawer has an "Areas" section under
  Categories — cities with flag and count (count desc), each expandable to
  its districts; "Unknown area (N)" for places not resolved yet; counts are
  over all places, like the category counts. The area filter is ANDed with
  category/cuisine and search, and shows as its own chip ("Shibuya, Tokyo ·
  12 ✕") next to the category chip, each with its own ✕.
- `AreaResolver` (lib/services/area_resolver.dart): background backfill of
  city → district for places missing them (e.g. My Maps imports) via
  Nominatim reverse geocoding (English names, zoom 14) — strictly
  sequential, ≥1.1 s apart, identifying User-Agent, backoff on 429/5xx,
  gives up after 5 failures in a row or any other 4xx. Starts ~5 s after
  launch/idle, pauses when the app is backgrounded, resumable; answers
  (including "nothing here") cached per 4-decimal coordinate in
  `guest/area_cache.json`. Results are saved in batches (every ~20 s or 50
  places) via `PlaceStore.updateAreas` → new `PlaceRepository.updateAll`,
  which on Firestore leaves `savedAt` (feed order) untouched. Existing
  city/district values (Gemini) are kept. A ~1,650-place backfill is ~30
  min of foreground time, once. Drawer shows "Finding areas… 320 / 1,650".
  Mapping rules per country (Tokyo wards, HK/Macau from `ISO3166-2-lvl3`,
  Korean gu, suffix/macron cleanup) are tested against 12 captured
  responses in test/fixtures/reverse_geocode/.
- `Place.countryCode` (ISO2; lenient JSON, `cc`/`countryCode` in the share
  codecs) and `Place.city`/`district`/`areaDisplay` getters (handle the
  older "Tokyo, Japan" region format). Detail sheet: the area badge shows
  "Shibuya, Tokyo" and is tappable to edit City/District by hand.
- Import from Google My Maps: Boards tab → Import menu ("From a shared trip
  link" / "From Google My Maps"), or share a My Maps link into the app. Paste
  a link (edit/viewer/`/u/N/` or a bare map id; clipboard prefilled), the app
  downloads the KML export (`/maps/d/kml?mid=…&forcekml=1`, parsed with
  `package:xml` in a background isolate) and previews title, place count and
  one checkbox per layer plus the board name (default "temp"). Import creates
  one 🗺️ board with a section per layer. Category comes from the layer (Food →
  restaurant/café by icon, Hotel → stay, 景點 → sightseeing, Shopping →
  shopping) or, for other layers, from the My Maps icon code; own score from a
  written `評分: x/5` / `Rating: x/10`, else the icon colour (green 9,
  yellow 5, red 2); description → plain-text notes; `<img>` and
  `gx_media_links` → photo URLs. Private maps get a "Share → Anyone with the
  link" hint; the web preview explains it can't download maps (CORS).
  New `SourcePlatform.googleMyMaps`.
- My Maps import refinements: icon colour scores only restaurants/cafés
  (a written `評分: x/5` still scores anything); area-label pins (generic pin,
  no description, name like 東京都/千葉市) are skipped by default via a "Skip
  area labels (N)" checkbox (unticked → imported as sightseeing); photo URLs
  request ~1280 px (`fife=s1280` / `=s1280`) instead of the original.
  Restaurant sub-type detection and search now also read `myNotes`.
- `PlaceStore.addAll` / `PlaceRepository.upsertAll`: bulk save in one update
  (Firestore: `WriteBatch`es of 450). `ImportService.importSections` (used by
  both importers) dedupes via a name-bucketed `DuplicateIndex` instead of
  scanning every saved place per incoming one.
- Tests: My Maps link/KML parsing on a trimmed fixture, category/score/notes
  mapping, sectioned board import, guest persistence round trip.
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
- "My review": `Place.myScore` (1–10, own rating, distinct from the source's
  5-point `rating`) and `Place.myNotes` (free-form text), editable from a new
  "My review" section in `PlaceDetailSheet` — a reusable `ScoreStars` picker
  (`lib/widgets/score_stars.dart`, half-star taps set odd/even points, tapping
  the current score clears it) plus a notes dialog. `PlaceStore.updateReview`
  saves both fields immediately (optimistic, like `toggleFavorite`); a compact
  `ScoreBadge` shows on `PlaceCard` and `PlaceListSheet` rows once a place has
  a score. Not included in any `TripShare` export (link/file/KML already
  allow-list their fields). Tests: JSON round-trip/clamp/garbage,
  `updateReview` set/clear, and a `ScoreStars` widget test (63 total).
- Pin tap → floating `PlacePreviewCard` (Google Maps style) just above the
  list sheet's top edge, tracking it as it drags; a sheet above half height
  collapses to peek. Photo thumbnail, name, category emoji, area, score badge,
  and Details / Maps / Add photo actions (tapping the card also opens
  details). Tapping empty map dismisses it; another pin swaps it (fade/slide).
  List-row selection still pans without a card.
- One personal photo per place: `PhotoStore` (bound on auth change like the
  other stores) over a `PhotoRepository` — Firestore
  `users/{uid}/photos/{placeId}` `{jpeg: Blob, updatedAt}` when signed in
  (Spark plan: no Cloud Storage, so bytes live in a doc apart from the place),
  `<app documents>/photos/<id>.jpg` for mobile guests, memory-only for web
  guests (lost on reload). `Place.myPhotoAt` marks which places have one so
  signed-in users skip a read for the rest; it's not in any `TripShare`
  export. Picked with `image_picker` (1280px, quality 75, 700 KB cap);
  add/change/remove (with confirm) from the preview card and the detail
  sheet header, which now prefers the user photo, then `photoUrls`.
- iOS `NSPhotoLibraryUsageDescription` / `NSCameraUsageDescription`. Android
  needs no permission (system photo picker and camera intent).
- Tests: `PhotoStore` (lazy load/cache, set/remove, revert on failure, size
  cap, marker-gated reads, rebind), `myPhotoAt` JSON, preview card, pin tap
  shows/empty map hides the card.
- `BoardPickerSheet` (`lib/widgets/board_picker_sheet.dart`, extracted from
  `PlaceDetailSheet`'s old `_BoardPickerSheet`): a Google-Maps-"Save to
  list"-style picker — a `CheckboxListTile` per stored board (checked via
  `BoardStore.containsPlace`), tapping toggles membership immediately without
  closing the sheet, so several boards can be picked in one go. "New board…"
  still creates the board and adds the place in one `createBoard(sections:)`
  upsert (avoids racing the repository echo), already checked. Tests:
  checkbox reflects membership, tap toggles add/remove in the store, new-board
  creation, `addToBoardLabel` (5 total, 94 project-wide).
- Restaurant cuisine sub-types: `RestaurantType` enum (ramen, sushi, izakaya,
  yakiniku, hot pot, dim sum, cha chaan teng, Japanese (other), Korean,
  Western, fine dining, other), `Place.restaurantType` (nullable — every place
  starts unset, no bulk tagging/migration). `Place.effectiveRestaurantType`
  resolves at read time: the stored value (user pick or Gemini extraction)
  always wins, else a keyword guess from the new
  `lib/models/restaurant_type_detect.dart` (`detectRestaurantType`, EN/繁/簡/日
  substring keywords, specific dishes checked before the generic "other
  Japanese" bucket), else "Other" — nothing is ever written back by the
  detector. Gemini extraction (`PlaceExtractor`) requests a `restaurantType`
  when the category is restaurant and leniently maps model output, including
  a small synonym table (sushi/sashimi, yakitori→izakaya, dim sum/cantonese,
  bbq/barbecue→yakiniku, cha chaan teng/茶餐廳). Map drawer's Restaurant row is
  now expandable (`_RestaurantCategoryTile`, only types with count > 0, in
  enum order; auto-expands when a sub-type becomes selected) to filter by
  sub-type; the active-category chip shows it ("🍜 Ramen · 5 ✕"). Search
  (`placeMatches`) also matches the effective type's English/Chinese label.
  Detail sheet shows a tappable "🍜 Ramen ▾" chip for restaurants (opens a
  bottom-sheet picker, saves via new `PlaceStore.setRestaurantType`);
  `PlaceCard`'s meta line shows the type instead of the generic "Restaurant"
  label. `TripShare` includes it as optional `rt` (link) / `restaurantType`
  (file) fields — old links/files without it still decode (`restaurantType`
  null → resolved as "Other" by `effectiveRestaurantType`). Mock data left
  untagged on purpose: Gogo (p1) already reads as ramen via detection (its
  descriptionEn mentions "ramen"), demonstrating the fallback. Tests: model
  JSON round-trip/unknown value/`effectiveRestaurantType` precedence,
  `detectRestaurantType` per-language + priority + no-match, extractor
  synonym mapping, store `setRestaurantType`, search matches, share codec
  round-trip + legacy-link decode, and a map-screen drawer widget test
  (25 new, 119 project-wide).
- `PostMetadata`/`fetchPostMetadata` (`lib/services/post_metadata.dart`):
  scrapes an Instagram/TikTok post's `og:title`/`og:description` via a
  crawler User-Agent (public pages 200 with these tags for that UA; a normal
  browser UA gets a login-wall shell) and derives a caption + author handle,
  HTML-entity-decoded (named, decimal, hex, including astral emoji and
  multi-line captions). No-ops on web (CORS blocks the cross-origin fetch).
  `PlaceExtractor.extract` uses it to enrich a bare-link share with the real
  caption before calling Gemini. Tests: og-tag parsing (attribute order,
  quote style, multi-line content), entity decoding, caption/author
  derivation for Instagram- and TikTok-shaped pages, `extractFirstPostUrl`
  on messy share text, and `fetchPostMetadata` against a mocked client
  (200-with-tags / 200-without / 404 / timeout).
### Changed
- Boards ⋮ "Share" is now "Send a copy" (the snapshot export sheet,
  unchanged otherwise).
- `sectionsWithChanges` (lib/models/board.dart) holds the add/remove
  section merge shared by `BoardStore.updateBoardPlaces` and the shared
  store; `AddPlacesSheet` takes an optional `onApply`.
- Guest mode now persists: places and boards are saved as JSON snapshots
  (`<app documents>/guest/*.json`, atomic write, debounced; web:
  shared_preferences) instead of living only in memory until restart.
  `MockData` only seeds the very first launch.
- Map list sheet builds rows lazily; pin taps still scroll off-screen rows
  into view (jump by index, then fine-tune). Board sections show 100 rows at
  a time ("Show more").
- `firestore.rules`: explicit `places`/`boards`/`photos` matches replace the
  `users/{uid}/{document=**}` wildcard (any allow wins, so the wildcard would
  bypass the new photo guard: `jpeg is bytes`, `< 1000000` bytes, only
  `jpeg`/`updatedAt` keys).
- `PlaceDetailSheet` has its own `ScaffoldMessenger`, so its SnackBars show
  over the sheet instead of under the modal barrier.
- `BoardStore.createBoard` takes optional `sections`, so a pre-filled board is
  written in one upsert (a loop of `addPlaceToBoard` can race the repository
  echo).
- firebase_core_web 3.11.0 → 3.12.0 (lockfile only): 3.11.0 doesn't compile
  for web under Flutter 3.41.7 (`isA` on `Object`) — pre-existing, unrelated
  to this feature.
- `BoardPickerSheet` (the board picker opened from the detail sheet's "Add to
  board" button) now has its own `ScaffoldMessenger`/`Scaffold`, mirroring
  `PlaceDetailSheet` — it's itself the topmost modal route (over the detail
  sheet, which now stays open underneath it), so its "Added"/"Removed"
  SnackBars would otherwise render under its own modal barrier.
- Removing a member from a shared board now resets the invite code in the
  same Firestore write (`SharedBoardRepository.removeMemberResetLink`) —
  their copy of the link stops working immediately instead of only after a
  separate "Reset link". The remove dialog says so when the link is on.
- `PlaceDetailSheet` takes a `PlaceDetailSource` (`.mine` or
  `.sharedBoard(board, role)`, set on `PlaceDetailSheet.show`). Opening a
  place from a shared board — any role, including the owner — now shows a
  read-only view (header photo from `photoUrls` only, name, category/
  sub-type, area, description, the owner's score/notes as plain text only
  when the board includes them, "Open in Google Maps") with "Save to my
  places" instead of favourite/My review/photo controls/area+type edit/
  "Add to board", which all act on the user's own Saved store and would
  otherwise read or write the wrong person's data — a shared copy keeps the
  owner's place id, so the personal widgets' usual `PlaceStore`/`PhotoStore`
  lookups by id would leak the owner's own photo, score, and notes.
### Fixed
- Boards tab: board cards no longer collapse (and their sections no longer
  reset) when the list shifts — e.g. the "New finds" card appearing after
  a place is removed from its last board, or a board delete/undo. The
  `ListView` now matches cards by key (`findItemIndexCallback`) instead of
  reusing state by index.
- Removing a place from a board (swipe, row menu, or the add picker) now
  undoes in place: UNDO writes back the pre-removal board in one update, so
  the place returns to its old section and position instead of being
  appended to the end (one rebuild instead of one per section).
- Detail sheet's "Add to board" button gave no feedback on success and no
  indication a place was already saved anywhere, so a re-tap silently
  no-opped: the button now reads "In <board name>" / "In N boards" (kept in
  sync with `BoardStore.boards`), and the picker shows a checkbox per board
  reflecting membership instead of an always-tappable "add" row.
- Sharing a bare Instagram/TikTok link (no caption — Android's IG share
  sheet only sends the URL) silently saved an "Untitled place" pinned to
  Tokyo, with no error shown. `PlaceExtractor.extract` now fetches the
  post's caption first (see `PostMetadata` above) and throws
  `CaptionUnavailableException` for a bare link it still can't read (private
  post, deleted, rate-limited), and `NoPlaceFoundException` whenever Gemini's
  result has no name/address/coordinates to save — `AddFindSheet` shows a
  friendly message for each and never saves a placeholder place.
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

