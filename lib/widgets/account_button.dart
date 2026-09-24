import 'package:flutter/material.dart';

import '../screens/account_sheet.dart';
import '../services/auth_service.dart';

/// Small circular affordance that opens [showAccountSheet]: the signed-in
/// user's Google avatar (falling back to their initial if the image fails
/// to load), or a generic person icon when signed out/guest.
///
/// Deliberately has no background/elevation of its own — callers that want
/// the "surface disc" treatment (e.g. the map screen's category-chip row,
/// which gives [ThemeToggleButton] that same look) wrap this in a
/// `Material(color: surface, shape: CircleBorder(), elevation: 2)`, matching
/// that sibling rather than duplicating the styling here.
class AccountButton extends StatelessWidget {
  const AccountButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppUser?>(
      valueListenable: AuthService.instance.user,
      builder: (context, user, _) {
        return Tooltip(
          message: 'Account',
          child: Semantics(
            button: true,
            label: 'Account',
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => showAccountSheet(context),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: _AccountGlyph(user: user),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The 40×40 avatar/icon shown inside [AccountButton]'s tap target.
class _AccountGlyph extends StatelessWidget {
  const _AccountGlyph({required this.user});

  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final photoUrl = user?.photoUrl;
    if (user != null && photoUrl != null && photoUrl.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          photoUrl,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          // Network avatars can 404/time out (revoked token, offline) —
          // fall back to an initial letter rather than a broken-image icon.
          errorBuilder: (context, error, stackTrace) =>
              _InitialAvatar(user: user!, scheme: scheme),
        ),
      );
    }
    if (user != null) return _InitialAvatar(user: user!, scheme: scheme);
    return CircleAvatar(
      radius: 20,
      backgroundColor: scheme.surfaceContainerHighest,
      child: Icon(Icons.person_outline, color: scheme.onSurfaceVariant),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.user, required this.scheme});

  final AppUser user;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final name = user.displayName?.trim();
    final email = user.email?.trim();
    final source = (name != null && name.isNotEmpty)
        ? name
        : (email != null && email.isNotEmpty ? email : '?');
    return CircleAvatar(
      radius: 20,
      backgroundColor: scheme.primary,
      child: Text(
        source[0].toUpperCase(),
        style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w700),
      ),
    );
  }
}
