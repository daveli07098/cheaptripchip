import 'dart:typed_data';

import 'package:cheaptripchip/data/memory_photo_repository.dart';
import 'package:cheaptripchip/data/photo_store.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/widgets/place_preview_card.dart';
import 'package:cheaptripchip/widgets/score_stars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const _place = Place(
  id: 'preview-place',
  name: 'Preview Cafe',
  areaLabel: 'Shibuya',
  region: 'Tokyo, Japan',
  category: PlaceCategory.cafe,
  location: LatLng(35.66, 139.7),
  descriptionEn: '',
  originalCaption: '',
  address: '',
  hours: '',
  sourceHandle: '@test',
  sourcePlatform: SourcePlatform.instagram,
  myScore: 8,
);

Widget _host(Place place, VoidCallback onOpenDetails) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: PlacePreviewCard(place: place, onOpenDetails: onOpenDetails),
    ),
  ),
);

void main() {
  setUp(() => PhotoStore.instance.bindRepository(MemoryPhotoRepository()));

  testWidgets('shows name, area, score and the three actions', (tester) async {
    var opened = 0;
    await tester.pumpWidget(_host(_place, () => opened++));
    await tester.pump();

    expect(find.text('Preview Cafe'), findsOneWidget);
    expect(find.text('Shibuya · Tokyo, Japan'), findsOneWidget);
    expect(find.byType(ScoreBadge), findsOneWidget);
    // The category emoji carries a Semantics label (merged into the card's
    // tap target, so check the widget rather than the semantics tree).
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Cafe',
      ),
      findsWidgets,
    );
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Maps'), findsOneWidget);
    expect(find.text('Add photo'), findsOneWidget);

    await tester.tap(find.text('Details'));
    await tester.tap(find.text('Preview Cafe'));
    expect(opened, 2, reason: 'Details and the card body both open details');
  });

  testWidgets('photo action reads "Change photo" once a photo exists', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_place, () {}));
    await tester.pump();
    // Place isn't in PlaceStore, so setPhoto's marker update is a no-op.
    await tester.runAsync(
      () => PhotoStore.instance.setPhoto(
        _place.id,
        Uint8List.fromList([0xFF, 0xD8, 0xFF]),
      ),
    );
    await tester.pump();

    expect(find.text('Change photo'), findsOneWidget);
    expect(find.text('Add photo'), findsNothing);
  });
}
