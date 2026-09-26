// Place page review/notes polish: share text uses the "District, City"
// display area, failed store writes revert with a SnackBar, the two note
// areas are labelled, and a set score can be cleared with one tap.
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/photo_store.dart';
import 'package:cheaptripchip/data/memory_photo_repository.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/screens/place_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'fakes/failing_place_repository.dart';

const _place = Place(
  id: 'review-test-1',
  name: 'Ramen Bar',
  areaLabel: 'Shibuya',
  region: 'Tokyo, Japan',
  category: PlaceCategory.cafe,
  location: LatLng(35.6, 139.7),
  descriptionEn: 'Somewhere.',
  originalCaption: '',
  address: '',
  hours: '',
  sourceHandle: '@x',
  sourcePlatform: SourcePlatform.instagram,
);

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(body: PlaceDetailSheet(place: _place)),
    ),
  );
  // Past _AfterFirstFrame's deferred below-the-fold build.
  await tester.pumpAndSettle();
}

void main() {
  group('placeShareText', () {
    test('uses District, City — not the raw area label/region', () {
      final text = placeShareText(_place);
      // (The Maps URL on line 2 carries its own search query.)
      expect(text.split('\n').first, 'Ramen Bar — Shibuya, Tokyo');
      expect(text, endsWith(_place.googleMapsUrl.toString()));
    });

    test('drops the extractor "Unknown" placeholder', () {
      final text = placeShareText(
        _place.copyWith(areaLabel: 'Unknown', region: 'Tokyo, Japan'),
      );
      expect(text.split('\n').first, 'Ramen Bar — Tokyo');
    });

    test('just the name when no area is known', () {
      final text = placeShareText(
        _place.copyWith(areaLabel: 'Unknown', region: 'Unknown'),
      );
      expect(text.split('\n').first, 'Ramen Bar');
    });
  });

  group('my review', () {
    setUp(() {
      PlaceStore.instance.bindRepository(LocalPlaceRepository());
      PhotoStore.instance.bindRepository(MemoryPhotoRepository());
    });

    testWidgets('labels Summary and Visit notes; add button is ≥48dp', (
      tester,
    ) async {
      await PlaceStore.instance.add(_place);
      await _pump(tester);

      expect(find.text('Summary / 總結'), findsOneWidget);
      expect(find.text('Visit notes / 到訪筆記'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Summary / 總結')).dy,
        lessThan(tester.getTopLeft(find.text('Visit notes / 到訪筆記')).dy),
      );
      final add = find.ancestor(
        of: find.text('Add a visit note / 加到訪筆記'),
        matching: find.byWidgetPredicate((w) => w is TextButton),
      );
      expect(tester.getSize(add).height, greaterThanOrEqualTo(48));

      // The Summary box opens a dialog titled the same.
      await tester.ensureVisible(find.text('Add a summary… / 加總結'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a summary… / 加總結'));
      await tester.pumpAndSettle();
      expect(find.text('Summary / 總結'), findsNWidgets(2));
      await tester.enterText(find.byType(TextField), 'Great broth');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(PlaceStore.instance.byIdOrNull(_place.id)!.myNotes, 'Great broth');
    });

    testWidgets('Clear appears once a score is set and clears it', (
      tester,
    ) async {
      await PlaceStore.instance.add(_place);
      await PlaceStore.instance.updateReview(_place.id, score: 7, notes: '');
      await _pump(tester);

      expect(find.text('7/10'), findsOneWidget);
      await tester.ensureVisible(find.text('Clear'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(PlaceStore.instance.byIdOrNull(_place.id)!.myScore, isNull);
      expect(find.text('Tap to rate'), findsOneWidget);
      expect(find.text('Clear'), findsNothing);
    });

    testWidgets('photo header has no standalone remove button', (tester) async {
      await PlaceStore.instance.add(_place);
      await PhotoStore.instance.setPhoto(
        _place.id,
        Uint8List.fromList(const [1, 2, 3]),
      );
      await _pump(tester);

      expect(find.text('Change photo'), findsOneWidget);
      expect(find.byTooltip('Remove photo'), findsNothing);
    });
  });

  group('failed save', () {
    late FailingPlaceRepository repo;

    setUp(() async {
      repo = FailingPlaceRepository(failWrites: false);
      PlaceStore.instance.bindRepository(repo);
      PhotoStore.instance.bindRepository(MemoryPhotoRepository());
    });

    testWidgets('favourite reverts and shows a SnackBar', (tester) async {
      await PlaceStore.instance.add(_place);
      repo.failWrites = true;
      await _pump(tester);

      await tester.tap(find.byTooltip('Add to favourites'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't save — try again"), findsOneWidget);
      expect(PlaceStore.instance.byIdOrNull(_place.id)!.isFavorite, isFalse);
      expect(find.byTooltip('Add to favourites'), findsOneWidget);
    });

    testWidgets('a score reverts and shows a SnackBar', (tester) async {
      await PlaceStore.instance.add(_place);
      repo.failWrites = true;
      await _pump(tester);

      await tester.ensureVisible(find.text('Tap to rate'));
      await tester.pumpAndSettle();
      final lastStar = find.byIcon(Icons.star_border).last;
      await tester.tapAt(tester.getCenter(lastStar) + const Offset(10, 0));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't save — try again"), findsOneWidget);
      expect(PlaceStore.instance.byIdOrNull(_place.id)!.myScore, isNull);
      expect(find.text('Tap to rate'), findsOneWidget);
    });
  });
}
