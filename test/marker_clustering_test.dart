import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/widgets/marker_clustering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Place _place(String id, double lat, double lng) => Place(
  id: id,
  name: id,
  areaLabel: '',
  region: '',
  category: PlaceCategory.cafe,
  location: LatLng(lat, lng),
  descriptionEn: '',
  originalCaption: '',
  address: '',
  hours: '',
  sourceHandle: '',
  sourcePlatform: SourcePlatform.instagram,
);

MapCamera _camera({
  LatLng center = const LatLng(35.68, 139.76),
  double zoom = 12,
}) => MapCamera(
  crs: const Epsg3857(),
  center: center,
  zoom: zoom,
  rotation: 0,
  nonRotatedSize: const Size(400, 800),
);

/// Two Shinjuku places ~100m apart plus one in Shibuya.
final _places = [
  _place('a', 35.6900, 139.7000),
  _place('b', 35.6905, 139.7005),
  _place('c', 35.6580, 139.7016),
];

Set<Set<String>> _groups(List<PlaceCluster> clusters) => {
  for (final c in clusters) {for (final p in c.places) p.id},
};

void main() {
  test('nearby places cluster, distant ones stay single', () {
    final clusters = clusterPlaces(places: _places, camera: _camera());
    expect(_groups(clusters), {
      {'a', 'b'},
      {'c'},
    });
  });

  test('clusters are anchored to the world, not the screen: panning never '
      're-buckets them', () {
    final base = _groups(clusterPlaces(places: _places, camera: _camera()));
    for (final dLng in [0.001, 0.013, 0.027, 0.05, -0.031]) {
      final panned = _camera(center: LatLng(35.68, 139.76 + dLng));
      expect(_groups(clusterPlaces(places: _places, camera: panned)), base);
    }
  });

  test('clusterZoomBucket floors to half steps', () {
    expect(clusterZoomBucket(12.0), 12.0);
    expect(clusterZoomBucket(12.49), 12.0);
    expect(clusterZoomBucket(12.5), 12.5);
    expect(clusterZoomBucket(12.99), 12.5);
  });

  group('PlaceClusterCache', () {
    test('same places + same zoom bucket returns the identical list, even '
        'after a pan', () {
      final cache = PlaceClusterCache();
      final first = cache.clustersFor(_places, _camera());
      expect(identical(cache.clustersFor(_places, _camera()), first), isTrue);
      final panned = _camera(center: const LatLng(35.7, 139.8), zoom: 12.3);
      expect(identical(cache.clustersFor(_places, panned), first), isTrue);
    });

    test('a new places list or a new zoom bucket recomputes', () {
      final cache = PlaceClusterCache();
      final first = cache.clustersFor(_places, _camera());
      final copy = List.of(_places);
      final second = cache.clustersFor(copy, _camera());
      expect(identical(second, first), isFalse);
      final zoomed = cache.clustersFor(copy, _camera(zoom: 12.5));
      expect(identical(zoomed, second), isFalse);
    });

    test('cell keys are unique per clustering pass', () {
      final many = [
        for (var i = 0; i < 500; i++)
          _place('p$i', 35.5 + (i % 25) * 0.02, 139.5 + (i ~/ 25) * 0.02),
      ];
      final clusters = PlaceClusterCache().clustersFor(many, _camera());
      final keys = clusters.map((c) => c.cellKey).toSet();
      expect(keys.length, clusters.length);
      expect(clusters.expand((c) => c.places).length, many.length);
    });
  });
}
