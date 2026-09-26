import 'package:flutter/material.dart';

/// An emoji glyph with a real accessible name (WCAG 1.4.1): screen readers
/// announce [label] instead of the glyph's CLDR name, which is hidden from
/// the semantics tree. The one place the app's "wrap every emoji in a
/// Semantics label" rule is implemented.
class AccessibleEmoji extends StatelessWidget {
  const AccessibleEmoji({
    super.key,
    required this.emoji,
    required this.label,
    this.fontSize = 14,
    this.height,
    this.selected,
  });

  final String emoji;
  final String label;
  final double fontSize;

  /// Line height; `1` keeps the glyph vertically centred inside a circle or
  /// tile (Flutter's emoji centering is unreliable, flutter/flutter#119623).
  final double? height;

  /// Forwarded to [Semantics.selected] (e.g. the selected map pin).
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      selected: selected,
      child: ExcludeSemantics(
        child: Text(
          emoji,
          style: TextStyle(fontSize: fontSize, height: height),
        ),
      ),
    );
  }
}
