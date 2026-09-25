import 'dart:convert';
import 'dart:io';

import 'package:cheaptripchip/models/place_area.dart';
import 'package:cheaptripchip/services/area_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real Nominatim `/reverse?format=jsonv2&zoom=14&accept-language=en`
/// responses, captured once into test/fixtures/reverse_geocode/.
PlaceArea? _fixture(String name) => areaFromNominatim(
  jsonDecode(
        File('test/fixtures/reverse_geocode/$name.json').readAsStringSync(),
      )
      as Map<String, dynamic>,
);

void main() {
  group('areaFromNominatim', () {
    const expected = {
      // Tokyo 23 wards: `city` is the ward, no prefecture → city "Tokyo".
      'shibuya': PlaceArea(
        city: 'Tokyo',
        district: 'Shibuya',
        countryCode: 'JP',
      ),
      'shinjuku': PlaceArea(
        city: 'Tokyo',
        district: 'Shinjuku',
        countryCode: 'JP',
      ),
      // Ward level, not the Ginza quarter.
      'ginza': PlaceArea(city: 'Tokyo', district: 'Chuo', countryCode: 'JP'),
      // "Chūō Ward" → "Chuo": macron folded, suffix stripped.
      'osaka_namba': PlaceArea(
        city: 'Osaka',
        district: 'Chuo',
        countryCode: 'JP',
      ),
      'kyoto_gion': PlaceArea(
        city: 'Kyoto',
        district: 'Higashiyama',
        countryCode: 'JP',
      ),
      // Only `town` + `quarter` outside a city.
      'hakone': PlaceArea(
        city: 'Hakone',
        district: 'Tonosawa',
        countryCode: 'JP',
      ),
      // Nominatim says country_code "cn"; ISO3166-2-lvl3 CN-HK → HK.
      'mong_kok': PlaceArea(
        city: 'Hong Kong',
        district: 'Mong Kok',
        countryCode: 'HK',
      ),
      // city_district "Hong Kong Island" is skipped for the suburb.
      'causeway_bay': PlaceArea(
        city: 'Hong Kong',
        district: 'Wan Chai',
        countryCode: 'HK',
      ),
      'taipei_xinyi': PlaceArea(
        city: 'Taipei',
        district: 'Xinyi',
        countryCode: 'TW',
      ),
      // Korea: the gu (borough), "-gu" kept.
      'seoul_myeongdong': PlaceArea(
        city: 'Seoul',
        district: 'Jung-gu',
        countryCode: 'KR',
      ),
      'bangkok_siam': PlaceArea(
        city: 'Bangkok',
        district: 'Pathum Wan',
        countryCode: 'TH',
      ),
      // borough "Central Region" is skipped for the planning area.
      'singapore_bugis': PlaceArea(
        city: 'Singapore',
        district: 'Rochor',
        countryCode: 'SG',
      ),
    };

    for (final entry in expected.entries) {
      test(entry.key, () {
        expect(_fixture(entry.key), entry.value);
      });
    }

    test('error / address-less responses map to null', () {
      expect(areaFromNominatim({'error': 'Unable to geocode'}), isNull);
      expect(areaFromNominatim({'address': <String, dynamic>{}}), isNull);
    });

    test('Tokyo municipality outside the 23 wards stays under Tokyo', () {
      expect(
        areaFromNominatim({
          'address': {
            'quarter': 'Kichijoji Honcho',
            'city': 'Musashino',
            'ISO3166-2-lvl4': 'JP-13',
            'country_code': 'jp',
          },
        }),
        const PlaceArea(
          city: 'Tokyo',
          district: 'Musashino',
          countryCode: 'JP',
        ),
      );
    });

    test('Macau is recognised from ISO3166-2-lvl3', () {
      expect(
        areaFromNominatim({
          'address': {
            'suburb': 'Sé',
            'city': 'Macau',
            'ISO3166-2-lvl3': 'CN-MO',
            'country_code': 'cn',
          },
        })?.countryCode,
        'MO',
      );
    });
  });

  group('cleanAreaName', () {
    test('folds macrons and strips administrative suffixes', () {
      expect(cleanAreaName('Chūō Ward'), 'Chuo');
      expect(cleanAreaName('Shibuya-ku'), 'Shibuya');
      expect(cleanAreaName('Xinyi District'), 'Xinyi');
      expect(cleanAreaName('Pathum Wan Subdistrict'), 'Pathum Wan');
      expect(cleanAreaName('Kōtō'), 'Koto');
      expect(cleanAreaName('Jung-gu'), 'Jung-gu');
    });
  });

  test('flagEmoji', () {
    expect(flagEmoji('JP'), '🇯🇵');
    expect(flagEmoji('hk'), '🇭🇰');
    expect(flagEmoji(''), '');
    expect(flagEmoji('JPN'), '');
  });
}
