import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/models/place_note.dart';
import 'package:cheaptripchip/services/duplicate_matcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Place _place(
  String id,
  String name,
  LatLng location, {
  String caption = '',
  List<PlaceNote> notes = const [],
}) => Place(
  id: id,
  name: name,
  areaLabel: '',
  region: 'Tokyo, Japan',
  category: PlaceCategory.food,
  location: location,
  descriptionEn: '',
  originalCaption: caption,
  address: '',
  hours: '',
  sourceHandle: '@x',
  sourcePlatform: SourcePlatform.instagram,
  extraNotes: notes,
);

void main() {
  const ikebukuro = LatLng(35.7295, 139.7109);
  // ~50 m north of ikebukuro.
  const nextDoor = LatLng(35.72995, 139.7109);
  // ~370 km away (Osaka).
  const osaka = LatLng(34.6937, 135.5023);

  group('normalizeName', () {
    test('drops case, punctuation and spaces, keeps any script', () {
      expect(DuplicateMatcher.normalizeName('Ramen  Bon!'), 'ramenbon');
      expect(DuplicateMatcher.normalizeName('ramen-bon'), 'ramenbon');
      expect(DuplicateMatcher.normalizeName('五感 (Gogo)'), '五感gogo');
      expect(DuplicateMatcher.normalizeName('Café Été'), 'caféété');
    });
  });

  group('isSimilarName', () {
    test('shared parenthetical variant', () {
      expect(DuplicateMatcher.isSimilarName('五感 (Gogo)', 'Gogo'), isTrue);
      expect(DuplicateMatcher.isSimilarName('五感 (Gogo)', '五感'), isTrue);
    });
    test('containment and token overlap', () {
      expect(
        DuplicateMatcher.isSimilarName('Ichiran Shibuya', 'Ichiran'),
        isTrue,
      );
      expect(
        DuplicateMatcher.isSimilarName('Blue Bottle Coffee', 'Blue Bottle'),
        isTrue,
      );
    });
    test('unrelated names are not similar', () {
      expect(DuplicateMatcher.isSimilarName('Ramen Bon', 'Sushi Dai'), isFalse);
      expect(DuplicateMatcher.isSimilarName('', 'Sushi Dai'), isFalse);
    });
  });

  group('findDuplicate', () {
    test('same normalized name nearby-ish (same city) is a duplicate', () {
      final existing = _place('a', 'Ramen Bon', ikebukuro);
      final candidate = _place(
        'new',
        'RAMEN BON',
        const LatLng(35.69, 139.70), // ~4.5 km away, same city
      );
      expect(DuplicateMatcher.findDuplicate(candidate, [existing]), existing);
    });

    test('same name in another city is not a duplicate (chains)', () {
      final existing = _place('a', 'Ichiran', ikebukuro);
      final candidate = _place('new', 'Ichiran', osaka);
      expect(DuplicateMatcher.findDuplicate(candidate, [existing]), isNull);
    });

    test('similar name within 80 m is a duplicate', () {
      final existing = _place('a', '五感 (Gogo)', ikebukuro);
      final candidate = _place('new', 'Gogo', nextDoor);
      expect(DuplicateMatcher.findDuplicate(candidate, [existing]), existing);
    });

    test('similar name further than 80 m is not', () {
      final existing = _place('a', 'Ichiran Ikebukuro', ikebukuro);
      final candidate = _place(
        'new',
        'Ichiran',
        const LatLng(35.7320, 139.7109),
      );
      expect(DuplicateMatcher.findDuplicate(candidate, [existing]), isNull);
    });

    test('different name next door is not a duplicate', () {
      final existing = _place('a', 'Sushi Dai', ikebukuro);
      final candidate = _place('new', 'Ramen Bon', nextDoor);
      expect(DuplicateMatcher.findDuplicate(candidate, [existing]), isNull);
    });

    test('exact name match wins over an earlier nearby-similar match', () {
      final similar = _place('a', 'Ramen Bon Annex', nextDoor);
      final exact = _place('b', 'Ramen Bon', const LatLng(35.70, 139.70));
      final candidate = _place('new', 'Ramen Bon', ikebukuro);
      expect(
        DuplicateMatcher.findDuplicate(candidate, [similar, exact]),
        exact,
      );
    });

    test('ignores a place with the same id', () {
      final p = _place('a', 'Ramen Bon', ikebukuro);
      expect(DuplicateMatcher.findDuplicate(p, [p]), isNull);
    });
  });

  group('mergeNote', () {
    const url = 'https://www.instagram.com/p/abc/';
    test('notes the new source link', () {
      final existing = _place('a', 'Ramen Bon', ikebukuro);
      expect(
        DuplicateMatcher.mergeNote(existing, sourceUrl: url),
        'Also saved from $url',
      );
    });
    test('falls back to the handle, and to nothing without a source', () {
      final existing = _place('a', 'Ramen Bon', ikebukuro);
      expect(
        DuplicateMatcher.mergeNote(existing, via: '@bon'),
        'Also saved from a post by @bon',
      );
      expect(DuplicateMatcher.mergeNote(existing, via: '@unknown'), isNull);
      expect(DuplicateMatcher.mergeNote(existing), isNull);
    });
    test('is idempotent: no note when the link is already recorded', () {
      final inCaption = _place('a', 'Ramen Bon', ikebukuro, caption: url);
      final inNotes = _place(
        'b',
        'Ramen Bon',
        ikebukuro,
        notes: [
          PlaceNote(
            id: 'n',
            text: 'Also saved from $url',
            createdAt: DateTime(2026),
          ),
        ],
      );
      expect(DuplicateMatcher.mergeNote(inCaption, sourceUrl: url), isNull);
      expect(DuplicateMatcher.mergeNote(inNotes, sourceUrl: url), isNull);
    });
  });
}
