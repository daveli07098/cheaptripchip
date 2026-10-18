import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/app_version_label.dart';
import '../widgets/onboarding_sheet.dart';
import '../widgets/user_avatar.dart';

/// Modal bottom sheet with the three [AuthService] states: Firebase not
/// configured, signed out, and signed in — plus, in every state, the app's
/// Appearance (theme) setting and "How it works". See [_AccountSheetBody].
Future<void> showAccountSheet(BuildContext context) {
  // Captured from the *caller's* context, before the sheet exists, so the
  // sign-in error SnackBar still has a valid ScaffoldMessenger to show on
  // after the sheet (and its own context) has closed.
  final messenger = ScaffoldMessenger.of(context);
  return showModalBottomSheet(
    context: context,
    // Taller than the default 9/16 cap when needed; the body scrolls.
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _AccountSheetBody(messenger: messenger),
  );
}

/// Shown in every auth state, so a guest knows before signing in that their
/// finds won't follow them into the account (see CLAUDE.md, guest mode).
const kGuestFindsCaveat =
    "Guest finds stay on this device and aren't uploaded when you sign in.";

/// The name an account's avatar initial comes from (the sheet's header and
/// AccountButton): the display name, else the email, else empty (→ "?").
String accountNameOf(AppUser user) {
  final name = user.displayName?.trim() ?? '';
  return name.isNotEmpty ? name : (user.email?.trim() ?? '');
}

class _AccountSheetBody extends StatefulWidget {
  const _AccountSheetBody({required this.messenger});

  final ScaffoldMessengerState messenger;

  @override
  State<_AccountSheetBody> createState() => _AccountSheetBodyState();
}

class _AccountSheetBodyState extends State<_AccountSheetBody> {
  bool _busy = false;

  Future<void> _signIn() async {
    setState(() => _busy = true);
    try {
      await AuthService.instance.signInWithGoogle();
      if (!mounted) return;
      Navigator.pop(context);
    } on AuthException catch (e) {
      widget.messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await AuthService.instance.signOut();
      if (!mounted) return;
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<AppUser?>(
              valueListenable: AuthService.instance.user,
              builder: (context, user, _) {
                if (!AuthService.instance.isConfigured) {
                  return _unconfigured(context);
                }
                if (user == null) return _signedOut(context);
                return _signedIn(context, user);
              },
            ),
            const Divider(height: 32),
            const _AppearancePicker(),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.help_outline),
              title: const Text('How it works'),
              onTap: _showHowItWorks,
            ),
            const SizedBox(height: 8),
            // Which build is installed — for checking a device has the latest.
            const AppVersionLabel(),
          ],
        ),
      ),
    );
  }

  /// Closes this sheet and opens the onboarding sheet in its place — on the
  /// navigator, since this sheet's context is gone once it's popped.
  void _showHowItWorks() {
    final navigator = Navigator.of(context);
    navigator.pop();
    showOnboardingSheet(navigator.context);
  }

  Widget _caveat(BuildContext context) => Text(
    kGuestFindsCaveat,
    style: TextStyle(
      color: Theme.of(
        context,
      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
      fontSize: 12.5,
      height: 1.4,
    ),
  );

  Widget _unconfigured(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Sign in isn't set up yet",
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          "Firebase isn't configured in this build. "
          'See docs/firebase-setup.md.',
          style: TextStyle(height: 1.4),
        ),
        const SizedBox(height: 10),
        _caveat(context),
      ],
    );
  }

  Widget _signedOut(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // FilledButton.icon already exposes button role + its `label` Text
        // as the accessible name — no extra Semantics wrapper needed.
        FilledButton.icon(
          onPressed: _busy ? null : _signIn,
          icon: _busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                )
              : const Icon(Icons.login, size: 18),
          label: Text(_busy ? 'Signing in…' : 'Sign in with Google'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.coral,
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Sync your finds and boards across devices.',
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        // Said before sign-in, not just after: signing in starts an empty
        // account rather than uploading what's saved here.
        _caveat(context),
      ],
    );
  }

  Widget _signedIn(BuildContext context, AppUser user) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            UserAvatar(
              photoUrl: user.photoUrl,
              name: accountNameOf(user),
              radius: 24,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName ?? 'Google account',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (user.email != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      user.email!,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        // Same as the sign-in button above — no extra Semantics wrapper.
        OutlinedButton(
          onPressed: _busy ? null : _signOut,
          style: OutlinedButton.styleFrom(
            foregroundColor: scheme.onSurface,
            side: BorderSide(color: scheme.outline),
            minimumSize: const Size(double.infinity, 48),
          ),
          child: _busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.onSurface,
                  ),
                )
              : const Text('Sign out'),
        ),
        const SizedBox(height: 10),
        _caveat(context),
      ],
    );
  }
}

/// "Appearance": System / Light / Dark — the app's one theme control.
/// Writes through [ThemeController.set], which persists the choice.
class _AppearancePicker extends StatelessWidget {
  const _AppearancePicker();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Appearance',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeController.instance,
          builder: (context, mode, _) => SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto),
                  label: Text('System'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode),
                  label: Text('Light'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode),
                  label: Text('Dark'),
                ),
              ],
              selected: {mode},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  ThemeController.instance.set(selection.single),
            ),
          ),
        ),
      ],
    );
  }
}
