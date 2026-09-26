import 'package:flutter/material.dart';

import '../screens/account_sheet.dart';
import '../services/auth_service.dart';
import 'user_avatar.dart';

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
                // 48×48 tap target (Material minimum) around the 40dp
                // avatar.
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(child: _AccountGlyph(user: user)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The 40×40 avatar/icon shown inside [AccountButton]'s 48×48 tap target:
/// the user's [UserAvatar], or a generic person icon for a guest.
class _AccountGlyph extends StatelessWidget {
  const _AccountGlyph({required this.user});

  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final user = this.user;
    if (user != null) {
      return UserAvatar(photoUrl: user.photoUrl, name: accountNameOf(user));
    }
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: 20,
      backgroundColor: scheme.surfaceContainerHighest,
      child: Icon(Icons.person_outline, color: scheme.onSurfaceVariant),
    );
  }
}
