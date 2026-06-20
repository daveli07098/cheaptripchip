import 'package:latlong2/latlong.dart';

import '../models/board.dart';
import '../models/place.dart';

/// Seed data for the draft — Tokyo places, leaning Japanese per the
/// concierge/Japan-first direction (see ANALYSIS.md → UI / Design References).
/// Coordinates are approximate and only for laying out the map prototype.
class MockData {
  static const LatLng tokyoCenter = LatLng(35.6895, 139.6917);

  static const List<Place> places = [
    Place(
      id: 'p1',
      name: '五感 (Gogo)',
      areaLabel: '池袋',
      region: 'Tokyo, Japan',
      category: PlaceCategory.restaurant,
      location: LatLng(35.7295, 139.7185),
      descriptionEn:
          'A tucked-away Ikebukuro ramen bar known for a deeply layered '
          'shoyu broth and house-made noodles. Small counter, big flavour — '
          'go early or expect a queue.',
      originalCaption: '東池袋の隠れた名店。醤油の旨みが五感に染みる一杯。',
      address: '東京都豊島区東池袋2-57-2 コスモ東池袋101',
      hours: '11:00–15:00, 18:00–22:00 (Closed Wed)',
      sourceHandle: '@rame.nbon',
      sourcePlatform: SourcePlatform.instagram,
      award: 'Michelin Bib Gourmand',
    ),
    Place(
      id: 'p2',
      name: 'teamLab Planets TOKYO',
      areaLabel: '豊洲',
      region: 'Tokyo, Japan',
      category: PlaceCategory.sightseeing,
      location: LatLng(35.6480, 139.7900),
      descriptionEn:
          'An immersive, walk-through digital art museum where you wade '
          'barefoot through water and mirrored light rooms. Book a timed '
          'slot in advance — it sells out.',
      originalCaption: '水に入る没入型ミュージアム。裸足で歩く光の世界。',
      address: '東京都江東区豊洲6-1-16',
      hours: '09:00–22:00 (timed entry)',
      sourceHandle: '@tokyo.artspots',
      sourcePlatform: SourcePlatform.tiktok,
    ),
    Place(
      id: 'p3',
      name: 'Koffee Mameya',
      areaLabel: '表参道',
      region: 'Tokyo, Japan',
      category: PlaceCategory.food,
      location: LatLng(35.6668, 139.7126),
      descriptionEn:
          'A minimalist specialty-coffee counter in Omotesando. Baristas '
          'guide you through single-origin beans like a tasting flight. '
          'Standing-room only and worth it.',
      originalCaption: '表参道の名コーヒースタンド。豆選びはまるでテイスティング。',
      address: '東京都渋谷区神宮前4-15-3',
      hours: '10:00–18:00',
      sourceHandle: '@coffee.tokyo',
      sourcePlatform: SourcePlatform.instagram,
    ),
    Place(
      id: 'p4',
      name: 'Nakameguro Riverside',
      areaLabel: '中目黒',
      region: 'Tokyo, Japan',
      category: PlaceCategory.sightseeing,
      location: LatLng(35.6440, 139.6982),
      descriptionEn:
          'The canal lined with cherry trees and low-key boutiques and '
          'wine bars. Magic at dusk, peak in sakura season, lovely any time '
          'for an aimless wander.',
      originalCaption: '目黒川沿いの散歩道。桜の季節は格別。',
      address: '東京都目黒区青葉台',
      hours: 'Open 24h',
      sourceHandle: '@walk.tokyo',
      sourcePlatform: SourcePlatform.instagram,
    ),
    Place(
      id: 'p5',
      name: 'Bar Benfiddich',
      areaLabel: '西新宿',
      region: 'Tokyo, Japan',
      category: PlaceCategory.nightlife,
      location: LatLng(35.6915, 139.6960),
      descriptionEn:
          'A herbal cocktail bar where the bartender grinds fresh botanicals '
          'with a mortar and pestle. No menu — describe a mood and trust the '
          'craft. Reserve ahead.',
      originalCaption: '生のハーブを使うカクテルバー。メニューはなし、お任せで。',
      address: '東京都新宿区西新宿1-13-7 7F',
      hours: '18:00–01:00 (Closed Sun)',
      sourceHandle: '@nightcap.jp',
      sourcePlatform: SourcePlatform.instagram,
      award: "Asia's 50 Best Bars",
    ),
    Place(
      id: 'p6',
      name: 'Hoshinoya Tokyo',
      areaLabel: '大手町',
      region: 'Tokyo, Japan',
      category: PlaceCategory.stay,
      location: LatLng(35.6870, 139.7660),
      descriptionEn:
          'A luxury ryokan tower in the business district — tatami floors, '
          'an onsen on the top floor, kaiseki dining. A serene contrast to '
          'the city right outside.',
      originalCaption: '大手町の高層旅館。最上階に温泉、館内は畳敷き。',
      address: '東京都千代田区大手町1-9-1',
      hours: 'Check-in 15:00',
      sourceHandle: '@stay.japan',
      sourcePlatform: SourcePlatform.instagram,
    ),
  ];

  static const List<Board> boards = [
    Board(
      id: 'b1',
      name: 'Tokyo Trip 2026',
      emoji: '🗼',
      sections: [
        BoardSection(title: 'Food', placeIds: ['p1', 'p3']),
        BoardSection(title: 'Sightseeing', placeIds: ['p2', 'p4']),
        BoardSection(title: 'Nightlife', placeIds: ['p5']),
        BoardSection(title: 'Stay', placeIds: ['p6']),
      ],
    ),
    Board(
      id: 'b2',
      name: 'Coffee & Quiet',
      emoji: '☕',
      sections: [
        BoardSection(title: 'Cafés', placeIds: ['p3']),
        BoardSection(title: 'Walks', placeIds: ['p4']),
      ],
    ),
  ];

  static Place placeById(String id) =>
      places.firstWhere((p) => p.id == id);
}
