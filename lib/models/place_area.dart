/// Where a place is, at city → district granularity: the values
/// [PlaceStore.updateAreas] writes into [Place.region] ([city]),
/// [Place.areaLabel] ([district]) and [Place.countryCode].
class PlaceArea {
  const PlaceArea({
    required this.city,
    required this.district,
    required this.countryCode,
  });

  /// "Tokyo", "Hong Kong", "Taipei" — may be empty when unknown.
  final String city;

  /// "Shibuya", "Mong Kok", "Xinyi" — may be empty when unknown.
  final String district;

  /// ISO 3166-1 alpha-2, upper-case ("JP", "HK"); empty when unknown.
  final String countryCode;

  bool get isEmpty => city.isEmpty && district.isEmpty && countryCode.isEmpty;

  Map<String, dynamic> toJson() => {
    'c': city,
    'd': district,
    'cc': countryCode,
  };

  factory PlaceArea.fromJson(Map<String, dynamic> json) => PlaceArea(
    city: json['c'] is String ? json['c'] as String : '',
    district: json['d'] is String ? json['d'] as String : '',
    countryCode: json['cc'] is String ? json['cc'] as String : '',
  );

  @override
  bool operator ==(Object other) =>
      other is PlaceArea &&
      other.city == city &&
      other.district == district &&
      other.countryCode == countryCode;

  @override
  int get hashCode => Object.hash(city, district, countryCode);

  @override
  String toString() => 'PlaceArea($city, $district, $countryCode)';
}

/// English name for an ISO 3166-1 alpha-2 [countryCode] ("JP" → "Japan"),
/// for the common travel destinations; any other code is returned as-is
/// (upper-cased), and an empty code reads "Unknown country".
String countryName(String countryCode) {
  final code = countryCode.trim().toUpperCase();
  if (code.isEmpty) return 'Unknown country';
  return _countryNames[code] ?? code;
}

const Map<String, String> _countryNames = {
  'AE': 'United Arab Emirates',
  'AR': 'Argentina',
  'AT': 'Austria',
  'AU': 'Australia',
  'BE': 'Belgium',
  'BR': 'Brazil',
  'CA': 'Canada',
  'CH': 'Switzerland',
  'CN': 'China',
  'CZ': 'Czechia',
  'DE': 'Germany',
  'DK': 'Denmark',
  'EG': 'Egypt',
  'ES': 'Spain',
  'FI': 'Finland',
  'FR': 'France',
  'GB': 'United Kingdom',
  'GR': 'Greece',
  'HK': 'Hong Kong',
  'HR': 'Croatia',
  'HU': 'Hungary',
  'ID': 'Indonesia',
  'IE': 'Ireland',
  'IL': 'Israel',
  'IN': 'India',
  'IS': 'Iceland',
  'IT': 'Italy',
  'JP': 'Japan',
  'KH': 'Cambodia',
  'KR': 'South Korea',
  'LA': 'Laos',
  'LK': 'Sri Lanka',
  'MA': 'Morocco',
  'MO': 'Macau',
  'MV': 'Maldives',
  'MX': 'Mexico',
  'MY': 'Malaysia',
  'NL': 'Netherlands',
  'NO': 'Norway',
  'NP': 'Nepal',
  'NZ': 'New Zealand',
  'PE': 'Peru',
  'PH': 'Philippines',
  'PL': 'Poland',
  'PT': 'Portugal',
  'SE': 'Sweden',
  'SG': 'Singapore',
  'TH': 'Thailand',
  'TR': 'Türkiye',
  'TW': 'Taiwan',
  'US': 'United States',
  'VN': 'Vietnam',
  'ZA': 'South Africa',
};
