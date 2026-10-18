import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'data/board_store.dart';
import 'data/photo_store.dart';
import 'data/place_store.dart';
import 'data/shared_board_store.dart';
import 'firebase_options.dart';
import 'screens/home_shell.dart';
import 'services/area_resolver.dart';
import 'services/auth_service.dart';
import 'services/place_enricher.dart';
import 'services/restaurant_type_rescan.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'widgets/web_safe_area.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.instance.load();
  try {
    await Firebase.initializeApp(options: _firebaseOptions());
  } catch (e) {
    debugPrint('Firebase not configured, running as guest: $e');
  }
  AuthService.instance.start();
  AuthService.instance.user.addListener(_bindStores);
  _bindStores();
  // Reverse-geocodes city/district for places that lack them, in the
  // background once the app has been idle a few seconds (see AreaResolver).
  AreaResolver.instance.start();
  // Auto-fills AI place details (must-try, price, tags, translations) for
  // new and existing finds, throttled, in the background (see PlaceEnricher).
  PlaceEnricher.instance.start();
  runApp(const CheapTripChipApp());
}

/// On a deployed web build, serves Firebase's auth handler from the app's own
/// host (proxied to `<project>.firebaseapp.com/__/auth/*` by the rewrite in
/// web_deploy/vercel.json). Safari blocks the third-party storage the default
/// cross-domain handler needs, so without this Google sign-in silently fails
/// on iPhones. Local dev (localhost) keeps the default authDomain.
FirebaseOptions _firebaseOptions() {
  final options = DefaultFirebaseOptions.currentPlatform;
  if (!kIsWeb) return options;
  final host = Uri.base.host;
  if (host.isEmpty || host == 'localhost' || host == '127.0.0.1') {
    return options;
  }
  return options.copyWith(authDomain: host);
}

/// Rebinds [PlaceStore], [BoardStore] and [PhotoStore] to the current user
/// (or to local, guest-mode repos when signed out / unconfigured) whenever
/// auth state changes. [SharedBoardStore] is signed-in only (empty for
/// guests). Once the places arrive, refines stored restaurant types after a
/// detection-keyword update (see [rescanRestaurantTypesIfNeeded]).
void _bindStores() {
  final user = AuthService.instance.user.value;
  PlaceStore.instance.bind(user);
  unawaited(rescanRestaurantTypesIfNeeded(user?.uid ?? 'guest'));
  BoardStore.instance.bind(user);
  PhotoStore.instance.bind(user);
  SharedBoardStore.instance.bind(user);
}

class CheapTripChipApp extends StatelessWidget {
  const CheapTripChipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'CheapTripChip',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          // Above the Navigator, so bottom sheets and dialogs get the web
          // safe-area padding too, not just the home shell.
          builder: (context, child) => WebSafeArea(child: child!),
          home: const HomeShell(),
        );
      },
    );
  }
}
