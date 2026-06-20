# CheapTripChip — Platform Feasibility Analysis

> Inspired by [Yaay Travel](https://popbee.com/lifestyle/gadgets/yaay-travel-app) — an app that converts scattered IG/TikTok saves into organized, map-based travel plans.

---

## Yaay Travel — Feature Summary (from iPad screenshots)

### 1. Share-to-Save Ingestion

- User shares an IG/TikTok post via iOS share sheet → Yaay
- Yaay appears in the share sheet row (can be pinned to favorites)
- Supports Instagram posts, Reels, and TikTok videos
- Onboarding overlay guides first-time setup ("Save 3 posts", "Show me how →")

### 2. AI Extraction & Enrichment

- **Auto-detects location** from post caption, hashtags, and image content
- **Generates English description** from any language (e.g. Japanese → English summary of 五感/Gogo ramen)
- **Extracts structured data:** name, full address, hours, cuisine type, awards (e.g. "Michelin Bib Gourmand")
- **Confidence indicator:** "1match" badge shows AI's geocoding confidence
- **Auto-categorization:** assigns tags like "Restaurant", "Food" automatically
- Cannot manually correct misidentified locations (noted limitation)

### 3. Map View

- Google Maps SDK with dark mode tiles
- All saved pins displayed on map simultaneously
- **Category filter chips** at top: "Restaurant 3", "Food 3" (label + count)
- Tap a pin → opens detail card overlay
- Embedded mini Google Map on detail card with "在 Google 地圖中開啟" (Open in Google Maps) deep link
- "View on map" button to jump from detail back to map view

### 4. Detail Card / Place View

- **Photo carousel** — swipeable images pulled from the original IG post
- **Location badge** — area tag (e.g. "池袋") at top of card
- **AI-generated description** — full English paragraph about the place
- **Original caption** — full Japanese text from the IG post preserved
- **Source attribution** — "By @rame.nbon on Instagram" with link back
- **Full address + hours** — e.g. "東京都豊島区東池袋2-57-2 コスモ東池袋101"
- **"Book" button** — likely links to reservation or Google Maps
- **Social actions row:** heart (favorite), thumbs up, comment, share icons

### 5. Boards (Organization System)

Hierarchical organization:

```
Board (e.g. "Tokyo Trip 2026")
  └── Section (e.g. "Food", "Sightseeing", "Shopping")
        └── Item (a saved place — 五感, etc.)
        └── Item
  └── Section (e.g. "Nightlife")
        └── Item
```

- **Boards** = top-level trip/theme containers
- **Sections** = category groupings within a board
- **Items** = individual saved places
- "+ Add to board" button on every detail card
- Three-dot menu (⋯) offers: "Add to board", "Share", "Edit", "Delete"
- Can organize the same item into multiple boards

### 6. Left Sidebar (Feed View)

- Scrollable card list of all saved places
- Each card shows: thumbnail image, place name, location tag, AI description preview
- "1match" indicator per card
- Region label (e.g. "Tokyo, Japan")
- Cards are tappable → opens detail on right panel

### 7. Actions & Management

- **Add to board** — assign any save to categorized boards/sections
- **Share** — share a place with friends
- **Edit** — modify details (though limited per the review)
- **Delete** — remove a save
- **Search bar** — "Search and explore saved items, boards, and inspiration" at top

### 8. iPad Layout

- Split-view design: left panel (feed/sidebar) + right panel (map or detail)
- Optimized for iPad multitasking

---

## Google Maps API Usage Analysis (from Yaay screenshots)

### APIs Used

| Feature | Google API | Evidence from screenshots | Price |
|---|---|---|---|
| **Map tiles (dark mode)** | Maps SDK for iOS | Full-screen interactive map with dark theme, pan/zoom | Mobile: **$0** (free unlimited) |
| **Markers / pins** | Maps SDK for iOS | Custom colored pins (pink 📍) on map | Included with SDK: **$0** |
| **Embedded mini-map** | Maps SDK (or Static Maps API) | Small map on detail card showing red Google pin | SDK: **$0** / Static: $2/1K |
| **"Open in Google Maps" link** | Google Maps URL scheme | "在 Google 地圖中開啟" deep link | **$0** (just a URL) |
| **Geocoding** (address → coords) | Geocoding API | Converts "東京都豊島区東池袋2-57-2" to lat/lng | $5 / 1K calls |
| **Place matching** | Places API (Find Place) | "1match" badge = AI-extracted name matched to a Google POI | $17 / 1K calls |

### APIs NOT Used (not visible in screenshots)

| Feature | Google API | Why not |
|---|---|---|
| Directions / routing | Directions API | No route lines drawn on map |
| Street View | Street View API | No street-level imagery |
| Place autocomplete | Places API | Search bar searches saved items, not Google Places |
| Satellite view | Maps SDK | Only dark vector tiles shown |
| Place photos | Places API | Photos come from IG posts, not Google |
| Reverse geocoding | Geocoding API | Area labels like "池袋" come from forward geocoding response (see below) |

### How API Call Counting Works

#### Geocoding API ($5 / 1K calls)

- **Forward geocoding** (address → coordinates): 1 API call
- **Reverse geocoding** (coordinates → area name): 1 API call
- Both use the same API, same price, but each direction is a **separate billable call**

**However:** Yaay likely does **NOT** make a separate reverse geocoding call. When you forward-geocode an address like `東京都豊島区東池袋2-57-2`, the response already includes `address_components`:

```json
{
  "results": [{
    "geometry": { "location": { "lat": 35.729, "lng": 139.718 } },
    "address_components": [
      { "long_name": "池袋", "types": ["sublocality_level_1"] },
      { "long_name": "豊島区", "types": ["ward"] },
      { "long_name": "東京都", "types": ["administrative_area_level_1"] }
    ]
  }]
}
```

So the area label "池袋" and region "Tokyo, Japan" shown in the app are **extracted from the same forward geocoding response** — no extra API call needed.

**Per save: 0–1 geocoding call = $0.000–0.005**

Depending on what the AI extracts from the IG post:

| IG post contains | Geocoding call needed | Why |
|---|---|---|
| Full address text | 1 forward call | Address → coords |
| GPS location tag only | 1 reverse call | Coords → area name/address |
| Place name only (no address) | 0 (use Places API instead) | Places API returns coords directly |
| Both address + GPS | 0 | Already have everything |

It's always **0 or 1 call** — never both directions for the same save. The forward geocoding response already includes `address_components` (area labels like "池袋"), so a separate reverse call is unnecessary.

#### Places API ($17 / 1K calls)

- **Find Place** request: given a place name + location, returns the matching Google POI
- The "1match" badge in Yaay = the AI-extracted name "五感 (Gogo)" was matched to exactly 1 Google Place
- Returns: official place name, place_id, rating, business hours, Google Maps link

**Per save: 1 Places API call = $0.017**

#### When Are Calls Made?

```
User shares IG post → Yaay
  │
  ├── 1. AI extracts: place name, address, description    (LLM API call — $0.01–0.04)
  │
  ├── 2. Geocoding: address → lat/lng + area labels       (1 Google API call — $0.005)
  │
  ├── 3. Places API: match name to Google POI              (1 Google API call — $0.017)
  │
  └── 4. Save all results to database                      (cached — $0)
         │
         └── All future views of this place: $0
             (served from database, no Google API calls)
```

**All API calls happen ONCE at save time.** After that, browsing the map, viewing detail cards, filtering by category — all served from the cached database. Zero additional API cost.

### Cost Per Save

| Call | API | Cost | Required? |
|---|---|---|---|
| AI extraction | OpenAI / Claude | $0.01–0.04 | Yes |
| Geocoding | Google Geocoding API | $0.005 | Yes |
| Place matching | Google Places API | $0.017 | Optional (can skip if AI + geocoding is enough) |
| Map tile loads | Google Maps SDK | $0.000 | Free on mobile |
| **Total per save** | | **$0.032–0.062** | |
| **Without Places API** | | **$0.015–0.045** | Cheaper but no Google POI verification |

### Monthly Google Maps API Cost by Scale

**Google Maps API only** (excludes AI, hosting, database).
Assuming **30 saves/user/day** = 900 saves/user/month.

Per-save Google API cost:
- Geocoding: $0.005 / save
- Places API: $0.017 / save
- Combined: $0.022 / save

$200/mo free credit covers:
- With Places API: ~9,000 saves → **~10 MAU** before credit runs out
- Without Places API: ~40,000 saves → **~44 MAU** before credit runs out

| MAU | Saves/mo | With Places API ($0.022/save) | Without Places API ($0.005/save) |
|---|---|---|---|
| 5 | 4,500 | **$0** | **$0** |
| 10 | 9,000 | **$0** (just at limit) | **$0** |
| 20 | 18,000 | **$196** | **$0** |
| 50 | 45,000 | **$790** | **$25** |
| 100 | 90,000 | **$1,780** | **$250** |
| 500 | 450,000 | **$9,700** | **$2,050** |
| 1,000 | 900,000 | **$19,600** | **$4,300** |
| 5,000 | 4,500,000 | **$98,800** | **$22,300** |
| 10,000 | 9,000,000 | **$197,800** | **$44,800** |

> All figures after subtracting $200/mo free credit. Mobile map tile loads = $0 (free unlimited).
>
> **Dropping Places API cuts Google costs by ~78%.** You can rely on AI + Geocoding alone — the AI extracts the place name and description, geocoding resolves the address to coordinates. You lose Google's official POI verification ("1match") but save significantly at scale.

---

## OSM + Leaflet + Nominatim Alternative

### Feature Parity with Google Maps

| Yaay Feature | Google Maps SDK | Leaflet + OSM Equivalent | Works? | Cost |
|---|---|---|---|---|
| **Map tiles (dark mode)** | Built-in dark theme | CartoDB Dark Matter / Stadia Dark tiles | ✅ | $0 |
| **Markers / pins** | Built-in | `L.marker()` | ✅ | $0 |
| **Embedded mini-map** | Maps SDK / Static Maps | Leaflet mini-map or static tile image | ✅ | $0 |
| **"Open in Google Maps" link** | URL scheme | `https://www.google.com/maps?q=35.729,139.718` | ✅ | $0 (just a URL, no API key) |
| **Forward geocoding** | Geocoding API ($5/1K) | Nominatim | ✅ | $0 |
| **Reverse geocoding** | Geocoding API ($5/1K) | Nominatim reverse | ✅ | $0 |
| **Place matching** (name → POI) | Places API ($17/1K) | Nominatim search | ⚠️ Weaker POI data | $0 |
| **Place details** (hours, rating) | Places API | ❌ OSM has some but inconsistent | ⚠️ Limited | $0 |

> The "Open in Google Maps" deep link is just a URL — `https://www.google.com/maps?q={lat},{lng}` or `https://www.google.com/maps/search/{place+name}`. No API key, no billing, works from any platform.

### What Counts as a Nominatim Request

Only **geocoding calls** count against the rate limit. Map browsing is separate.

| User action | Nominatim request? | Why |
|---|---|---|
| Save an IG link | **0 or 1** | Only if AI can't extract coords directly |
| Browse the map | **0** | Map tiles come from tile servers, NOT Nominatim |
| View a saved pin | **0** | Data served from your database |
| Pan / zoom the map | **0** | Tile server, not geocoding |
| Open detail card | **0** | From your database |
| Filter by category | **0** | From your database |

### How Many Nominatim Calls Per Save?

```
User shares IG post → your backend
  │
  ├── AI extracts from caption:
  │     - Place name: "五感 (Gogo)"
  │     - Address: "東京都豊島区東池袋2-57-2"
  │     - Coords from IG location tag: 35.729, 139.718  ← IG often embeds this!
  │
  ├── Case A: IG post has location tag (lat/lng)
  │     → 0 Nominatim calls (already have coords + AI extracts area name)
  │
  ├── Case B: IG post has address text but no coords
  │     → 1 Nominatim call (forward geocode: address → coords)
  │
  ├── Case C: IG post has neither address nor coords
  │     → 1 Nominatim call (search place name → coords)
  │
  └── Save to database → all future reads = 0 calls
```

**Average: ~0.5–0.8 Nominatim calls per save** (many IG posts embed GPS in their location tag).

### Nominatim Rate Limit: 1 req/sec

Free public Nominatim allows **1 request per second** = 86,400 requests/day = ~2.6M/month.

Since saves are spread across the day (not all at once), the real capacity is:

| MAU | Saves/mo (30/day/user) | Nominatim calls (~0.7/save) | Fits in 1 req/sec? |
|---|---|---|---|
| 10 | 9,000 | ~6,300 | ✅ Easily |
| 100 | 90,000 | ~63,000 | ✅ Yes |
| 1,000 | 900,000 | ~630,000 | ✅ Yes |
| 3,000 | 2,700,000 | ~1,890,000 | ✅ Just fits |
| 5,000 | 4,500,000 | ~3,150,000 | ❌ Exceeds — need self-host |

> Free Nominatim handles up to **~3K MAU** comfortably. Beyond that, self-host ($20–80/mo VPS) or use LocationIQ (~$0.50/1K calls).

### Cost Comparison: Google vs OSM (Maps/Geocoding Only)

Assuming 30 saves/user/day, ~0.7 Nominatim calls/save:

| MAU | Google (Geocoding + Places) | Google (Geocoding only) | OSM (Nominatim free) | OSM (self-hosted) |
|---|---|---|---|---|
| 10 | $0 | $0 | $0 | $0 |
| 50 | $790 | $25 | $0 | $20 |
| 100 | $1,780 | $250 | $0 | $20 |
| 500 | $9,700 | $2,050 | $0 | $40 |
| 1,000 | $19,600 | $4,300 | $0 | $40–80 |
| 5,000 | $98,800 | $22,300 | N/A (rate limited) | $80–200 |
| 10,000 | $197,800 | $44,800 | N/A | $100–200 |

### What You Lose with OSM

| Trade-off | Impact | Mitigation |
|---|---|---|
| No "1match" POI verification | Can't confirm place against Google database | AI accuracy + user can manually correct |
| Weaker small-shop geocoding in Asia | Some obscure shops may not resolve | AI extracts coords from IG location tag |
| No business hours / ratings from Google | Missing structured data | AI extracts from IG caption |
| Rate limited without self-hosting | 1 req/sec = ~3K MAU max | Self-host for $20–80/mo |
| "Open in Google Maps" link still works | ✅ No impact | It's just a URL, no API needed |

### Bottom Line: OSM Saves 95–99% on Maps Costs

| Scale | Google total | OSM total | Savings |
|---|---|---|---|
| 10 MAU | $0 | $0 | — |
| 100 MAU | $1,780 | $0 | **100%** |
| 1,000 MAU | $19,600 | $40–80 | **99.6%** |
| 10,000 MAU | $197,800 | $100–200 | **99.9%** |

---

## Feature Comparison: Web vs Native vs Flutter

| # | Feature | Web App | Native (Swift + Kotlin) | Flutter | Notes |
|---|---------|---------|-------------------------|---------|-------|
| 1 | **Share sheet integration** | ⚠️ Partial | ✅ Full | ✅ Full | Web: paste-a-link only. Android PWA has Share Target API. iOS Safari: no share target. Flutter uses `receive_sharing_intent` plugin for both platforms. |
| 2 | **AI location extraction** | ✅ Full | ✅ Full | ✅ Full | Backend-side — platform irrelevant. All call the same API endpoint. |
| 3 | **Map with pins** | ✅ Full | ✅ Full | ✅ Full | Web: Leaflet/Mapbox. Native: MapKit (iOS) + Google Maps (Android). Flutter: `google_maps_flutter` or `flutter_map` (Leaflet-equivalent, free). |
| 4 | **Boards / tags** | ✅ Full | ✅ Full | ✅ Full | Standard CRUD. No platform advantage. |
| 5 | **Collaborative lists** | ✅ Full | ✅ Full | ✅ Full | Web has easiest sharing (just a URL). Native/Flutter need deep links or share sheet. |
| 6 | **Source link + preview** | ✅ Full | ✅ Full | ✅ Full | OG meta scraping on backend. In-app browser or WebView for preview. |
| 7 | **Nearby recommendations** | ✅ Full | ✅ Full | ✅ Full | Backend AI + maps API. No platform dependency. |
| 8 | **Route planning** | ✅ Full | ✅ Full | ✅ Full | Google Directions API or OSRM (free). All platforms render polylines on map. |
| 9 | **Push notifications** | ⚠️ Partial | ✅ Full | ✅ Full | Web Push: works on Android + desktop, **not iOS Safari**. Flutter: `firebase_messaging` covers both platforms. |
| 10 | **Offline access** | ⚠️ Limited | ✅ Full | ✅ Full | PWA service worker caches pages but map tiles are heavy. Native/Flutter can use `sqflite`/Hive + cached tile layers. |
| 11 | **Camera / photo attach** | ✅ Full | ✅ Full | ✅ Full | Web camera API works on mobile browsers. Flutter: `image_picker`. |
| 12 | **GPS current location** | ✅ Full | ✅ Full | ✅ Full | Web Geolocation API. Flutter: `geolocator`. |
| 13 | **Smooth animations / gestures** | ⚠️ OK | ✅ Best | ✅ Great | Web can feel janky on low-end phones. Flutter's Skia/Impeller rendering is near-native. |
| 14 | **App Store presence** | ❌ No | ✅ Yes | ✅ Yes | PWA can be "installed" but not discoverable in App Store / Play Store. Flutter ships to both stores from one codebase. |
| 15 | **Hot reload / dev speed** | ✅ Fast | ❌ Slow | ✅ Fast | Flutter's hot reload rivals web DX. Native needs full recompile per change. |

### Scorecard

| Platform | Features covered (of 15) | Partial | Missing |
|----------|--------------------------|---------|---------|
| **Web App** | 11 ✅ | 3 ⚠️ | 1 ❌ |
| **Native (Swift + Kotlin)** | 15 ✅ | 0 | 0 |
| **Flutter** | 15 ✅ | 0 | 0 |

---

## Development Effort

| Feature | Web (Next.js) | Native (Swift + Kotlin) | Flutter |
|---------|---------------|-------------------------|---------|
| Paste URL + AI extract | 2–3 days | 4–6 days (×2) | 2–3 days |
| Map view + pins | 2–3 days | 5–7 days | 3–4 days |
| Boards / CRUD | 1–2 days | 2–4 days | 1–2 days |
| Auth + accounts | 1 day | 2–3 days | 1–2 days |
| Collaborative lists | 2–3 days | 3–5 days | 2–3 days |
| Link preview / OG scrape | 1 day | 1–2 days | 1 day |
| Nearby recommendations | 2–3 days | 3–5 days | 2–3 days |
| Route planning | 2–3 days | 3–5 days | 2–3 days |
| Share sheet integration | N/A | 2–3 days | 1–2 days |
| Push notifications | 1 day (web push) | 2–3 days | 1–2 days |
| Polish / deploy | 2–3 days | 5–7 days | 3–5 days |
| **Total** | **~2–3 weeks** | **~6–9 weeks** | **~3–4 weeks** |

---

## Running Costs (Monthly)

### Tier 1: Personal use (you + friends, < 50 saves/month)

| Service | Web | Native | Flutter | Notes |
|---------|-----|--------|---------|-------|
| Hosting / backend | $0 | $0 | $0 | Vercel / Cloudflare free tier |
| Database | $0 | $0 | $0 | Supabase free (500 MB, 50K rows) |
| AI (location extract) | ~$0.50 | ~$0.50 | ~$0.50 | ~50 calls × GPT-4o-mini ~$0.01/call |
| Maps | $0 | $0 | $0 | Leaflet + OSM / flutter_map + OSM |
| Auth | $0 | $0 | $0 | Supabase Auth free tier |
| App Store fees | $0 | $124/yr | $124/yr | Apple $99/yr + Google $25 one-time |
| **Total/month** | **~$0.50** | **~$10.83** | **~$10.83** | Native/Flutter add store fees |

### Tier 2: Small community (100–500 users)

| Service | Web | Native | Flutter |
|---------|-----|--------|---------|
| Hosting | $0–5 | $0–5 | $0–5 |
| Database | $25 | $25 | $25 |
| AI | $5–15 | $5–15 | $5–15 |
| Maps (if Google) | $0–10 | $0–10 | $0–10 |
| Store fees | $0 | ~$10 | ~$10 |
| **Total/month** | **~$30–50** | **~$40–60** | **~$40–60** |

### Tier 3: Public product (1K+ users)

| Service | Web | Native | Flutter |
|---------|-----|--------|---------|
| Hosting | $20 | $20 | $20 |
| Database | $25–75 | $25–75 | $25–75 |
| AI | $30–100 | $30–100 | $30–100 |
| Maps (Google) | $50–200 | $50–200 | $50–200 |
| Store fees | $0 | ~$10 | ~$10 |
| **Total/month** | **~$125–400** | **~$135–410** | **~$135–410** |

---

## Platform Recommendation

### For personal + friends → **Web App**

- Zero install — share a link, done
- Cheapest to run ($0.50/mo)
- Fastest to build (2–3 weeks)
- The paste-a-link UX is fine for a small group

### For a public product → **Flutter**

- One codebase → iOS + Android + (web via Flutter Web, though less polished)
- Full share sheet on both platforms
- Full push notifications
- App Store discoverability
- Dev speed close to web (hot reload)
- Half the effort of building two native apps

### When to pick Native (Swift + Kotlin)

- Only if you need best-in-class platform feel (custom iOS widgets, Android Wear, etc.)
- 2–3× the dev effort of Flutter for the same features
- Not justified for a travel organizer app

---

## Decision Matrix

| Criteria | Weight | Web | Native | Flutter |
|----------|--------|-----|--------|---------|
| Dev speed | 25% | ⭐⭐⭐ | ⭐ | ⭐⭐⭐ |
| Feature completeness | 20% | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |
| Running cost | 15% | ⭐⭐⭐ | ⭐⭐ | ⭐⭐ |
| UX / smoothness | 15% | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |
| Sharing / onboarding | 10% | ⭐⭐⭐ | ⭐⭐ | ⭐⭐ |
| Offline capability | 10% | ⭐ | ⭐⭐⭐ | ⭐⭐⭐ |
| Store presence | 5% | ⭐ | ⭐⭐⭐ | ⭐⭐⭐ |
| **Weighted score** | | **2.45** | **2.35** | **2.70** |

**Winner: Flutter** for a product you might grow.
**Winner: Web** if it stays personal/friends-only.

---

## Google Maps Pricing: Web vs Mobile SDK

Google charges **differently** for web (Maps JavaScript API) vs mobile (Maps SDK for iOS/Android).

### Per-API Pricing Comparison

| API | Web (JS API) | Mobile SDK (iOS/Android/Flutter) | Notes |
|-----|-------------|----------------------------------|-------|
| **Map loads** | $7.00 / 1K | $0 (free unlimited) | Mobile SDK map loads are **completely free**. Web is not. |
| **Dynamic map (with markers)** | $7.00 / 1K | $0 | Same — mobile wins. |
| **Static map images** | $2.00 / 1K | $2.00 / 1K | Same both platforms. |
| **Geocoding** (address → coords) | $5.00 / 1K | $5.00 / 1K | Same. Backend API — platform irrelevant. |
| **Places API** (search/autocomplete) | $17.00 / 1K (autocomplete) | $17.00 / 1K | Same. Backend or client — same price. |
| **Directions API** | $5.00 / 1K (up to 10 waypoints) | $5.00 / 1K | Same. Backend call. |
| **Routes API (advanced)** | $10.00 / 1K | $10.00 / 1K | Same. |

> **Key insight:** Google Maps SDK for mobile has **free unlimited map loads**. The web JS API charges $7/1K after the $200/mo free credit (~28K free loads). All other APIs (geocoding, places, directions) are the same price regardless of platform.

### Monthly $200 Free Credit

Google gives every project **$200/month** free credit across all Maps APIs. Here's what that covers:

| API usage | $200 credit covers |
|-----------|-------------------|
| Web map loads only | ~28,571 loads |
| Mobile map loads only | ∞ (map loads are free, use credit for other APIs) |
| Geocoding only | ~40,000 calls |
| Places autocomplete only | ~11,764 calls |
| Directions only | ~40,000 calls |

### Cost at Scale: Web vs App (Google Maps only)

Assuming each user loads the map **~30 times/month** and saves **~5 places/month**:

| Monthly active users | Web (Maps JS) | App (Mobile SDK) | Savings with App |
|---------------------|---------------|-------------------|-------------------|
| **50 users** | $0 | $0 | $0 (both within free tier) |
| **500 users** | $0 | $0 | $0 (still within free tier) |
| **1,000 users** | $10.50 | $0 | **$10.50/mo** |
| **5,000 users** | $157.50 | $0 | **$157.50/mo** |
| **10,000 users** | $507.00 | $0 | **$507.00/mo** |
| **50,000 users** | $2,835.00 | $0 | **$2,835.00/mo** |
| **100,000 users** | $5,670.00 | $0 | **$5,670.00/mo** |

> Map loads on mobile SDK = $0 forever. On web = $7/1K after free tier.

### Full Cost Projection (All APIs Combined, Public Product)

Assumptions per user/month: 30 map loads, 5 saves (5 geocoding + 5 AI calls), 2 direction lookups.

| MAU | Component | Web App | Flutter App |
|-----|-----------|---------|-------------|
| **1K** | Map loads | $10.50 | $0 |
| | Geocoding | $0 (in free tier) | $0 |
| | AI extraction | $50 | $50 |
| | Hosting + DB | $25 | $25 |
| | Store fees | $0 | $10 |
| | **Total** | **~$85** | **~$85** |
| **5K** | Map loads | $157.50 | $0 |
| | Geocoding | $0 (in free tier) | $0 |
| | AI extraction | $250 | $250 |
| | Hosting + DB | $50 | $50 |
| | Store fees | $0 | $10 |
| | **Total** | **~$457** | **~$310** |
| **10K** | Map loads | $507 | $0 |
| | Geocoding | $50 | $50 |
| | AI extraction | $500 | $500 |
| | Hosting + DB | $75 | $75 |
| | Store fees | $0 | $10 |
| | **Total** | **~$1,132** | **~$635** |
| **50K** | Map loads | $2,835 | $0 |
| | Geocoding | $450 | $450 |
| | AI extraction | $2,500 | $2,500 |
| | Hosting + DB | $200 | $200 |
| | Store fees | $0 | $10 |
| | **Total** | **~$5,985** | **~$3,160** |
| **100K** | Map loads | $5,670 | $0 |
| | Geocoding | $1,000 | $1,000 |
| | AI extraction | $5,000 | $5,000 |
| | Hosting + DB | $400 | $400 |
| | Store fees | $0 | $10 |
| | **Total** | **~$12,070** | **~$6,410** |

### The Crossover Point

| Scale | Winner on cost | Margin |
|-------|---------------|--------|
| < 1K MAU | Tie (~same) | ±$10 |
| 1K–5K MAU | App is **~32% cheaper** | Saves ~$150/mo |
| 5K–10K MAU | App is **~44% cheaper** | Saves ~$500/mo |
| 10K–50K MAU | App is **~47% cheaper** | Saves ~$2,800/mo |
| 50K–100K MAU | App is **~47% cheaper** | Saves ~$5,660/mo |

### Hybrid Strategy (Best of Both)

If you want to cover all users:

1. **Start with web** — fastest to build, $0 maps cost at small scale
2. **Use Leaflet + OSM for web** — avoids the $7/1K map load fee entirely, keeping web version at $0 for maps forever
3. **Add Flutter app later** — gets free Google Maps mobile SDK + share sheet + push notifications
4. **Share the same backend** — API server, database, AI extraction are platform-agnostic

This way:
- Web users get free maps (OSM) + easy link-share onboarding
- App users get free maps (Google SDK) + native share sheet + push
- Backend cost stays the same regardless
