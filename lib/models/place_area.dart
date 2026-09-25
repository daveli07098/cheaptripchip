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
