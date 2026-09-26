import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/models/restaurant_type_detect.dart';
import 'package:cheaptripchip/services/restaurant_type_rescan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _udonShop = Place(
  id: 'udon-shop',
  name: 'Udon Shin',
  areaLabel: '',
  region: '',
  category: PlaceCategory.restaurant,
  location: LatLng(1, 1),
  descriptionEn: '',
  originalCaption: '',
  address: '',
  hours: '',
  sourceHandle: '',
  sourcePlatform: SourcePlatform.instagram,
  restaurantType: RestaurantType.other,
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PlaceStore.instance.bindRepository(LocalPlaceRepository());
    await PlaceStore.instance.loaded;
    await PlaceStore.instance.add(_udonShop);
    await Future<void>.delayed(Duration.zero);
  });

  test('runs once per detection version and account', () async {
    final store = PlaceStore.instance;

    expect(await rescanRestaurantTypesIfNeeded('guest'), greaterThan(0));
    expect(store.byId(_udonShop.id).restaurantType, RestaurantType.udonSoba);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getInt('restaurantTypeDetectionVersion.guest'),
      restaurantTypeDetectionVersion,
    );

    // Put a refinable type back: the recorded version skips the pass.
    await store.setRestaurantType(
      _udonShop.id,
      RestaurantType.other,
      manual: false,
    );
    await Future<void>.delayed(Duration.zero);
    expect(await rescanRestaurantTypesIfNeeded('guest'), 0);
    expect(store.byId(_udonShop.id).restaurantType, RestaurantType.other);

    // Another account's data set has its own marker.
    expect(await rescanRestaurantTypesIfNeeded('uid-1'), greaterThan(0));
    expect(store.byId(_udonShop.id).restaurantType, RestaurantType.udonSoba);
  });

  test('re-runs when an older detection version was recorded', () async {
    SharedPreferences.setMockInitialValues({
      'restaurantTypeDetectionVersion.guest':
          restaurantTypeDetectionVersion - 1,
    });
    expect(await rescanRestaurantTypesIfNeeded('guest'), greaterThan(0));
  });
}
