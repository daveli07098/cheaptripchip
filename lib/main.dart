import 'package:flutter/material.dart';

import 'screens/home_shell.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const CheapTripChipApp());
}

class CheapTripChipApp extends StatelessWidget {
  const CheapTripChipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CheapTripChip',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const HomeShell(),
    );
  }
}
