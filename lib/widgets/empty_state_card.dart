import 'package:flutter/material.dart';

/// The one empty-state layout, shared by Saved, Boards and the map's place
/// list: an icon, a title, an explanation and the primary actions (wrapping
/// onto a second line on a narrow phone).
class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actions = const [],
    this.padding = const EdgeInsets.all(32),
  });

  final IconData icon;
  final String title;
  final String body;

  /// Buttons, e.g. "Add a find" / "Import a trip" / "Create your first
  /// board". Empty for a purely informational state such as "No matches".
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 14),
            Semantics(
              header: true,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Body copy shared by the empty states: the three tabs are views of one set
/// of finds, so an empty Saved list means an empty map and vice versa.
const kSameFindsExplainer =
    'Map, Saved and Boards are three views of the same finds — '
    'save one and it shows up in all three.';
