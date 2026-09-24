import 'dart:typed_data';

import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/mock_data.dart';
import 'package:cheaptripchip/data/photo_repository.dart';
import 'package:cheaptripchip/data/photo_store.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory [PhotoRepository] that counts calls and can pretend to be a
/// billed backend ([loadIsCostly]) or fail writes.
class _FakePhotoRepository implements PhotoRepository {
  _FakePhotoRepository({this.loadIsCostly = false});

  final Map<String, Uint8List> photos = {};
  int loads = 0;
  bool failWrites = false;

  @override
  final bool loadIsCostly;

  @override
  Future<Uint8List?> load(String placeId) async {
    loads++;
    return photos[placeId];
  }

  @override
  Future<void> save(String placeId, Uint8List jpeg) async {
    if (failWrites) throw StateError('offline');
    photos[placeId] = jpeg;
  }

  @override
  Future<void> delete(String placeId) async {
    if (failWrites) throw StateError('offline');
    photos.remove(placeId);
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  final store = PhotoStore.instance;
  final placeId = MockData.places.first.id;
  final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2, 3]);

  setUp(() async {
    PlaceStore.instance.bindRepository(LocalPlaceRepository());
    await _settle();
  });

  test('photoFor lazily loads once and caches', () async {
    final repo = _FakePhotoRepository()..photos[placeId] = jpeg;
    store.bindRepository(repo);

    final photo = store.photoFor(placeId);
    expect(photo.value, isNull);
    await _settle();
    expect(photo.value, jpeg);
    expect(repo.loads, 1);

    store.photoFor(placeId);
    await _settle();
    expect(repo.loads, 1, reason: 'second photoFor hits the cache');
  });

  test('setPhoto notifies, persists and marks the place', () async {
    final repo = _FakePhotoRepository();
    store.bindRepository(repo);
    final photo = store.photoFor(placeId);
    await _settle();

    var notifications = 0;
    void listener() => notifications++;
    photo.addListener(listener);
    await store.setPhoto(placeId, jpeg);
    photo.removeListener(listener);

    expect(photo.value, jpeg);
    expect(notifications, 1);
    expect(repo.photos[placeId], jpeg);
    expect(PlaceStore.instance.byId(placeId).myPhotoAt, isNotNull);
  });

  test('removePhoto clears the photo and the place marker', () async {
    final repo = _FakePhotoRepository();
    store.bindRepository(repo);
    await store.setPhoto(placeId, jpeg);

    await store.removePhoto(placeId);

    expect(store.photoFor(placeId).value, isNull);
    expect(repo.photos, isEmpty);
    expect(PlaceStore.instance.byId(placeId).myPhotoAt, isNull);
  });

  test('failed write reverts the optimistic update and rethrows', () async {
    final repo = _FakePhotoRepository()..failWrites = true;
    store.bindRepository(repo);
    final photo = store.photoFor(placeId);
    await _settle();

    await expectLater(store.setPhoto(placeId, jpeg), throwsStateError);
    expect(photo.value, isNull);
    expect(PlaceStore.instance.byId(placeId).myPhotoAt, isNull);
  });

  test('rejects photos over the size limit', () async {
    store.bindRepository(_FakePhotoRepository());
    await expectLater(
      store.setPhoto(placeId, Uint8List(kMaxPhotoBytes + 1)),
      throwsA(isA<PhotoTooLargeException>()),
    );
  });

  test('costly repository skips the read for unmarked places', () async {
    final repo = _FakePhotoRepository(loadIsCostly: true)
      ..photos[placeId] = jpeg;
    store.bindRepository(repo);

    final photo = store.photoFor(placeId);
    await _settle();
    expect(repo.loads, 0, reason: 'no myPhotoAt marker → no billed read');
    expect(photo.value, isNull);

    await PlaceStore.instance.setPhotoMarker(
      placeId,
      DateTime.utc(2026, 9, 25),
    );
    store.photoFor(placeId);
    await _settle();
    expect(repo.loads, 1);
    expect(photo.value, jpeg);
  });

  test('rebinding clears the cache but keeps notifier identity', () async {
    final first = _FakePhotoRepository()..photos[placeId] = jpeg;
    store.bindRepository(first);
    final photo = store.photoFor(placeId);
    await _settle();
    expect(photo.value, jpeg);

    store.bindRepository(_FakePhotoRepository());
    expect(photo.value, isNull);
    expect(identical(store.photoFor(placeId), photo), isTrue);
  });
}
