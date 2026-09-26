// PlacePhoto's loading behaviour: the fallback shows under a photo that's
// still decoding (instead of a blank box), and an already-cached photo —
// what PlaceDetailSheet.precacheHeader warms — paints straight away.
import 'package:cheaptripchip/data/memory_photo_repository.dart';
import 'package:cheaptripchip/data/photo_store.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/widgets/place_photo.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const _url = 'https://example.com/photo.jpg';

const _place = Place(
  id: 'photo-test-1',
  name: 'Photo Spot',
  areaLabel: 'Shibuya',
  region: 'Tokyo',
  category: PlaceCategory.cafe,
  location: LatLng(35.6, 139.7),
  descriptionEn: '',
  originalCaption: '',
  address: '',
  hours: '',
  sourceHandle: '@x',
  sourcePlatform: SourcePlatform.instagram,
  photoUrls: [_url],
);

Widget _host({int? cacheWidth}) => MaterialApp(
  home: Center(
    child: SizedBox.square(
      dimension: 100,
      child: PlacePhoto(
        place: _place,
        cacheWidth: cacheWidth,
        fallback: const Text('fallback'),
      ),
    ),
  ),
);

void main() {
  setUp(() {
    PhotoStore.instance.bindRepository(MemoryPhotoRepository());
    imageCache.clear();
  });

  testWidgets('shows the fallback while the photo loads, image hidden', (
    tester,
  ) async {
    await tester.pumpWidget(_host(cacheWidth: 300));

    expect(find.text('fallback'), findsOneWidget);
    final fade = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(fade.opacity, 0);

    // The test HTTP client fails every request: the fallback stays.
    await tester.pumpAndSettle();
    expect(find.text('fallback'), findsOneWidget);
  });

  test('precache and the widget resolve the same cache key', () {
    expect(
      PlacePhoto.providerFor(_place, cacheWidth: 1080),
      PlacePhoto.providerFor(_place, cacheWidth: 1080),
    );
    expect(
      PlacePhoto.providerFor(_place, cacheWidth: 1080),
      isNot(PlacePhoto.providerFor(_place, cacheWidth: 216)),
    );
    expect(PlacePhoto.providerFor(_place), const NetworkImage(_url));
  });

  testWidgets('an already-cached photo paints at once, no fallback', (
    tester,
  ) async {
    final image = await tester.runAsync(() => createTestImage());
    imageCache.putIfAbsent(
      const NetworkImage(_url),
      () => OneFrameImageStreamCompleter(
        SynchronousFuture(ImageInfo(image: image!)),
      ),
    );

    await tester.pumpWidget(_host());

    expect(find.text('fallback'), findsNothing);
    expect(find.byType(AnimatedOpacity), findsNothing);
    expect(find.byType(RawImage), findsOneWidget);
  });
}
