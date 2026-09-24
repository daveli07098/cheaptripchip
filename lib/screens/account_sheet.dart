import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Modal bottom sheet with the three [AuthService] states: Firebase not
/// configured, signed out, and signed in. See [_AccountSheetBody].
Future<void> showAccountSheet(BuildContext context) {
  // Captured from the *caller's* context, before the sheet exists, so the
  // sign-in error SnackBar still has a valid ScaffoldMessenger to show on
  // after the sheet (and its own context) has closed.
  final messenger = ScaffoldMessenger.of(context);
  return showModalBottomSheet(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _AccountSheetBody(messenger: messenger),
  );
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: ValueListenableBuilder<AppUser?>(
          valueListenable: AuthService.instance.user,
          builder: (context, user, _) {
            if (!AuthService.instance.isConfigured) return _unconfigured();
            if (user == null) return _signedOut(context);
            return _signedIn(context, user);
          },
        ),
      ),
    );
  }

  Widget _unconfigured() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text(
          "Sign in isn't set up yet",
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 6),
        Text(
          "Firebase isn't configured in this build. "
          'See docs/firebase-setup.md.',
          style: TextStyle(height: 1.4),
        ),
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
            _Avatar(user: user, radius: 24),
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
        Text(
          'Guest finds stay on this device.',
          style: TextStyle(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
            fontSize: 12.5,
          ),
        ),
      ],
    );
  }
}

/// 2×[radius] avatar matching [AccountButton]'s photo/initial-fallback
/// logic, sized for the signed-in state's header row.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.user, required this.radius});

  final AppUser user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final photoUrl = user.photoUrl;
    final size = radius * 2;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          photoUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _initial(scheme, radius),
        ),
      );
    }
    return _initial(scheme, radius);
  }

  Widget _initial(ColorScheme scheme, double radius) {
    final name = user.displayName?.trim();
    final email = user.email?.trim();
    final source = (name != null && name.isNotEmpty)
        ? name
        : (email != null && email.isNotEmpty ? email : '?');
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primary,
      child: Text(
        source[0].toUpperCase(),
        style: TextStyle(
          color: scheme.onPrimary,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}
