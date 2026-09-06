import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:cheaptripchip/models/board.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/screens/boards_screen.dart';

Place _place(String id, PlaceCategory category) => Place(
  id: id,
  name: 'Place $id',
  areaLabel: 'Area',
  region: 'Region',
  category: category,
  location: const LatLng(0, 0),
  descriptionEn: '',
  originalCaption: '',
  address: '',
  hours: '',
  sourceHandle: '@handle',
  sourcePlatform: SourcePlatform.instagram,
);

void main() {
  group('newFindsBoard', () {
    test('returns null when every place is already referenced', () {
      final places = [
        _place('p1', PlaceCategory.restaurant),
        _place('p2', PlaceCategory.cafe),
      ];
      final boards = [
        const Board(
          id: 'b1',
          name: 'Trip',
          emoji: '🗼',
          sections: [
            BoardSection(title: 'Food', placeIds: ['p1']),
            BoardSection(title: 'Cafés', placeIds: ['p2']),
          ],
        ),
      ];

      expect(newFindsBoard(places, boards), isNull);
    });

    test(
      'groups unreferenced places by category into one board with sections',
      () {
        final places = [
          _place('p1', PlaceCategory.restaurant),
          _place('p2', PlaceCategory.cafe),
          _place('p3', PlaceCategory.restaurant),
        ];
        final boards = [
          const Board(
            id: 'b1',
            name: 'Trip',
            emoji: '🗼',
            sections: [
              BoardSection(title: 'Food', placeIds: ['p3']),
            ],
          ),
        ];

        final board = newFindsBoard(places, boards);

        expect(board, isNotNull);
        expect(board!.name, 'New finds');
        expect(board.emoji, '📌');
        expect(board.sections.length, 2);

        final restaurantSection = board.sections.firstWhere(
          (s) => s.title == PlaceCategory.restaurant.labelEn,
        );
        expect(restaurantSection.placeIds, ['p1']);

        final cafeSection = board.sections.firstWhere(
          (s) => s.title == PlaceCategory.cafe.labelEn,
        );
        expect(cafeSection.placeIds, ['p2']);
      },
    );
  });
}
