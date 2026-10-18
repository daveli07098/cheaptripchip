// The account sheet: the app's one theme control (Appearance) and the guest
// caveat shown before signing in.
import 'package:cheaptripchip/data/board_store.dart';
import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/screens/account_sheet.dart';
import 'package:cheaptripchip/screens/home_shell.dart';
import 'package:cheaptripchip/theme/theme_controller.dart';
import 'package:cheaptripchip/theme/theme_toggle_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PlaceStore.instance.bindRepository(LocalPlaceRepository());
    BoardStore.instance.bindRepository(LocalBoardRepository());
    await Future<void>.delayed(Duration.zero);
  });

  // ThemeController is a singleton — don't leak a mode into other tests.
  tearDown(() => ThemeController.instance.value = ThemeMode.system);

  Future<void> openAccountSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HomeShell(showFirstRunPrompts: false)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, 'Saved'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
  }

  testWidgets('Appearance picks System / Light / Dark and persists it', (
    tester,
  ) async {
    await openAccountSheet(tester);
    expect(find.text('Appearance'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(ThemeController.instance.value, ThemeMode.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'dark');

    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(ThemeController.instance.value, ThemeMode.system);
  });

  testWidgets('no theme toggle in the app bar or the Filters drawer', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: HomeShell(showFirstRunPrompts: false)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, 'Saved'));
    await tester.pumpAndSettle();
    expect(find.byType(ThemeToggleButton), findsNothing);

    // The Saved tab's Filters drawer keeps "Re-scan food types" only.
    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).last);
    scaffold.openDrawer();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Re-scan food types'),
      200,
      scrollable: find.descendant(
        of: find.byType(Drawer),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Re-scan food types'), findsOneWidget);
    expect(find.byType(ThemeToggleButton), findsNothing);
  });

  testWidgets('guest caveat shows before sign-in', (tester) async {
    await openAccountSheet(tester);
    // Firebase isn't configured under test: the not-set-up state, which is
    // still signed out.
    expect(find.text(kGuestFindsCaveat), findsOneWidget);
  });
}
