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
flutter run
```

Requires the Flutter SDK (developed against Flutter 3.41). Map tiles need network access.

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

## Next steps (not in this draft)

1. Backend: link ingestion → AI extraction → geocoding (OSM/Nominatim) → persistence.
2. Share-sheet intake (`receive_sharing_intent`) so a reel can be shared straight into the app.
3. Real photos from the source post; swap mock data for an API client + local cache.
4. Auth + collaborative boards.
