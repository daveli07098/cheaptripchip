import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Small "Version 1.0.0 (1) · a9b04b2" line for checking which build is on
/// the device. The commit comes from `--dart-define=GIT_SHA=...` at build
/// time and is omitted when not passed.
class AppVersionLabel extends StatelessWidget {
  const AppVersionLabel({super.key});

  static const _gitSha = String.fromEnvironment('GIT_SHA');
  static const _buildTime = String.fromEnvironment('BUILD_TIME');

  static Future<String> describe() async {
    final info = await PackageInfo.fromPlatform();
    return [
      'Version ${info.version} (${info.buildNumber})',
      if (_gitSha.isNotEmpty) _gitSha,
      if (_buildTime.isNotEmpty) _buildTime,
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: describe(),
      builder: (context, snap) {
        final text = snap.data ?? (snap.hasError ? 'Version unknown' : '');
        return SelectableText(
          text,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        );
      },
    );
  }
}
