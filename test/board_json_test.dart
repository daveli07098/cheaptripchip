import 'dart:convert';

import 'package:cheaptripchip/models/board.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Board JSON round-trip', () {
    test('board with two sections round-trips', () {
      const board = Board(
        id: 'tokyo-trip',
        name: 'Tokyo Trip',
        emoji: '🗼',
        sections: [
          BoardSection(
            title: 'Food',
            placeIds: ['gogo-ikebukuro', 'ramen-shop'],
          ),
          BoardSection(title: 'Sightseeing', placeIds: ['senso-ji']),
        ],
      );

      final json = board.toJson();
      // Confirm toJson() emits plain JSON types only by round-tripping
      // through a real JSON encoder/decoder, matching what Firestore/
      // jsonDecode actually hand back to fromJson.
      final reencoded = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
      final decoded = Board.fromJson(reencoded);

      expect(json['sections'], isA<List>());
      expect(json['sections'], hasLength(2));

      expect(decoded.id, board.id);
      expect(decoded.name, board.name);
      expect(decoded.emoji, board.emoji);
      expect(decoded.sections, hasLength(2));
      expect(decoded.sections[0].title, 'Food');
      expect(decoded.sections[0].placeIds, ['gogo-ikebukuro', 'ramen-shop']);
      expect(decoded.sections[1].title, 'Sightseeing');
      expect(decoded.sections[1].placeIds, ['senso-ji']);
      expect(decoded.itemCount, 3);
    });

    test('lenient parse: missing sections falls back to empty list', () {
      final json = <String, dynamic>{
        'id': 'empty-board',
        'name': 'Empty Board',
        'emoji': '📋',
        // sections intentionally omitted
      };

      final decoded = Board.fromJson(json);

      expect(decoded.id, 'empty-board');
      expect(decoded.name, 'Empty Board');
      expect(decoded.emoji, '📋');
      expect(decoded.sections, isEmpty);
      expect(decoded.itemCount, 0);
    });

    test('copyWith updates only requested fields', () {
      const board = Board(
        id: 'tokyo-trip',
        name: 'Tokyo Trip',
        emoji: '🗼',
        sections: [
          BoardSection(title: 'Food', placeIds: ['a']),
        ],
      );

      final renamed = board.copyWith(name: 'Osaka Trip');
      expect(renamed.id, board.id);
      expect(renamed.name, 'Osaka Trip');
      expect(renamed.emoji, board.emoji);
      expect(renamed.sections, board.sections);

      final section = board.sections.first;
      final retitled = section.copyWith(title: 'Restaurants');
      expect(retitled.title, 'Restaurants');
      expect(retitled.placeIds, section.placeIds);
    });
  });
}
