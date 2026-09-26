import 'package:flutter/material.dart';

import '../data/map_filter.dart';
import '../data/place_filter_controller.dart';
import '../services/area_resolver.dart';
import 'accessible_emoji.dart';

/// The active filters as removable chips — "❤️ Favourites · 3 ✕",
/// "🍜 Ramen · 5 ✕", "🇭🇰 Mong Kok, Hong Kong · 2 ✕", one per picked board
/// — plus "Clear all" once two or more are on. Shown under the search pill
/// on both the map and the Saved tab. Counts are over ALL places, same as
/// the drawer (see [MapPlaceIndex.counts]), so they stay stable while the
/// user types. Renders nothing when no filter is active.
class ActiveFilterChips extends StatelessWidget {
  const ActiveFilterChips({
    super.key,
    required this.filters,
    required this.index,
    required this.boardIndex,
    this.padding = EdgeInsets.zero,
  });

  final PlaceFilterController filters;
  final MapPlaceIndex index;
  final BoardIndex boardIndex;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final filter = filters.filter;
    if (!filter.hasActiveFilters) return const SizedBox.shrink();
    final category = filter.category;
    final type = filter.restaurantType;
    final city = filter.city;
    final areas = index.areas;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: padding,
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (filter.favoritesOnly)
              _FilterChip(
                leading: const AccessibleEmoji(
                  emoji: '❤️',
                  label: 'Favourites',
                ),
                label: 'Favourites · ${index.favoriteCount}',
                clearLabel: 'Clear favourites filter',
                onClear: () => filters.setFavoritesOnly(false),
              ),
            if (category != null)
              _FilterChip(
                leading: AccessibleEmoji(
                  emoji: type?.emoji ?? category.emoji,
                  label: type?.labelEn ?? category.labelEn,
                ),
                label:
                    '${type?.labelEn ?? category.labelEn} · '
                    '${type != null ? (index.restaurantTypeCounts[type] ?? 0) : (index.counts[category] ?? 0)}',
                clearLabel: 'Clear category filter',
                onClear: () => filters.setCategory(null),
              ),
            if (city != null)
              _FilterChip(
                leading: AreaFlag(
                  countryCode: areas.countryCodeOf(city),
                  size: 14,
                ),
                label:
                    '${_areaLabel(city, filter.district)} · '
                    '${areas.countOf(city, filter.district)}',
                clearLabel: 'Clear area filter',
                onClear: () => filters.setArea(null, null),
              ),
            for (final key in filter.boards)
              if (boardIndex.byKey(key) case final board?)
                _FilterChip(
                  leading: AccessibleEmoji(emoji: board.emoji, label: 'Board'),
                  label: '${board.name} · ${boardIndex.countOf(key)}',
                  clearLabel: 'Clear board filter ${board.name}',
                  onClear: () => filters.removeBoard(key),
                ),
            if (filter.activeCount >= 2)
              _ClearAllChip(onClear: filters.clearFilters),
          ],
        ),
      ),
    );
  }
}

String _areaLabel(String city, String? district) => city.isEmpty
    ? 'Unknown area'
    : (district == null ? city : '$district, $city');

/// One active filter: [leading] glyph + "[label]" (the caller includes the
/// count) + a ✕ with a 44dp hit area that clears just this filter.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.leading,
    required this.label,
    required this.clearLabel,
    required this.onClear,
  });

  final Widget leading;
  final String label;

  /// Screen-reader name of the ✕, e.g. "Clear area filter".
  final String clearLabel;
  final VoidCallback onClear;

  static const double _height = 44;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(_height / 2),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: _height,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 12),
            leading,
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ),
            Semantics(
              button: true,
              label: clearLabel,
              child: InkWell(
                onTap: onClear,
                child: const SizedBox.square(
                  dimension: _height,
                  child: Icon(Icons.close, size: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Clear all" pill, same shape as [_FilterChip].
class _ClearAllChip extends StatelessWidget {
  const _ClearAllChip({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(_FilterChip._height / 2),
      clipBehavior: Clip.antiAlias,
      child: TextButton(
        onPressed: onClear,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, _FilterChip._height),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text('Clear all'),
      ),
    );
  }
}

/// A flag for [countryCode] (an [AccessibleEmoji], per the emoji rule), or
/// a pin icon when the country is unknown.
class AreaFlag extends StatelessWidget {
  const AreaFlag({super.key, required this.countryCode, required this.size});

  final String countryCode;
  final double size;

  @override
  Widget build(BuildContext context) {
    final flag = flagEmoji(countryCode);
    if (flag.isEmpty) return Icon(Icons.place_outlined, size: size + 4);
    return AccessibleEmoji(
      emoji: flag,
      label: 'Country: $countryCode',
      fontSize: size,
    );
  }
}
