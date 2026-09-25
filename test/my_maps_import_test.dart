import 'dart:convert';
import 'dart:io';

import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/services/my_maps_import.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('parseMyMapsId', () {
    const mid = '18CC871xLj1gaVQIVAnmU_wZsWIRe1c4';

    test('accepts edit, viewer, /u/N/ and kml links', () {
      for (final link in [
        'https://www.google.com/maps/d/u/0/edit?hl=zh-TW&mid=$mid&ll=35.6,139.7&z=10',
        'https://www.google.com/maps/d/viewer?mid=$mid',
        'https://www.google.com/maps/d/u/1/viewer?ll=1,2&mid=$mid',
        'https://www.google.com/maps/d/kml?mid=$mid&forcekml=1',
        'Check out my map! https://www.google.com/maps/d/edit?mid=$mid 🗺️',
      ]) {
        expect(parseMyMapsId(link), mid, reason: link);
      }
    });

    test('accepts a bare id only when it is the whole text', () {
      expect(parseMyMapsId('  $mid \n'), mid);
      expect(parseMyMapsId('my id is $mid'), isNull);
    });

    test('ignores other links and text', () {
      for (final text in [
        '',
        'https://www.instagram.com/reel/C1234567890abcdefghij/',
        'https://www.google.com/maps/place/Tokyo+Tower?mid=$mid',
        'https://maps.app.goo.gl/AbCdEfGhIjKlMnOpQr',
        'Great ramen in Ikebukuro',
      ]) {
        expect(parseMyMapsId(text), isNull, reason: text);
      }
    });

    test('kmlUrl asks for plain KML', () {
      expect(
        kmlUrl(mid).toString(),
        'https://www.google.com/maps/d/kml?mid=$mid&forcekml=1',
      );
    });
  });

  group('fetchKml', () {
    test('returns the KML body, decoded as UTF-8', () async {
      // No charset in the content type — must not fall back to latin-1.
      final client = MockClient(
        (_) async => http.Response.bytes(
          utf8.encode('<kml><Document><name>東京</name></Document></kml>'),
          200,
          headers: {'content-type': 'application/vnd.google-earth.kml+xml'},
        ),
      );
      expect(await fetchKml('abc', client: client), contains('東京'));
    });

    test('a private map (login page or error) reads as not shared', () {
      final login = MockClient(
        (_) async => http.Response('<html>Sign in</html>', 200),
      );
      final forbidden = MockClient((_) async => http.Response('', 403));
      for (final client in [login, forbidden]) {
        expect(
          fetchKml('abc', client: client),
          throwsA(
            isA<MyMapsImportException>().having(
              (e) => e.message,
              'message',
              MyMapsImportException.notShared,
            ),
          ),
        );
      }
    });
  });

  group('parseMyMapsKml (fixture)', () {
    final doc = parseMyMapsKml(
      File('test/fixtures/my_maps_sample.kml').readAsStringSync(),
    );
    MyMapsPlacemark byName(String folder, String name) => doc.folders
        .firstWhere((f) => f.name == folder)
        .placemarks
        .firstWhere((p) => p.name == name);

    test('title, folders in KML order, counts; non-points skipped', () {
      expect(doc.title, 'Sample Trip 🗺️');
      expect(doc.folders.map((f) => f.name), ['Food', 'Hotel', '景點', 'temp']);
      expect(doc.folders.map((f) => f.count), [4, 1, 1, 3]);
      expect(doc.placeCount, 9);
    });

    test('coordinates are lng,lat in KML', () {
      final p = byName('Food', 'Sample Tonkatsu');
      expect(p.location.latitude, closeTo(35.6712, 1e-9));
      expect(p.location.longitude, closeTo(139.7671, 1e-9));
    });

    test('icon code and colour come from the style url', () {
      final p = byName('Food', 'Sample Noodles');
      expect(p.iconCode, 1640);
      expect(p.colour, 'FFEA00');
      expect(byName('temp', 'Some Pin').iconCode, 1899);
    });

    test('CDATA names are read as text', () {
      expect(byName('Food', 'Bean & Cup').category, PlaceCategory.cafe);
    });

    test('category: named layers win, food refines by icon, else icon', () {
      expect(
        byName('Food', 'Sample Tonkatsu').category,
        PlaceCategory.restaurant,
      );
      expect(
        byName('Food', 'Sample Noodles').category,
        PlaceCategory.restaurant,
      );
      expect(byName('Hotel', 'Sample Inn').category, PlaceCategory.stay);
      expect(byName('景點', 'Sample Shrine').category, PlaceCategory.sightseeing);
      expect(byName('temp', 'Sample Mall').category, PlaceCategory.shopping);
      expect(
        byName('temp', 'Some Pin').category,
        PlaceCategory.sightseeing,
        reason: 'generic pin in an unnamed layer',
      );
    });

    test('score: written rating wins, then food colour, else null', () {
      // 評分: 4/5 on a green icon → 8, not 9.
      expect(byName('Food', 'Sample Tonkatsu').myScore, 8);
      // 評分: ?/5 on yellow → colour → 5.
      expect(byName('Food', 'Sample Noodles').myScore, 5);
      expect(byName('Food', 'Bean & Cup').myScore, 2); // red
      expect(byName('Food', 'Untried Diner').myScore, isNull); // grey
      // The colour applies to every category.
      expect(byName('Hotel', 'Sample Inn').myScore, 9);
      expect(byName('temp', 'Some Pin').myScore, 7); // Rating: 7/10
    });

    test('notes: plain text, entities decoded, empty fields dropped', () {
      final notes = byName('Food', 'Sample Tonkatsu').notes;
      expect(notes, 'Cat: カツ丼\n評分: 4/5\n預約制: Online\nLink/食評: Crispy & juicy.');
      expect(byName('Food', 'Sample Noodles').notes, contains('Price:'));
      expect(byName('Food', 'Sample Noodles').notes, isNot(contains('?/5')));
      expect(byName('Hotel', 'Sample Inn').notes, isEmpty);
    });

    test('photo urls from <img> and gx_media_links, deduped, http only', () {
      expect(byName('Food', 'Sample Tonkatsu').photoUrls, [
        'https://example.com/hostedimage/a1?fife=s16383',
        'https://example.com/hostedimage/a2?fife=s16383',
      ]);
      expect(byName('Hotel', 'Sample Inn').photoUrls, isEmpty);
    });

    test('toPlace carries the mapped fields', () {
      final place = byName(
        'Food',
        'Sample Tonkatsu',
      ).toPlace(id: 'x', mapTitle: doc.title);
      expect(place.sourcePlatform, SourcePlatform.googleMyMaps);
      expect(place.sourceHandle, doc.title);
      expect(place.myScore, 8);
      expect(place.myNotes, startsWith('Cat:'));
      expect(place.restaurantType, isNull);
      expect(place.areaLabel, isEmpty);
    });

    test('parses in a background isolate (compute)', () async {
      final xml = File('test/fixtures/my_maps_sample.kml').readAsStringSync();
      final parsed = await compute(parseMyMapsKml, xml);
      expect(parsed.placeCount, 9);
      expect(
        parsed.folders.first.placemarks.first.location.longitude,
        139.7671,
      );
    });

    test('rejects non-KML', () {
      expect(() => parseMyMapsKml('<html></html>'), throwsFormatException);
      expect(() => parseMyMapsKml('not xml'), throwsFormatException);
    });
  });

  group('mapping helpers', () {
    test('myMapsCategory by icon in unnamed layers', () {
      expect(myMapsCategory('temp', 1577), PlaceCategory.restaurant);
      expect(myMapsCategory('Edit', 1602), PlaceCategory.stay);
      expect(myMapsCategory('Edit', 1535), PlaceCategory.sightseeing);
      expect(myMapsCategory('Edit', 1684), PlaceCategory.shopping);
      expect(myMapsCategory('Edit', 1534), PlaceCategory.cafe);
      expect(myMapsCategory('Edit', null), PlaceCategory.sightseeing);
      expect(myMapsCategory('Edit', 9999), PlaceCategory.sightseeing);
    });

    test('named layers ignore non-food icons', () {
      expect(myMapsCategory('Food', 1602), PlaceCategory.restaurant);
      expect(myMapsCategory('Food', 1517), PlaceCategory.cafe);
      expect(myMapsCategory('Hotel', 1577), PlaceCategory.stay);
      expect(myMapsCategory('Shopping', 1899), PlaceCategory.shopping);
    });

    test('myMapsScore converts and clamps', () {
      int? score(String notes, [String? colour]) =>
          myMapsScore(colour: colour, notes: notes);
      expect(score('評分: 2.5/5'), 5);
      expect(score('評分：3.8/5'), 8);
      expect(score('評分: 0/5'), 1);
      expect(score('Rating: 10/10'), 10);
      expect(score('評分: 7/5', '0F9D58'), 9, reason: 'out of range');
      expect(score('評分:  ？/5', 'FF5252'), 2);
      expect(score(''), isNull);
    });

    test('descriptionToNotes caps long text', () {
      final notes = descriptionToNotes('a' * 1500);
      expect(notes.length, maxNotesLength);
      expect(notes, endsWith('…'));
      expect(descriptionToNotes('&lt;b&gt; &#26481;&#x4EAC;'), '<b> 東京');
    });
  });
}
