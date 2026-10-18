// "Map unavailable" banner: shows after a run of tile errors with no
// successful tile, hides when tiles load again, and doesn't flap.
import 'package:cheaptripchip/widgets/map_tile_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late TileHealthMonitor monitor;

  setUp(() {
    now = DateTime(2026, 1, 1, 12);
    monitor = TileHealthMonitor(clock: () => now);
  });
  tearDown(() => monitor.dispose());

  void errors(int n, {Duration gap = const Duration(milliseconds: 100)}) {
    for (var i = 0; i < n; i++) {
      now = now.add(gap);
      monitor.recordError();
    }
  }

  group('TileHealthMonitor', () {
    test('shows only once the threshold is reached', () {
      errors(5);
      expect(monitor.unavailable.value, isFalse);
      errors(1);
      expect(monitor.unavailable.value, isTrue);
    });

    test('errors spread wider than the window never add up', () {
      errors(12, gap: const Duration(seconds: 3));
      expect(monitor.unavailable.value, isFalse);
    });

    test('a successful tile hides it and restarts the count', () {
      errors(6);
      now = now.add(const Duration(seconds: 1));
      monitor.recordSuccess(now);
      expect(monitor.unavailable.value, isFalse);
      expect(monitor.awaitingRecovery, isFalse);
      errors(5);
      expect(monitor.unavailable.value, isFalse);
    });

    test('a tile that loaded before the errors is not a recovery', () {
      final earlier = now;
      errors(6);
      monitor.recordSuccess(earlier);
      expect(monitor.unavailable.value, isTrue);
    });

    test('a success between errors keeps it hidden', () {
      errors(4);
      monitor.recordSuccess(now.add(const Duration(milliseconds: 1)));
      errors(4);
      expect(monitor.unavailable.value, isFalse);
    });

    test('dismissed stays hidden until tiles load again', () {
      errors(6);
      monitor.dismiss();
      errors(10);
      expect(monitor.unavailable.value, isFalse);
      monitor.recordSuccess(now.add(const Duration(milliseconds: 1)));
      errors(6);
      expect(monitor.unavailable.value, isTrue);
    });
  });

  testWidgets('MapTileBanner shows, dismisses, and hides on recovery', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MapTileBanner(monitor: monitor)),
      ),
    );
    expect(find.text(kMapUnavailableMessage), findsNothing);

    errors(6);
    await tester.pump();
    expect(find.text(kMapUnavailableMessage), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.text(kMapUnavailableMessage), findsNothing);

    monitor.recordSuccess(now.add(const Duration(milliseconds: 1)));
    errors(6);
    await tester.pump();
    expect(find.text(kMapUnavailableMessage), findsOneWidget);
    monitor.recordSuccess(now.add(const Duration(milliseconds: 1)));
    await tester.pump();
    expect(find.text(kMapUnavailableMessage), findsNothing);
  });
}
