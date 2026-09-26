import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/place.dart';

/// A group of one or more [Place]s occupying the same on-screen grid cell.
///
/// `places.length == 1` means "just a regular pin" — [isSingle]/[isCluster]
/// are the readable way to branch on that.
class PlaceCluster {
  const PlaceCluster({
    required this.places,
    required this.center,
    this.cellKey = '',
  });

  /// The places grouped into this cell. Never empty.
  final List<Place> places;

  /// Where to draw the cluster/pin — the centroid of [places] (or, for a
  /// single place, its exact location).
  final LatLng center;

  /// Identifies the grid cell ("zoom:x:y") this cluster came from — stable
  /// for as long as the zoom bucket is, so it makes a good widget key.
  final String cellKey;

  bool get isSingle => places.length == 1;
  bool get isCluster => places.length > 1;

  /// The category shared by every member, or null if the cluster is mixed.
  /// Used to pick a single representative emoji/colour for the badge.
  PlaceCategory? get sharedCategory {
    final first = places.first.category;
    return places.every((p) => p.category == first) ? first : null;
  }
}

/// The zoom level clustering is computed at: [zoom] floored to a half step.
/// Within one bucket the clusters don't change, so pans and small pinches
/// reuse the same result (see [PlaceClusterCache]); a cell is 60px at the
/// bucket's zoom, i.e. 60–85 on-screen px until the next half step.
double clusterZoomBucket(double zoom) => (zoom * 2).floorToDouble() / 2;

/// Groups [places] using the same default grid algorithm documented for
/// Google Maps clustering: markers are bucketed into a 60x60 (logical) pixel
/// grid, and any cell that ends up with two or more markers is rendered as a
/// single cluster badge.
///
/// The grid is anchored in *world* pixel space at [clusterZoomBucket] of the
/// camera's zoom (via [MapCamera.projectAtZoom]) rather than to the screen:
/// a screen-anchored grid re-bucketed every marker on every pan frame, so
/// clusters split and merged while the user merely dragged the map. A world
/// grid depends only on the zoom bucket, so the result is stable under
/// panning and can be memoized — see [PlaceClusterCache].
List<PlaceCluster> clusterPlaces({
  required List<Place> places,
  required MapCamera camera,
  double cellSize = 60,
}) {
  final zoom = clusterZoomBucket(camera.zoom);
  final buckets = <(int, int), List<Place>>{};
  for (final place in places) {
    final point = camera.projectAtZoom(place.location, zoom);
    final cell = ((point.dx / cellSize).floor(), (point.dy / cellSize).floor());
    buckets.putIfAbsent(cell, () => <Place>[]).add(place);
  }

  return [
    for (final MapEntry(key: (x, y), value: members) in buckets.entries)
      PlaceCluster(
        places: members,
        center: _centroid(members),
        cellKey: '$zoom:$x:$y',
      ),
  ];
}

/// Memoizes [clusterPlaces] on (identity of `places`, zoom bucket), so the
/// marker layer — rebuilt on every camera frame — only re-clusters when the
/// filtered list changes or the zoom crosses a half step, and otherwise
/// returns the *same* list instance (letting callers cache what they build
/// from it).
class PlaceClusterCache {
  List<Place>? _places;
  double? _zoomBucket;
  List<PlaceCluster>? _clusters;

  List<PlaceCluster> clustersFor(List<Place> places, MapCamera camera) {
    final bucket = clusterZoomBucket(camera.zoom);
    final cached = _clusters;
    if (cached != null && identical(places, _places) && bucket == _zoomBucket) {
      return cached;
    }
    _places = places;
    _zoomBucket = bucket;
    return _clusters = clusterPlaces(places: places, camera: camera);
  }
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
