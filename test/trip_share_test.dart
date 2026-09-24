import 'dart:convert';

import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/services/trip_share.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Place _place({
  String id = 'gogo-ikebukuro',
  String name = '五感 (Gogo)',
  String areaLabel = '池袋',
  String region = 'Tokyo, Japan',
  PlaceCategory category = PlaceCategory.cafe,
  LatLng location = const LatLng(35.7295, 139.7109),
  String descriptionEn = 'A quiet kissaten known for seasonal fruit parfaits.',
  String address = '3-1-1 Nishi-Ikebukuro, Toshima City, Tokyo',
  String sourceHandle = '@rame.nbon',
  SourcePlatform sourcePlatform = SourcePlatform.tiktok,
}) {
  return Place(
    id: id,
    name: name,
    areaLabel: areaLabel,
    region: region,
    category: category,
    location: location,
    descriptionEn: descriptionEn,
    originalCaption: 'original caption — dropped on export',
    address: address,
    hours: '11:00–19:00, closed Tuesdays',
    sourceHandle: sourceHandle,
    sourcePlatform: sourcePlatform,
    rating: 4.7,
    reviewCount: 85,
    photoUrls: const ['https://example.com/photo1.jpg'],
    isFavorite: true,
  );
}

void main() {
  group('App link round-trip', () {
    test('preserves place fields and issues fresh ids', () {
      final original = _place();
      final bundle = TripBundle(title: 'Tokyo Trip', places: [original]);

      final link = TripShare.toAppLink(bundle);
      expect(link.scheme, TripShare.scheme);
      expect(link.host, TripShare.host);
      expect(link.queryParameters['v'], '1');

      final decoded = TripShare.fromAppLink(link);
      expect(decoded, isNotNull);
      expect(decoded!.title, 'Tokyo Trip');
      expect(decoded.places, hasLength(1));

      final place = decoded.places.single;
      expect(place.id, isNot(original.id));
      expect(place.id, isNotEmpty);
      expect(place.name, original.name);
      expect(
        place.location.latitude,
        closeTo(original.location.latitude, 1e-9),
      );
      expect(
        place.location.longitude,
        closeTo(original.location.longitude, 1e-9),
      );
      expect(place.category, original.category);
      expect(place.address, original.address);
      expect(place.areaLabel, original.areaLabel);
      expect(place.region, original.region);
      expect(place.descriptionEn, original.descriptionEn);
      expect(place.sourceHandle, original.sourceHandle);
      expect(place.sourcePlatform, original.sourcePlatform);

      // Dropped fields fall back to defaults rather than surviving.
      expect(place.originalCaption, isEmpty);
      expect(place.hours, isEmpty);
      expect(place.photoUrls, isEmpty);
      expect(place.isFavorite, isFalse);
    });

    test('two places in the same bundle get distinct fresh ids', () {
      final bundle = TripBundle(
        title: 'Two Spots',
        places: [
          _place(id: 'a', name: 'Spot A'),
          _place(id: 'b', name: 'Spot B'),
        ],
      );

      final decoded = TripShare.fromAppLink(TripShare.toAppLink(bundle))!;
      expect(decoded.places, hasLength(2));
      expect(decoded.places[0].id, isNot(decoded.places[1].id));
    });

    test(
      'minimal place (empty optionals) round-trips without the omitted keys',
      () {
        const place = Place(
          id: 'bare',
          name: 'Unnamed Spot',
          areaLabel: '',
          region: '',
          category: PlaceCategory.sightseeing,
          location: LatLng(0, 0),
          descriptionEn: '',
          originalCaption: '',
          address: '',
          hours: '',
          sourceHandle: '',
          sourcePlatform: SourcePlatform.instagram,
        );
        final bundle = TripBundle(title: 'Bare', places: [place]);

        final decoded = TripShare.fromAppLink(TripShare.toAppLink(bundle))!;
        final decodedPlace = decoded.places.single;
        expect(decodedPlace.name, 'Unnamed Spot');
        expect(decodedPlace.address, isEmpty);
        expect(decodedPlace.areaLabel, isEmpty);
        expect(decodedPlace.region, isEmpty);
        expect(decodedPlace.descriptionEn, isEmpty);
        expect(decodedPlace.sourceHandle, isEmpty);
        expect(decodedPlace.sourcePlatform, SourcePlatform.instagram);
      },
    );
  });

  group('fromText', () {
    test('extracts a link surrounded by other text', () {
      final bundle = TripBundle(title: 'Chat Share', places: [_place()]);
      final link = TripShare.toAppLink(bundle);
      final message =
          'hey check out this trip! $link\n— sent from CheapTripChip';

      final decoded = TripShare.fromText(message);
      expect(decoded, isNotNull);
      expect(decoded!.title, 'Chat Share');
      expect(decoded.places, hasLength(1));
    });

    test('returns null when no link is present', () {
      expect(
        TripShare.fromText('just some regular text, no link here'),
        isNull,
      );
    });
  });

  group('corrupt or foreign links', () {
    test('wrong scheme returns null', () {
      final uri = Uri.parse('https://import?v=1&d=abcd');
      expect(TripShare.fromAppLink(uri), isNull);
    });

    test('wrong host returns null', () {
      final uri = Uri.parse('cheaptripchip://export?v=1&d=abcd');
      expect(TripShare.fromAppLink(uri), isNull);
    });

    test('unsupported version returns null', () {
      final bundle = TripBundle(title: 'X', places: [_place()]);
      final link = TripShare.toAppLink(bundle);
      final tampered = link.replace(
        queryParameters: {...link.queryParameters, 'v': '2'},
      );
      expect(TripShare.fromAppLink(tampered), isNull);
    });

    test('missing payload returns null', () {
      final uri = Uri.parse('cheaptripchip://import?v=1');
      expect(TripShare.fromAppLink(uri), isNull);
    });

    test('garbage payload returns null, never throws', () {
      final uri = Uri.parse('cheaptripchip://import?v=1&d=not-valid-base64!!!');
      expect(() => TripShare.fromAppLink(uri), returnsNormally);
      expect(TripShare.fromAppLink(uri), isNull);
    });

    test('valid base64url of non-gzip bytes returns null', () {
      final payload = base64Url
          .encode(utf8.encode('this is plain text, not gzip'))
          .replaceAll('=', '');
      final uri = Uri.parse('cheaptripchip://import?v=1&d=$payload');
      expect(() => TripShare.fromAppLink(uri), returnsNormally);
      expect(TripShare.fromAppLink(uri), isNull);
    });
  });

  group('file JSON round-trip', () {
    test('valid file round-trips title and places', () {
      final bundle = TripBundle(
        title: 'Osaka Weekend',
        places: [
          _place(),
          _place(id: 'b', name: 'Second Spot'),
        ],
      );

      final fileJson = TripShare.toFileJson(bundle);
      expect(fileJson, contains('"format": "cheaptripchip.trip"'));
      expect(fileJson, contains('"version": 1'));

      final decoded = TripShare.fromFileJson(fileJson);
      expect(decoded, isNotNull);
      expect(decoded!.title, 'Osaka Weekend');
      expect(decoded.places, hasLength(2));
      expect(decoded.places[0].name, _place().name);
      expect(decoded.places[1].name, 'Second Spot');
      expect(decoded.places[0].id, isNot('gogo-ikebukuro'));
    });

    test('invalid JSON returns null', () {
      expect(TripShare.fromFileJson('not json at all'), isNull);
    });

    test('wrong format tag returns null', () {
      expect(
        TripShare.fromFileJson(
          '{"format": "some.other.format", "version": 1, "title": "X", "places": []}',
        ),
        isNull,
      );
    });

    test('wrong version returns null', () {
      expect(
        TripShare.fromFileJson(
          '{"format": "cheaptripchip.trip", "version": 2, "title": "X", "places": []}',
        ),
        isNull,
      );
    });

    test('missing places array returns null', () {
      expect(
        TripShare.fromFileJson(
          '{"format": "cheaptripchip.trip", "version": 1, "title": "X"}',
        ),
        isNull,
      );
    });

    test('places without numeric coordinates are dropped', () {
      final decoded = TripShare.fromFileJson(
        '{"format": "cheaptripchip.trip", "version": 1, "title": "X", '
        '"places": [{"name": "No coords"}, '
        '{"name": "Bad", "lat": "35.6", "lng": 139.7}, '
        '{"name": "Good", "lat": 35.6, "lng": 139.7}]}',
      );
      expect(decoded, isNotNull);
      expect(decoded!.places.map((p) => p.name), ['Good']);
    });

    test('fileName slugifies the title', () {
      final bundle = TripBundle(title: 'Tokyo & Osaka Trip!', places: const []);
      expect(TripShare.fileName(bundle), 'tokyo-osaka-trip.cheaptrip.json');
    });

    test('fileName falls back for a title with no alphanumerics', () {
      final bundle = TripBundle(title: '★★★', places: const []);
      expect(TripShare.fileName(bundle), 'trip.cheaptrip.json');
    });
  });

  group('KML export', () {
    test('escapes special characters in name, note, and address', () {
      final place = _place(
        name: 'Fish & Chips "The Best" <Shop>',
        descriptionEn: "Tom's favourite spot — cheap & cheerful",
        address: '5 O\'Brien St',
      );
      final bundle = TripBundle(title: "Dave's Picks", places: [place]);

      final kml = TripShare.toKml(bundle);

      expect(kml, contains('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(kml, contains('<kml xmlns="http://www.opengis.net/kml/2.2">'));
      expect(kml, contains('Dave&apos;s Picks'));
      expect(
        kml,
        contains('Fish &amp; Chips &quot;The Best&quot; &lt;Shop&gt;'),
      );
      expect(kml, contains('Tom&apos;s favourite spot'));
      expect(kml, contains('cheap &amp; cheerful'));
      expect(kml, contains('5 O&apos;Brien St'));
      expect(kml, isNot(contains('<Shop>')));
      expect(kml, isNot(contains('"The Best"')));

      // Category emoji is folded into the placemark name.
      expect(kml, contains(PlaceCategory.cafe.emoji));
    });

    test('coordinates are lng,lat,0 order', () {
      final place = _place(location: const LatLng(35.7295, 139.7109));
      final bundle = TripBundle(title: 'Coords', places: [place]);

      final kml = TripShare.toKml(bundle);
      expect(kml, contains('<coordinates>139.7109,35.7295,0</coordinates>'));
    });

    test('kmlFileName slugifies the title', () {
      final bundle = TripBundle(title: 'Tokyo Trip', places: const []);
      expect(TripShare.kmlFileName(bundle), 'tokyo-trip.kml');
    });
  });

  group('Google Maps URLs', () {
    test('googleMapsPlaceUrl searches name + address', () {
      final url = TripShare.googleMapsPlaceUrl(_place());
      expect(url.host, 'www.google.com');
      expect(url.path, '/maps/search/');
      expect(
        url.queryParameters['query'],
        '五感 (Gogo), 3-1-1 Nishi-Ikebukuro, Toshima City, Tokyo',
      );
    });

    test('googleMapsQuery falls back to area and region without address', () {
      expect(
        _place(address: '').googleMapsQuery,
        '五感 (Gogo), 池袋, Tokyo, Japan',
      );
      expect(
        _place(address: '', areaLabel: '', region: '').googleMapsQuery,
        '五感 (Gogo)',
      );
    });

    test('googleMapsQuery falls back to coordinates without a name', () {
      final place = _place(
        name: '  ',
        location: const LatLng(35.7295, 139.7109),
      );
      expect(place.googleMapsQuery, '35.7295,139.7109');
    });

    test('googleMapsRouteUrl returns null for an empty list', () {
      expect(TripShare.googleMapsRouteUrl(const []), isNull);
    });

    test('googleMapsRouteUrl for a single place is the place URL', () {
      final place = _place(location: const LatLng(35.7295, 139.7109));
      final route = TripShare.googleMapsRouteUrl([place]);
      expect(route, TripShare.googleMapsPlaceUrl(place));
    });

    test('googleMapsRouteUrl sets origin, destination, and waypoints', () {
      final places = [
        _place(id: 'a', name: 'A', address: 'Addr A'),
        _place(id: 'b', name: 'B|x', address: 'Addr B'),
        _place(id: 'c', name: 'C', address: 'Addr C'),
      ];
      final route = TripShare.googleMapsRouteUrl(places)!;
      expect(route.queryParameters['origin'], 'A, Addr A');
      expect(route.queryParameters['destination'], 'C, Addr C');
      // A `|` inside a name would split the waypoint list, so it's stripped.
      expect(route.queryParameters['waypoints'], 'B x, Addr B');
      expect(route.queryParameters['travelmode'], 'walking');
    });

    test('googleMapsRouteUrl caps waypoints at the Google Maps limit', () {
      // 12 places -> origin + 9 waypoints (the max) + destination = 11 used,
      // 1 dropped.
      final places = List.generate(
        12,
        (i) => _place(id: 'p$i', name: 'P$i', address: ''),
      );
      final route = TripShare.googleMapsRouteUrl(places)!;
      final waypoints = route.queryParameters['waypoints']!.split('|');
      expect(waypoints, hasLength(TripShare.maxRouteWaypoints));
      expect(route.queryParameters['origin'], 'P0, 池袋, Tokyo, Japan');
      // Point index 10 is the destination (11th of the first 11 points);
      // point 11 was dropped by the cap.
      expect(route.queryParameters['destination'], 'P10, 池袋, Tokyo, Japan');
      expect(waypoints, isNot(contains('P11, 池袋, Tokyo, Japan')));
    });
  });

  group('linkFits', () {
    test('a small bundle fits within maxLinkLength', () {
      final bundle = TripBundle(title: 'Small Trip', places: [_place()]);
      expect(TripShare.linkFits(bundle), isTrue);
    });

    test('a large bundle does not fit within maxLinkLength', () {
      final places = List.generate(
        400,
        (i) => _place(
          id: 'place-$i',
          name: 'A Fairly Long Place Name Number $i With Extra Words',
          location: LatLng(i.toDouble(), i.toDouble()),
          descriptionEn:
              'A long, verbose description repeated to pad out the payload '
              'so the encoded link comfortably exceeds the maximum length '
              'for place number $i.',
        ),
      );
      final bundle = TripBundle(title: 'Huge Trip', places: places);
      expect(TripShare.linkFits(bundle), isFalse);
    });
  });
}
