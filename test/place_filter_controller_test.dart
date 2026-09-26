import 'package:cheaptripchip/data/map_filter.dart';
import 'package:cheaptripchip/data/place_filter_controller.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PlaceFilterController filters;
  var notified = 0;

  setUp(() {
    filters = PlaceFilterController();
    notified = 0;
    filters.addListener(() => notified++);
  });
  tearDown(() => filters.dispose());

  test('search text is mirrored into the filter query', () {
    filters.search.text = 'ramen';
    expect(filters.filter.query, 'ramen');
    expect(notified, 1);
    filters.search.text = 'ramen';
    expect(notified, 1, reason: 'same text, no change');
  });

  test('category picks clear the sub-type; a sub-type implies Restaurant', () {
    filters.setRestaurantType(RestaurantType.ramen);
    expect(filters.filter.category, PlaceCategory.restaurant);
    expect(filters.filter.restaurantType, RestaurantType.ramen);
    filters.setCategory(PlaceCategory.cafe);
    expect(filters.filter.restaurantType, isNull);
  });

  test('clearFilters drops every chip filter but keeps the search', () {
    filters.search.text = 'tokyo';
    filters
      ..setFavoritesOnly(true)
      ..setCategory(PlaceCategory.cafe)
      ..setArea('Tokyo', 'Shibuya')
      ..toggleBoard('b1');
    expect(filters.filter.activeCount, 4);
    filters.clearFilters();
    expect(filters.filter, const MapFilter(query: 'tokyo'));
  });

  test('showOnlyBoard replaces every filter and the search', () {
    filters.search.text = 'x';
    filters
      ..setFavoritesOnly(true)
      ..setCategory(PlaceCategory.cafe);
    notified = 0;
    filters.showOnlyBoard('b2');
    expect(filters.filter, const MapFilter(boards: {'b2'}));
    expect(filters.search.text, isEmpty);
    expect(notified, 1);
  });

  test('toggleBoard / retainBoards', () {
    filters
      ..toggleBoard('a')
      ..toggleBoard('b');
    expect(filters.filter.boards, {'a', 'b'});
    filters.toggleBoard('a');
    expect(filters.filter.boards, {'b'});
    filters.retainBoards((key) => key != 'b');
    expect(filters.filter.boards, isEmpty);
  });
}
