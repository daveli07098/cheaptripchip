// Widget test for the personal place page's "My review" extra notes log:
// add another note via the dialog, PlaceStore reflects it and it renders in
// the list. Shared-board mode never shows the section at all.
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/models/shared_board.dart';
import 'package:cheaptripchip/screens/place_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const _place = Place(
  id: 'notes-test-1',
  name: 'Corner Spot',
  areaLabel: 'Shibuya',
  region: 'Tokyo',
  category: PlaceCategory.cafe,
  location: LatLng(35.6, 139.7),
  descriptionEn: 'Somewhere.',
  originalCaption: '',
  address: '',
  hours: '',
  sourceHandle: '@x',
  sourcePlatform: SourcePlatform.instagram,
);

Future<void> _pump(
  WidgetTester tester, {
  PlaceDetailSource source = PlaceDetailSource.mine,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PlaceDetailSheet(place: _place, source: source),
      ),
    ),
  );
  // The sheet defers everything below the fold to a post-first-frame build
  // (see _AfterFirstFrame in place_detail_sheet.dart) — pump past it.
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    PlaceStore.instance.bindRepository(LocalPlaceRepository());
  });

  testWidgets('Add another note opens a dialog and saves to the store', (
    tester,
  ) async {
    await PlaceStore.instance.add(_place);
    await _pump(tester);

    expect(find.text('Add another note / 再加備註'), findsOneWidget);

    await tester.ensureVisible(find.text('Add another note / 再加備註'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add another note / 再加備註'));
    await tester.pumpAndSettle();

    expect(find.text('Add another note / 再加備註'), findsWidgets);
    await tester.enterText(find.byType(TextField), '2nd visit: even better');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final notes = PlaceStore.instance.byId(_place.id).extraNotes;
    expect(notes, hasLength(1));
    expect(notes.single.text, '2nd visit: even better');
    expect(find.text('2nd visit: even better'), findsOneWidget);
  });

  testWidgets('Editing a note via its tile updates the store', (tester) async {
    await PlaceStore.instance.add(_place);
    await PlaceStore.instance.addNote(_place.id, 'original text');
    await _pump(tester);

    await tester.ensureVisible(find.text('original text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('original text'));
    await tester.pumpAndSettle();

    expect(find.text('Edit note / 編輯備註'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'updated text');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      PlaceStore.instance.byId(_place.id).extraNotes.single.text,
      'updated text',
    );
    expect(find.text('updated text'), findsOneWidget);
  });

  testWidgets('Delete from the edit dialog removes the note', (tester) async {
    await PlaceStore.instance.add(_place);
    await PlaceStore.instance.addNote(_place.id, 'delete me');
    await _pump(tester);

    await tester.ensureVisible(find.text('delete me'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('delete me'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(PlaceStore.instance.byId(_place.id).extraNotes, isEmpty);
    expect(find.text('Note deleted'), findsOneWidget);
  });

  testWidgets('shared-board mode never shows the extra-notes section', (
    tester,
  ) async {
    const board = SharedBoard(
      id: 'sb',
      ownerId: 'alice',
      ownerName: 'Alice',
      name: 'Tokyo',
      emoji: '🗼',
      sections: [],
      members: {'alice': BoardRole.owner},
      memberNames: {'alice': 'Alice'},
      inviteCode: 'abcdefghijklmnopqrstuvwx',
    );
    await _pump(
      tester,
      source: PlaceDetailSource.sharedBoard(board, BoardRole.viewer),
    );

    expect(find.text('Add another note / 再加備註'), findsNothing);
  });
}
