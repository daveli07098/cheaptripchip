# CheapTripChip

Save scattered Instagram / TikTok travel finds into organized, map-based plans.

Inspired by [Yaay Travel](https://popbee.com/lifestyle/gadgets/yaay-travel-app) for the
interaction model, and the [oyado JP travel concierge](https://oyado.gumroad.com/l/jptw) for a
Japan-first, curated, map-centric aesthetic. Full feasibility study and cost analysis live in
[`ANALYSIS.md`](./ANALYSIS.md).

## Status — draft

A front-end-only **Flutter** prototype with **mock data**. No backend wired yet; this draft
validates the UX and visual direction. The AI-extraction + geocoding pipeline described in
`ANALYSIS.md` is stubbed (the "Add a find" sheet is non-functional on purpose).

## What's in the draft

- **Explore (map)** — `flutter_map` + CartoDB dark tiles ($0, OSM-based), coral category pins,
  filter chips with counts, tap a pin → detail sheet.
- **Saved (feed)** — searchable card list with the "1 match" confidence badge.
- **Boards** — Board → Section → Item hierarchy (expandable).
- **Place detail** — photo header, area badge, AI summary, original (Japanese) caption,
  source attribution, address/hours, "Open in Google Maps" deep link, add-to-board.

Seed data is a handful of Tokyo places (see `lib/data/mock_data.dart`).

## Run it

```bash
flutter pub get
flutter run                      # mobile (iOS/Android)
flutter run -d chrome            # quick preview in the browser
```

Requires the Flutter SDK (developed against Flutter 3.41). Map tiles need network access.

### AI extraction config (Gemini)

The "Add a find" flow uses Gemini to extract a place from a pasted link/caption,
then geocodes it via OSM Nominatim. Ported from the event-calendar AI client
(model cascade, JSON mode, lenient parse). Provide the key at run time — nothing
is hard-coded:

```bash
flutter run --dart-define=GEMINI_API_KEY=your_key
# Optional reverse proxy (e.g. to bypass a regional block), same role as
# event-calendar's GEMINI_BASE_URL:
flutter run --dart-define=GEMINI_API_KEY=your_key \
            --dart-define=GEMINI_BASE_URL=https://your-proxy.example.workers.dev
```

Without a key, the app still runs and shows the seed data; extraction shows a
"no key" message. **Security:** a key shipped in a client app is exposed — for
production, point `GEMINI_BASE_URL` at your own backend/proxy and keep the key
server-side. The client is structured so that swap is config-only.

### Share-sheet intake

On Android, sharing a link/caption (from Instagram/TikTok's share sheet) opens
CheapTripChip with the "Add a find" sheet pre-filled. iOS requires a Share
Extension target (not yet added — see next steps).

## Project structure

```
lib/
  main.dart                 App entry + theme wiring
  models/                   place.dart, board.dart
  data/mock_data.dart       Seed Tokyo data (replaces backend for now)
  theme/app_theme.dart      Dark, map-first theme + per-category colours/icons
  widgets/place_card.dart   Reusable feed card
  screens/
    home_shell.dart         Bottom-nav shell (Explore / Saved / Boards) + add sheet
    map_screen.dart         Map with pins + category chips
    feed_screen.dart        Searchable saved list
    boards_screen.dart      Board → Section → Item
    place_detail_sheet.dart Draggable detail bottom sheet
```

## Next steps

1. **Persistence (Firebase)** — back `PlaceStore` with Firestore so saves survive
   restart and sync across devices. The screens already listen via
   `ValueListenableBuilder`, so this is a store-layer swap.
2. **iOS Share Extension** — add the iOS share target so intake works on iPhone
   (Android intent-filter is already wired).
3. **Full URL ingestion** — a bare reel URL can't be read client-side; move page
   fetch + extraction to the backend (feed page text to the same Gemini prompt).
4. **Real photos** from the source post; replace placeholder thumbnails.
5. **Auth + collaborative boards.**

### Done in the draft
- Gemini extraction (`lib/services/gemini_service.dart`) + Nominatim geocoding,
  wired into "Add a find" → saved place appears on map/feed.
- Android share-sheet intake (`receive_sharing_intent`).
