import 'package:flutter/material.dart';

/// Circular avatar for a person: their photo from [photoUrl] when it loads,
/// otherwise the first letter of [name] ("?" when the name is blank).
///
/// The initial is always painted underneath, so a photo that 404s or times
/// out (revoked token, offline) simply leaves the initial showing instead of
/// a broken-image icon. Decorative — callers put the person's name in their
/// own Semantics/Text.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.photoUrl,
    required this.name,
    this.radius = 20,
  });

  final String? photoUrl;
  final String name;
  final double radius;

  /// First character of the trimmed [name], upper-cased; "?" when blank.
  static String initialOf(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = photoUrl;
    final hasPhoto = url != null && url.isNotEmpty;
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: radius,
        backgroundColor: scheme.primaryContainer,
        foregroundImage: hasPhoto ? NetworkImage(url) : null,
        onForegroundImageError: hasPhoto ? (_, _) {} : null,
        child: Text(
          initialOf(name),
          style: TextStyle(
            fontSize: radius * 0.85,
            fontWeight: FontWeight.w700,
            color: scheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}
