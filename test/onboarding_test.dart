// First-run "How it works": shown once on first launch, re-openable from the
// account sheet, with the share step worded per platform.
import 'package:cheaptripchip/data/board_store.dart';
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/screens/home_shell.dart';
import 'package:cheaptripchip/widgets/onboarding_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sheetTitle = 'How cheaptripchip works';

void main() {
  group('onboardingSteps', () {
    test('always three steps: share in, lands on the map, boards', () {
      for (final isWeb in [false, true]) {
        for (final platform in TargetPlatform.values) {
          final steps = onboardingSteps(isWeb: isWeb, platform: platform);
          expect(steps, hasLength(3));
          expect(steps[1].title, 'It lands on the map');
          expect(steps[2].title, 'Group into boards & plan trips');
        }
      }
    });

    test('Android app: share straight into the app', () {
      final share = onboardingSteps(
        isWeb: false,
        platform: TargetPlatform.android,
      ).first;
      expect(share.body, contains('tap Share, then cheaptripchip'));
      expect(share.body, contains('screenshot'));
      expect(share.substeps, isEmpty);
    });

    test('iPhone web: Shortcut steps and the ?add= address to copy', () {
      final share = onboardingSteps(
        isWeb: true,
        platform: TargetPlatform.iOS,
      ).first;
      expect(share.body, contains('Shortcut'));
      expect(share.substeps, isNotEmpty);
      expect(share.substeps.join(' '), contains('Show in Share Sheet'));
      expect(share.copyText, 'https://cheaptripchip.vercel.app/?add=');
    });

    test('elsewhere: paste a link or add a screenshot', () {
      final share = onboardingSteps(
        isWeb: true,
        platform: TargetPlatform.macOS,
      ).first;
      expect(share.body, contains('paste'));
      expect(share.copyText, isNull);
    });
  });

  group('HomeShell first run', () {
    setUp(() async {
      PlaceStore.instance.bindRepository(LocalPlaceRepository());
      BoardStore.instance.bindRepository(LocalBoardRepository());
      await Future<void>.delayed(Duration.zero);
    });

    testWidgets('shows the sheet once, then never again', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const MaterialApp(home: HomeShell()));
      await tester.pumpAndSettle();
      expect(find.text(_sheetTitle), findsOneWidget);

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.text(_sheetTitle), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_seen'), isTrue);

      // A fresh launch with the same prefs.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(const MaterialApp(home: HomeShell()));
      await tester.pumpAndSettle();
      expect(find.text(_sheetTitle), findsNothing);
    });

    testWidgets('showFirstRunPrompts: false skips it', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const MaterialApp(home: HomeShell(showFirstRunPrompts: false)),
      );
      await tester.pumpAndSettle();
      expect(find.text(_sheetTitle), findsNothing);
    });

    testWidgets('re-opens from the account sheet ("How it works")', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'onboarding_seen': true});
      await tester.pumpWidget(const MaterialApp(home: HomeShell()));
      await tester.pumpAndSettle();
      expect(find.text(_sheetTitle), findsNothing);

      await tester.tap(find.widgetWithText(NavigationDestination, 'Saved'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('How it works'));
      await tester.pumpAndSettle();

      expect(find.text(_sheetTitle), findsOneWidget);
      // The account sheet closed in its favour.
      expect(find.text('Appearance'), findsNothing);
    });
  });
}
