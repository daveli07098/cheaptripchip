import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/place.dart';

/// A group of one or more [Place]s occupying the same on-screen grid cell.
///
/// `places.length == 1` means "just a regular pin" — [isSingle]/[isCluster]
/// are the readable way to branch on that.
class PlaceCluster {
  const PlaceCluster({required this.places, required this.center});

  /// The places grouped into this cell. Never empty.
  final List<Place> places;

  /// Where to draw the cluster/pin — the centroid of [places] (or, for a
  /// single place, its exact location).
  final LatLng center;

  bool get isSingle => places.length == 1;
  bool get isCluster => places.length > 1;

  /// The category shared by every member, or null if the cluster is mixed.
  /// Used to pick a single representative emoji/colour for the badge.
  PlaceCategory? get sharedCategory {
    final first = places.first.category;
    return places.every((p) => p.category == first) ? first : null;
  }
}

/// Groups [places] using the same default grid algorithm documented for
/// Google Maps clustering: markers are bucketed into a 60x60 (logical) pixel
/// grid at the map's *current* on-screen projection, and any cell that ends
/// up with two or more markers is rendered as a single cluster badge.
///
/// Because bucketing happens in screen space (via [MapCamera.latLngToScreenOffset])
/// rather than lat/lng space, the 60x60 cell size stays visually correct at
/// every zoom level — callers should recompute this whenever the camera
/// (pan/zoom/rotate) changes, which happens automatically for any widget
/// that reads [MapCamera.of] during build (see `_ClusterMarkerLayer` in
/// map_screen.dart).
List<PlaceCluster> clusterPlaces({
  required List<Place> places,
  required MapCamera camera,
  double cellSize = 60,
}) {
  final buckets = <String, List<Place>>{};
  for (final place in places) {
    final screenPoint = camera.latLngToScreenOffset(place.location);
    final cellX = (screenPoint.dx / cellSize).floor();
    final cellY = (screenPoint.dy / cellSize).floor();
    buckets.putIfAbsent('$cellX:$cellY', () => <Place>[]).add(place);
  }

  return [
    for (final members in buckets.values)
      PlaceCluster(places: members, center: _centroid(members)),
  ];
}

/// Simple arithmetic-mean centroid. Members of one 60x60px cell are always
/// close together on screen, so this is visually indistinguishable from a
/// more precise (e.g. projected-space) centroid but far cheaper to compute.
LatLng _centroid(List<Place> members) {
  if (members.length == 1) return members.first.location;
  var lat = 0.0;
  var lng = 0.0;
  for (final member in members) {
    lat += member.location.latitude;
    lng += member.location.longitude;
  }
  return LatLng(lat / members.length, lng / members.length);
}
