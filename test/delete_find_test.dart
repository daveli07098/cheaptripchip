import 'dart:typed_data';

import 'package:cheaptripchip/data/board_store.dart';
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/memory_photo_repository.dart';
import 'package:cheaptripchip/data/mock_data.dart';
import 'package:cheaptripchip/data/photo_store.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/screens/home_shell.dart';
import 'package:cheaptripchip/widgets/place_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Unreferenced by any board, so it's listed on the auto "New finds" board.
const _fresh = Place(
  id: 'fresh',
  name: 'Fresh Find',
  areaLabel: 'Shibuya',
  region: 'Tokyo, Japan',
  category: PlaceCategory.cafe,
  location: LatLng(35.66, 139.70),
  descriptionEn: 'Not on any board yet.',
  originalCaption: 'caption',
  address: 'addr',
  hours: 'hours',
  sourceHandle: '@test',
  sourcePlatform: SourcePlatform.instagram,
);

void main() {
  late MemoryPhotoRepository photos;
  final gogo = MockData.places.first; // p1

  setUp(() async {
    PlaceStore.instance.bindRepository(LocalPlaceRepository());
    BoardStore.instance.bindRepository(LocalBoardRepository());
    photos = MemoryPhotoRepository();
    PhotoStore.instance.bindRepository(photos);
    await Future<void>.delayed(Duration.zero);
  });

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeShell()));
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(NavigationDestination, label));
    await tester.pumpAndSettle();
  }

  Finder card(String name) => find.widgetWithText(PlaceCard, name);

  group('Saved tab swipe', () {
    testWidgets('deletes the find off Saved and its boards; UNDO restores', (
      tester,
    ) async {
      await pumpShell(tester);
      await openTab(tester, 'Saved');

      await tester.drag(card(gogo.name), const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(card(gogo.name), findsNothing);
      expect(PlaceStore.instance.byIdOrNull(gogo.id), isNull);
      expect(BoardStore.instance.boardsContaining(gogo.id), isEmpty);
      expect(find.text('Deleted “${gogo.name}”'), findsOneWidget);

      await tester.tap(find.text('UNDO'));
      await tester.pumpAndSettle();

      expect(PlaceStore.instance.byIdOrNull(gogo.id), isNotNull);
      expect(BoardStore.instance.containsPlace('b1', gogo.id), isTrue);
      expect(card(gogo.name), findsOneWidget);
    });

    testWidgets('the photo is discarded only after the undo window', (
      tester,
    ) async {
      await PhotoStore.instance.setPhoto(gogo.id, Uint8List.fromList([1, 2]));
      await pumpShell(tester);
      await openTab(tester, 'Saved');

      await tester.drag(card(gogo.name), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(await photos.load(gogo.id), isNotNull);

      // The 6 s undo window, then the SnackBar's exit animation.
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(find.text('Deleted “${gogo.name}”'), findsNothing);
      expect(await photos.load(gogo.id), isNull);
    });

    testWidgets('UNDO keeps the photo', (tester) async {
      await PhotoStore.instance.setPhoto(gogo.id, Uint8List.fromList([1, 2]));
      await pumpShell(tester);
      await openTab(tester, 'Saved');

      await tester.drag(card(gogo.name), const Offset(-600, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('UNDO'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();

      expect(await photos.load(gogo.id), isNotNull);
    });
  });

  testWidgets('"New finds" rows swipe to Delete (the find), with UNDO', (
    tester,
  ) async {
    await PlaceStore.instance.add(_fresh);
    await pumpShell(tester);
    await openTab(tester, 'Boards');
    await tester.tap(find.text('New finds'));
    await tester.pumpAndSettle();

    final row = find.widgetWithText(ListTile, _fresh.name);
    await tester.drag(row, const Offset(-120, 0));
    await tester.pump();
    // The swipe background says Delete, not Remove.
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Remove'), findsNothing);
    await tester.pumpAndSettle();

    await tester.drag(row, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(PlaceStore.instance.byIdOrNull(_fresh.id), isNull);
    expect(find.text('Deleted “${_fresh.name}”'), findsOneWidget);

    await tester.tap(find.text('UNDO'));
    await tester.pumpAndSettle();
    expect(PlaceStore.instance.byIdOrNull(_fresh.id), isNotNull);
    expect(find.text('New finds'), findsOneWidget);
  });

  testWidgets('personal board rows still swipe to Remove from the board', (
    tester,
  ) async {
    await pumpShell(tester);
    await openTab(tester, 'Boards');
    await tester.tap(find.text('Coffee & Quiet'));
    await tester.pumpAndSettle();

    final name = MockData.places[2].name; // p3, in Cafés
    final row = find.widgetWithText(ListTile, name).last;
    await tester.drag(row, const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(find.text('Removed from Coffee & Quiet'), findsOneWidget);
    expect(PlaceStore.instance.byIdOrNull('p3'), isNotNull);
  });

  testWidgets('place page "Delete find" confirms, closes and offers UNDO', (
    tester,
  ) async {
    await pumpShell(tester);
    await openTab(tester, 'Saved');
    await tester.tap(card(gogo.name));
    await tester.pumpAndSettle();

    final delete = find.text('Delete find');
    await tester.ensureVisible(delete);
    await tester.pumpAndSettle();
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(find.text('Delete “${gogo.name}”?'), findsOneWidget);

    // Cancel keeps it.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(PlaceStore.instance.byIdOrNull(gogo.id), isNotNull);

    await tester.ensureVisible(delete);
    await tester.pumpAndSettle();
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(PlaceStore.instance.byIdOrNull(gogo.id), isNull);
    expect(find.text('Deleted “${gogo.name}”'), findsOneWidget);

    await tester.tap(find.text('UNDO'));
    await tester.pumpAndSettle();
    expect(PlaceStore.instance.byIdOrNull(gogo.id), isNotNull);
  });
}
