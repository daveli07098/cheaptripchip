import 'package:cheaptripchip/data/board_store.dart';
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/mock_data.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/services/import_service.dart';
import 'package:cheaptripchip/services/trip_share.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Place _place(String id, String name, LatLng location) => Place(
  id: id,
  name: name,
  areaLabel: 'Area',
  region: 'Tokyo, Japan',
  category: PlaceCategory.cafe,
  location: location,
  descriptionEn: '',
  originalCaption: '',
  address: '',
  hours: '',
  sourceHandle: '',
  sourcePlatform: SourcePlatform.instagram,
);

/// Shifts [p] north by roughly [meters] (1° latitude ≈ 111 km).
LatLng _north(LatLng p, double meters) =>
    LatLng(p.latitude + meters / 111000, p.longitude);

void main() {
  group('ImportService', () {
    setUp(() async {
      // Fresh in-memory repositories per test; let their initial replay
      // settle first (same reasoning as place_store_test.dart).
      PlaceStore.instance.bindRepository(LocalPlaceRepository());
      BoardStore.instance.bindRepository(LocalBoardRepository());
      await Future<void>.delayed(Duration.zero);
    });

    test('isDuplicate: same name case-insensitively and within 50 m', () {
      final base = _place('a', 'Koffee Mameya', const LatLng(35.67, 139.71));
      expect(
        ImportService.isDuplicate(
          base,
          _place('b', '  koffee MAMEYA ', _north(base.location, 30)),
        ),
        isTrue,
      );
      expect(
        ImportService.isDuplicate(
          base,
          _place('c', 'Koffee Mameya', _north(base.location, 500)),
        ),
        isFalse,
      );
      expect(
        ImportService.isDuplicate(
          base,
          _place('d', 'Other Cafe', base.location),
        ),
        isFalse,
      );
    });

    test('adds new places, reuses saved ones, and creates a "Shared" '
        'board holding both', () async {
      final places = PlaceStore.instance;
      final boards = BoardStore.instance;
      final existing = MockData.places.first;
      final beforePlaces = places.places.value.length;
      final beforeBoards = boards.boards.value.length;

      final dup = _place(
        'fresh-dup',
        existing.name.toUpperCase(),
        _north(existing.location, 20),
      );
      final brandNew = _place('fresh-new', 'Brand New', const LatLng(1, 1));
      final far = _place(
        'fresh-far',
        existing.name,
        _north(existing.location, 500),
      );

      final result = await ImportService.importBundle(
        TripBundle(title: 'Friend trip', places: [dup, brandNew, far]),
      );
      await Future<void>.delayed(Duration.zero);

      expect(result.added, 2);
      expect(result.alreadySaved, 1);
      expect(places.places.value.length, beforePlaces + 2);
      expect(places.byIdOrNull('fresh-new'), isNotNull);
      expect(places.byIdOrNull('fresh-far'), isNotNull);
      expect(places.byIdOrNull('fresh-dup'), isNull);

      expect(boards.boards.value.length, beforeBoards + 1);
      final board = boards.byIdOrNull(result.board.id)!;
      expect(board.name, 'Friend trip');
      expect(board.emoji, '📥');
      expect(board.sections, hasLength(1));
      expect(board.sections.single.title, 'Shared');
      expect(board.sections.single.placeIds, [
        existing.id,
        'fresh-new',
        'fresh-far',
      ]);
    });

    test('duplicates inside the bundle collapse to one saved place', () async {
      final a = _place('in-a', 'Twin', const LatLng(2, 2));
      final b = _place('in-b', 'twin', _north(const LatLng(2, 2), 10));
      final before = PlaceStore.instance.places.value.length;

      final result = await ImportService.importBundle(
        TripBundle(title: 'Twins', places: [a, b]),
      );
      await Future<void>.delayed(Duration.zero);

      expect(result.added, 1);
      expect(result.alreadySaved, 0);
      expect(PlaceStore.instance.places.value.length, before + 1);
      expect(
        BoardStore.instance
            .byIdOrNull(result.board.id)!
            .sections
            .single
            .placeIds,
        ['in-a'],
      );
    });

    test('importing a decoded app link round-trips into the stores', () async {
      final bundle = TripShare.fromAppLink(
        TripShare.toAppLink(
          TripBundle(
            title: 'Link trip',
            places: [_place('x', 'Linked Spot', const LatLng(3, 3))],
          ),
        ),
      )!;

      final result = await ImportService.importBundle(bundle);
      await Future<void>.delayed(Duration.zero);

      expect(result.added, 1);
      final id = result.board.sections.single.placeIds.single;
      expect(PlaceStore.instance.byIdOrNull(id)?.name, 'Linked Spot');
    });
  });
}
