// Widget tests for the place page's AI "Details / 詳情" section, the native
// name under the title and the "Translate caption" toggle (Place.details,
// filled by PlaceEnricher).
import 'package:cheaptripchip/data/board_store.dart';
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/models/board.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/models/place_details.dart';
import 'package:cheaptripchip/models/shared_board.dart';
import 'package:cheaptripchip/screens/place_detail_sheet.dart';
import 'package:cheaptripchip/services/place_enricher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

final _details = PlaceDetails(
  mustTry: const ['tonkotsu ramen', 'kae-dama'],
  priceLevel: 2,
  nativeName: '一蘭 渋谷店',
  tags: const ['late-night', 'solo-friendly'],
  openingHours: 'Daily 24h',
  captionEn: 'Ichiran ramen is great!',
  captionZh: '一蘭的拉麵超好吃！',
  enrichedAt: DateTime.utc(2026, 10, 18),
);

Place _place({PlaceDetails? details}) => Place(
  id: 'details-test-1',
  name: 'Ichiran',
  areaLabel: 'Shibuya',
  region: 'Tokyo',
  category: PlaceCategory.restaurant,
  location: const LatLng(35.66, 139.7),
  descriptionEn: 'Ramen.',
  originalCaption: '一蘭的拉麵超好吃！',
  address: '',
  hours: '',
  sourceHandle: '@x',
  sourcePlatform: SourcePlatform.instagram,
  countryCode: 'JP',
  details: details,
);

final _board = SharedBoard(
  id: 'sb',
  ownerId: 'alice',
  ownerName: 'Alice',
  name: 'Tokyo',
  emoji: '🗼',
  sections: const [
    BoardSection(title: 'Food', placeIds: ['details-test-1']),
  ],
  members: const {'alice': BoardRole.owner, 'bob': BoardRole.viewer},
  memberNames: const {'alice': 'Alice', 'bob': 'Bob'},
  inviteCode: 'abcdefghijklmnopqrstuvwx',
);

Future<void> _pump(
  WidgetTester tester,
  Place place, {
  PlaceDetailSource source = PlaceDetailSource.mine,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PlaceDetailSheet(place: place, source: source),
      ),
    ),
  );
  // The details section builds one frame after the sheet (_AfterFirstFrame).
  await tester.pump();
  await tester.pump();
}

PlaceEnricher _fakeEnricher({bool configured = true}) => PlaceEnricher(
  extractJson: (_) async => {
    'priceLevel': 3,
    'mustTry': ['gyoza'],
  },
  isConfigured: () => configured,
  ready: () async {},
);

void main() {
  late PlaceEnricher original;

  setUp(() {
    original = PlaceEnricher.instance;
    PlaceStore.instance.bindRepository(LocalPlaceRepository());
    BoardStore.instance.bindRepository(LocalBoardRepository());
  });

  tearDown(() => PlaceEnricher.instance = original);

  testWidgets('shows price, hours, must-try, tags and native name', (
    tester,
  ) async {
    PlaceEnricher.instance = _fakeEnricher();
    final place = _place(details: _details);
    await PlaceStore.instance.add(place);
    await _pump(tester, place);

    expect(find.text('DETAILS / 詳情'), findsOneWidget);
    expect(find.text('✨ AI'), findsOneWidget);
    expect(find.text('¥¥ · Moderate'), findsOneWidget);
    expect(find.text('Daily 24h'), findsOneWidget);
    expect(find.text('tonkotsu ramen'), findsOneWidget);
    expect(find.text('kae-dama'), findsOneWidget);
    expect(find.text('#late-night'), findsOneWidget);
    expect(find.text('#solo-friendly'), findsOneWidget);
    expect(find.text('一蘭 渋谷店'), findsOneWidget);
    expect(find.text('Refresh details'), findsOneWidget);
  });

  testWidgets('translate toggle shows the English caption for a CJK one', (
    tester,
  ) async {
    final place = _place(details: _details);
    await PlaceStore.instance.add(place);
    await _pump(tester, place);

    expect(find.text('一蘭的拉麵超好吃！'), findsOneWidget);
    await tester.ensureVisible(find.text('Translate caption / 翻譯'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Translate caption / 翻譯'));
    await tester.pump();
    expect(find.text('Ichiran ramen is great!'), findsOneWidget);
    expect(find.text('一蘭的拉麵超好吃！'), findsNothing);
    await tester.tap(find.text('Show original / 顯示原文'));
    await tester.pump();
    expect(find.text('一蘭的拉麵超好吃！'), findsOneWidget);
  });

  testWidgets('Refresh details fills in details from the enricher', (
    tester,
  ) async {
    PlaceEnricher.instance = _fakeEnricher();
    final place = _place();
    await PlaceStore.instance.add(place);
    await _pump(tester, place);

    expect(find.text('Not filled in yet / 尚未填寫'), findsOneWidget);
    await tester.ensureVisible(find.text('Refresh details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh details'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(PlaceStore.instance.byId(place.id).details!.priceLevel, 3);
    expect(find.text('¥¥¥ · Pricey'), findsOneWidget);
    expect(find.text('gyoza'), findsOneWidget);
    expect(find.text('Translate caption / 翻譯'), findsNothing);
  });

  testWidgets('no section without details when AI is not configured', (
    tester,
  ) async {
    PlaceEnricher.instance = _fakeEnricher(configured: false);
    final place = _place();
    await PlaceStore.instance.add(place);
    await _pump(tester, place);
    expect(find.text('DETAILS / 詳情'), findsNothing);
  });

  testWidgets('shared-board copy shows details read-only', (tester) async {
    PlaceEnricher.instance = _fakeEnricher();
    final shared = sharedCopyOf(_place(details: _details));
    expect(shared.details, isNotNull);
    await _pump(
      tester,
      shared,
      source: PlaceDetailSource.sharedBoard(_board, BoardRole.viewer),
    );

    expect(find.text('DETAILS / 詳情'), findsOneWidget);
    expect(find.text('¥¥ · Moderate'), findsOneWidget);
    expect(find.text('一蘭 渋谷店'), findsOneWidget);
    expect(find.text('Refresh details'), findsNothing);
  });

  testWidgets('shared-board copy without details hides the section', (
    tester,
  ) async {
    PlaceEnricher.instance = _fakeEnricher();
    await _pump(
      tester,
      sharedCopyOf(_place()),
      source: PlaceDetailSource.sharedBoard(_board, BoardRole.viewer),
    );
    expect(find.text('DETAILS / 詳情'), findsNothing);
  });
}
