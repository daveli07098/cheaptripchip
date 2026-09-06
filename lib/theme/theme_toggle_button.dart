import 'package:flutter/material.dart';
import 'theme_controller.dart';

/// Icon button that lets the user override the system theme. Cycles
/// system → light → dark → system; icon + tooltip reflect the current mode.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, mode, _) {
        final (icon, tooltip) = switch (mode) {
          ThemeMode.system => (Icons.brightness_auto, 'Theme: System'),
          ThemeMode.light => (Icons.light_mode, 'Theme: Light'),
          ThemeMode.dark => (Icons.dark_mode, 'Theme: Dark'),
        };
        return IconButton(
          icon: Icon(icon),
          tooltip: tooltip,
          onPressed: ThemeController.instance.toggle,
        );
      },
    );
  }
}
