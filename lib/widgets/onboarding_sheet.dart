import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

/// What an iPhone Shortcut opens to hand a post link to the web app — the
/// link, URL-encoded, goes right after it (see web_share_intake.dart).
const kShortcutAddUrl = 'https://cheaptripchip.vercel.app/?add=';

/// One step of the first-run "How it works" sheet.
@immutable
class OnboardingStep {
  const OnboardingStep({
    required this.icon,
    required this.title,
    required this.body,
    this.substeps = const [],
    this.copyText,
  });

  final IconData icon;
  final String title;
  final String body;

  /// Numbered sub-steps (the iPhone Shortcut setup).
  final List<String> substeps;

  /// Text offered with a "Copy" button (the Shortcut's URL).
  final String? copyText;
}

/// The three steps — share a post in, it lands on the map, group it into
/// boards — with the "share in" step worded for what this build can do:
/// the Android app receives shares; the iPhone web app needs a Shortcut;
/// the Android web app receives shares once installed; elsewhere it's paste
/// a link or add a screenshot. Pure, so each variant is unit-testable.
List<OnboardingStep> onboardingSteps({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  const pasteOrScreenshot =
      'Or tap Add a find and paste a post link, or add a screenshot.';
  final share = switch ((isWeb, platform)) {
    (false, TargetPlatform.android) => const OnboardingStep(
      icon: Icons.ios_share,
      title: 'Share a post into the app',
      body:
          'In Instagram or TikTok, tap Share, then cheaptripchip. '
          '$pasteOrScreenshot',
    ),
    (true, TargetPlatform.iOS) => const OnboardingStep(
      icon: Icons.ios_share,
      title: 'Share a post into the app',
      body:
          'On iPhone, add a Shortcut once, then share a post from Instagram '
          'or TikTok to it. $pasteOrScreenshot',
      substeps: [
        'Open the Shortcuts app and tap + to make a new shortcut.',
        'In its details (the i button), turn on "Show in Share Sheet".',
        'Add the action "URL Encode" with Shortcut Input.',
        'Add "Open URLs" with the address below, followed by the '
            'URL Encoded Text.',
        'In Instagram or TikTok, tap Share, then your shortcut.',
      ],
      copyText: kShortcutAddUrl,
    ),
    (true, TargetPlatform.android) => const OnboardingStep(
      icon: Icons.ios_share,
      title: 'Share a post into the app',
      body:
          'Install this web app (browser menu → Add to Home screen), then '
          'in Instagram or TikTok tap Share, then cheaptripchip. '
          '$pasteOrScreenshot',
    ),
    _ => const OnboardingStep(
      icon: Icons.add_link,
      title: 'Add a post',
      body:
          'Copy an Instagram or TikTok post link, tap Add a find and paste '
          'it — or add a screenshot.',
    ),
  };
  return [
    share,
    const OnboardingStep(
      icon: Icons.place_outlined,
      title: 'It lands on the map',
      body:
          'We read the post, find the place and pin it. Map, Saved and '
          'Boards are three views of the same finds.',
    ),
    const OnboardingStep(
      icon: Icons.dashboard_outlined,
      title: 'Group into boards & plan trips',
      body:
          'Collect finds into boards, then plan a day-by-day trip from a '
          'board.',
    ),
  ];
}

/// Remembers that the first-run sheet has been seen, under [_prefsKey].
abstract final class OnboardingPrefs {
  static const _prefsKey = 'onboarding_seen';

  /// Unreadable prefs count as seen: a welcome sheet that can't be
  /// dismissed for good would reappear on every launch.
  static Future<bool> seen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefsKey) ?? false;
    } catch (_) {
      return true;
    }
  }

  static Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, true);
    } catch (_) {
      // Shown again next launch — harmless.
    }
  }
}

/// Opens the "How it works" sheet (first launch, the empty states and the
/// account sheet). Marks it seen however it's closed.
Future<void> showOnboardingSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => OnboardingSheet(
      steps: onboardingSteps(isWeb: kIsWeb, platform: defaultTargetPlatform),
    ),
  );
  await OnboardingPrefs.markSeen();
}

/// The "How it works" sheet's content: a title, the numbered [steps] and a
/// "Got it" button.
class OnboardingSheet extends StatelessWidget {
  const OnboardingSheet({super.key, required this.steps});

  final List<OnboardingStep> steps;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: const Text(
                'How cheaptripchip works',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Save travel finds from your feed onto one map.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            for (final (i, step) in steps.indexed) ...[
              _StepTile(number: i + 1, step: step),
              const SizedBox(height: 14),
            ],
            const SizedBox(height: 4),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.coral,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                minimumSize: const Size(double.infinity, 48),
              ),
              child: const Text('Got it'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.number, required this.step});

  final int number;
  final OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurfaceVariant, height: 1.4);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppTheme.coral.withValues(alpha: 0.15),
          child: Icon(step.icon, size: 20, color: AppTheme.coral),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$number. ${step.title}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(step.body, style: muted),
              if (step.substeps.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final (i, substep) in step.substeps.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('${i + 1}) $substep', style: muted),
                  ),
              ],
              if (step.copyText case final text?) ...[
                const SizedBox(height: 6),
                _CopyField(text: text),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// [text] in a monospace box with a Copy button.
class _CopyField extends StatelessWidget {
  const _CopyField({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.maybeOf(context);
              await Clipboard.setData(ClipboardData(text: text));
              messenger?.showSnackBar(
                const SnackBar(content: Text('Address copied')),
              );
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }
}
