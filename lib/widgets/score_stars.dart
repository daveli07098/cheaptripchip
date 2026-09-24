import 'package:flutter/material.dart';

/// Amber/gold used for the user's own rating — the same gold as the detail
/// sheet's award chip, tuned to read clearly on both the dark and light
/// scaffold backgrounds (see AppTheme).
const Color _scoreGold = Color(0xFFFFC857);

/// Interactive 5-star / 10-point "my review" rating picker.
///
/// Each star represents two points: tapping the left half of star `i` sets
/// [value] to `2i - 1`, the right half to `2i`. Tapping the half that
/// already matches the current [value] clears it (calls [onChanged] with
/// `null`) — there's no separate "clear" control.
///
/// Pure/stateless: it renders [value] and reports taps via [onChanged];
/// callers own persistence (PlaceDetailSheet calls
/// `PlaceStore.updateReview` on every change).
class ScoreStars extends StatelessWidget {
  const ScoreStars({super.key, required this.value, required this.onChanged});

  /// Current score, 1..10. Null means "not rated".
  final int? value;

  final ValueChanged<int?> onChanged;

  static const _starCount = 5;

  /// >=48dp per star so each half still clears the recommended minimum
  /// touch-target size even though it's only occupying half the star.
  static const _starTapSize = 48.0;
  static const _starIconSize = 30.0;

  bool get _canIncrease => value == null || value! < 10;
  bool get _canDecrease => value != null;

  static String _describe(int? score) =>
      score == null ? 'Not rated' : '$score out of 10';

  @override
  Widget build(BuildContext context) {
    final label = value == null ? 'Tap to rate' : '$value/10';
    return Semantics(
      // One container node for the whole picker — the per-half
      // GestureDetectors below are excluded from the a11y tree via
      // `excludeFromSemantics`, so a screen reader announces a single
      // "My score, 9 out of 10" control with increase/decrease actions
      // instead of five ambiguous "star" nodes. `increasedValue`/
      // `decreasedValue` are required alongside `value` whenever the
      // matching action is enabled (Semantics asserts on this).
      container: true,
      label: 'My score',
      value: _describe(value),
      increasedValue: _canIncrease
          ? _describe(value == null ? 1 : value! + 1)
          : '',
      decreasedValue: _canDecrease
          ? _describe(value! <= 1 ? null : value! - 1)
          : '',
      onIncrease: _canIncrease ? _increase : null,
      onDecrease: _canDecrease ? _decrease : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= _starCount; i++)
            _Star(star: i, value: value, onTap: _handleTap),
          const SizedBox(width: 8),
          // The container Semantics node above already carries the score as
          // its `value` — exclude this Text from the tree so it doesn't get
          // merged in too (a screen reader would otherwise read the label
          // twice, e.g. "My score 9/10, 9 out of 10").
          ExcludeSemantics(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleTap(int mark) => onChanged(value == mark ? null : mark);

  void _increase() {
    final next = value == null ? 1 : value! + 1;
    onChanged(next > 10 ? 10 : next);
  }

  void _decrease() {
    if (value == null) return;
    final next = value! - 1;
    onChanged(next < 1 ? null : next);
  }
}

class _Star extends StatelessWidget {
  const _Star({required this.star, required this.value, required this.onTap});

  final int star;
  final int? value;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final full = 2 * star;
    final half = full - 1;
    final icon = value == null
        ? Icons.star_border
        : value! >= full
        ? Icons.star
        : value! == half
        ? Icons.star_half
        : Icons.star_border;

    return GestureDetector(
      excludeFromSemantics: true,
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        final isLeftHalf =
            details.localPosition.dx < ScoreStars._starTapSize / 2;
        onTap(isLeftHalf ? half : full);
      },
      child: SizedBox(
        width: ScoreStars._starTapSize,
        height: ScoreStars._starTapSize,
        child: Icon(icon, size: ScoreStars._starIconSize, color: _scoreGold),
      ),
    );
  }
}

/// Compact "★ 9/10" badge shown on [PlaceCard] and [PlaceListSheet] rows
/// once a place has [Place.myScore] set — small enough not to crowd the
/// existing rating/category metadata. An `Icon` stands in for the star
/// glyph (matches the repo convention of not relying on emoji glyphs for
/// meaning — see PlaceCard's `_MatchBadge`).
class ScoreBadge extends StatelessWidget {
  const ScoreBadge({super.key, required this.score});

  /// The place's `myScore`, 1..10. Callers only build this when non-null.
  final int score;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Your score $score out of 10',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: _scoreGold.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star, size: 12, color: _scoreGold),
              const SizedBox(width: 3),
              Text(
                '$score/10',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _scoreGold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
