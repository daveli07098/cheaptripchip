import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'data/board_store.dart';
import 'data/photo_store.dart';
import 'data/place_store.dart';
import 'firebase_options.dart';
import 'screens/home_shell.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.instance.load();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase not configured, running as guest: $e');
  }
  AuthService.instance.start();
  AuthService.instance.user.addListener(_bindStores);
  _bindStores();
  runApp(const CheapTripChipApp());
}

/// Rebinds [PlaceStore], [BoardStore] and [PhotoStore] to the current user
/// (or to local, guest-mode repos when signed out / unconfigured) whenever
/// auth state changes.
void _bindStores() {
  final user = AuthService.instance.user.value;
  PlaceStore.instance.bind(user);
  BoardStore.instance.bind(user);
  PhotoStore.instance.bind(user);
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
          home: const HomeShell(),
        );
      },
    );
  }
}
