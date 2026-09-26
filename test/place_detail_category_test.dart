// Widget tests for the personal place page's category chip: tap it, pick a
// category from the bottom sheet, and PlaceStore reflects the change (the
// restaurant sub-type chip follows). Shared-board mode shows the category
// as a plain, non-tappable chip.
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/models/shared_board.dart';
import 'package:cheaptripchip/screens/place_detail_sheet.dart';
import 'package:cheaptripchip/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const _place = Place(
  id: 'cat-test-1',
  name: 'Corner Spot',
  areaLabel: 'Shibuya',
  region: 'Tokyo',
  category: PlaceCategory.restaurant,
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
  await tester.pump();
}

/// First stop of the photo header's category-colour gradient (no photo).
Color _headerColor(WidgetTester tester) {
  final box = tester
      .widgetList<Container>(find.byType(Container))
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .firstWhere((d) => d.gradient is LinearGradient);
  return (box.gradient! as LinearGradient).colors.first;
}

void main() {
  setUp(() {
    PlaceStore.instance.bindRepository(LocalPlaceRepository());
  });

  testWidgets('tap the category chip, pick Cafe, the store updates', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await PlaceStore.instance.add(_place);
    await _pump(tester);

    expect(
      find.bySemanticsLabel('Category: Restaurant. Tap to change.'),
      findsOneWidget,
    );
    // The cuisine chip sits next to it while it's a restaurant.
    expect(find.bySemanticsLabel(RegExp('^Cuisine: ')), findsOneWidget);

    expect(
      _headerColor(tester),
      AppTheme.categoryColor(
        PlaceCategory.restaurant,
        Brightness.light,
      ).withValues(alpha: 0.9),
    );

    await tester.tap(find.text('Restaurant'));
    await tester.pumpAndSettle();
    expect(find.text('Category / 類別'), findsOneWidget);
    await tester.tap(find.text('Cafe'));
    await tester.pumpAndSettle();

    expect(PlaceStore.instance.byId('cat-test-1').category, PlaceCategory.cafe);
    expect(
      find.bySemanticsLabel('Category: Cafe. Tap to change.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('^Cuisine: ')), findsNothing);
    // The header gradient recolours live, without reopening the sheet.
    expect(
      _headerColor(tester),
      AppTheme.categoryColor(
        PlaceCategory.cafe,
        Brightness.light,
      ).withValues(alpha: 0.9),
    );
    semantics.dispose();
  });

  testWidgets('shared-board mode shows a read-only category chip', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
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

    expect(
      find.bySemanticsLabel(RegExp('Category: Restaurant(?!. Tap)')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.expand_more), findsNothing);
    await tester.tap(find.text('Restaurant'));
    await tester.pumpAndSettle();
    expect(find.text('Category / 類別'), findsNothing);
    semantics.dispose();
  });
}
