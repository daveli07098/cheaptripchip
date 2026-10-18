import 'package:flutter/material.dart';

import '../data/place_filter_controller.dart';

/// The temporary "✨ AI results · N ✕" chip plus the answer's one-line
/// explanation, shown on the map and the Saved tab while
/// [PlaceFilterController.aiResult] is set. ✕ clears the results and the
/// question ([PlaceFilterController.clearAiResults]). Renders nothing
/// otherwise.
class AiResultsChip extends StatelessWidget {
  const AiResultsChip({
    super.key,
    required this.filters,
    this.padding = EdgeInsets.zero,
  });

  final PlaceFilterController filters;
  final EdgeInsetsGeometry padding;

  static const double _height = 44;

  @override
  Widget build(BuildContext context) {
    final result = filters.aiResult;
    if (result == null || !filters.filter.hasAiResults) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final count = result.placeIds.length;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: padding,
        child: Material(
          color: scheme.surface,
          elevation: 1,
          borderRadius: BorderRadius.circular(_height / 2),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI results · $count',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                        Text(
                          result.explanation,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Clear AI results',
                  child: InkWell(
                    onTap: filters.clearAiResults,
                    child: const SizedBox.square(
                      dimension: _height,
                      child: Icon(Icons.close, size: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
