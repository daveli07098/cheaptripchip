import 'package:flutter/material.dart';

import '../data/map_filter.dart';
import '../data/place_filter_controller.dart';
import '../data/place_store.dart';
import '../models/place.dart';
import '../services/area_resolver.dart';
import '../theme/app_theme.dart';
import '../theme/theme_toggle_button.dart';
import 'accessible_emoji.dart';
import 'filter_chips.dart';

/// The Filters drawer, shared by the map and the Saved tab (both edit the
/// same [PlaceFilterController]). Sections, top to bottom: Favourites,
/// Categories ("All" plus every category present, with counts; the
/// Restaurant row expands to cuisine sub-types — see
/// [_RestaurantCategoryTile]), then two collapsible sections, Boards
/// (multi-select toggles that keep the drawer open) and Areas (country →
/// city → district, each level A–Z and collapsible), and Settings (food-type
/// rescan + theme) at the bottom.
///
/// Single-choice picks apply, call [onPicked] and close the drawer; board
/// toggles call [onBoardsChanged] and keep it open. Screen-specific
/// follow-ups (the map's camera fit) hang off those callbacks.
class FilterDrawer extends StatelessWidget {
  const FilterDrawer({
    super.key,
    required this.filters,
    required this.index,
    required this.boardIndex,
    this.onPicked,
    this.onBoardsChanged,
  });

  final PlaceFilterController filters;

  /// Counts over ALL places (see [MapPlaceIndex]).
  final MapPlaceIndex index;
  final BoardIndex boardIndex;

  /// After a single-choice pick, before the drawer closes. [always] is true
  /// for area picks (the user asked for a place — the map always flies
  /// there), false for favourites/category picks.
  final void Function({required bool always})? onPicked;

  /// After a board toggle (the drawer stays open).
  final VoidCallback? onBoardsChanged;

  void _pick(BuildContext context, VoidCallback change, {bool always = false}) {
    change();
    onPicked?.call(always: always);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: filters,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final filter = filters.filter;
    final selected = filter.category;
    final selectedType = filter.restaurantType;
    final selectedCity = filter.city;
    final selectedArea = filter.district;
    final selectedBoards = filter.boards;
    final total = index.all.length;
    final areas = index.areas;
    // Boards with places on the map, plus any still picked (so it can be
    // unticked even after its places are gone).
    final boards = [
      for (final board in boardIndex.boards)
        if (boardIndex.countOf(board.key) > 0 ||
            selectedBoards.contains(board.key))
          board,
    ];
    // One country: open it straight away; several: collapsed, except the
    // one holding the picked city.
    final expandCountries = areas.countries.length == 1;
    void onSelectArea(String? city, String? district) => _pick(
      context,
      () => filters.setArea(city, district),
      always: city != null,
    );

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
              child: Text(
                'Filters',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const _SectionLabel('Favourites'),
            _CategoryTile(
              leading: const AccessibleEmoji(
                emoji: '❤️',
                label: 'Favourites',
                fontSize: 22,
              ),
              label: 'Favourites',
              count: index.favoriteCount,
              color: AppTheme.coral,
              selected: filter.favoritesOnly,
              subtitle: index.favoriteCount == 0 && !filter.favoritesOnly
                  ? 'Tap ♡ on a place to add it'
                  : null,
              onTap: index.favoriteCount == 0 && !filter.favoritesOnly
                  ? null
                  : () => _pick(
                      context,
                      () => filters.setFavoritesOnly(!filter.favoritesOnly),
                    ),
            ),
            const _SectionLabel('Categories'),
            _CategoryTile(
              leading: const Icon(Icons.apps),
              label: 'All',
              count: total,
              color: AppTheme.coral,
              selected: selected == null,
              onTap: () => _pick(context, () => filters.setCategory(null)),
            ),
            for (final entry in index.counts.entries)
              if (entry.key == PlaceCategory.restaurant)
                _RestaurantCategoryTile(
                  count: entry.value,
                  typeCounts: index.restaurantTypeCounts,
                  selected: selected == PlaceCategory.restaurant,
                  selectedType: selectedType,
                  onSelectCategory: () => _pick(
                    context,
                    () => filters.setCategory(PlaceCategory.restaurant),
                  ),
                  onSelectType: (t) =>
                      _pick(context, () => filters.setRestaurantType(t)),
                )
              else
                _CategoryTile(
                  leading: AccessibleEmoji(
                    emoji: entry.key.emoji,
                    label: entry.key.labelEn,
                    fontSize: 22,
                  ),
                  label: entry.key.labelEn,
                  count: entry.value,
                  color: AppTheme.categoryColor(entry.key, brightness),
                  selected: selected == entry.key,
                  onTap: () =>
                      _pick(context, () => filters.setCategory(entry.key)),
                ),
            if (boards.isNotEmpty) ...[
              const Divider(height: 24),
              _SectionHeader(
                title: 'Boards',
                expanded: filters.boardsExpanded,
                onToggle: filters.toggleBoardsExpanded,
              ),
              if (filters.boardsExpanded) ...[
                _CategoryTile(
                  leading: const Icon(Icons.dashboard_outlined),
                  label: 'All boards',
                  count: total,
                  color: AppTheme.coral,
                  selected: selectedBoards.isEmpty,
                  onTap: () {
                    if (selectedBoards.isEmpty) return;
                    filters.clearBoards();
                    onBoardsChanged?.call();
                  },
                ),
                for (final board in boards)
                  _BoardFilterTile(
                    board: board,
                    count: boardIndex.countOf(board.key),
                    selected: selectedBoards.contains(board.key),
                    onToggle: () {
                      filters.toggleBoard(board.key);
                      onBoardsChanged?.call();
                    },
                  ),
              ],
            ],
            const Divider(height: 24),
            _SectionHeader(
              title: 'Areas',
              expanded: filters.areasExpanded,
              onToggle: filters.toggleAreasExpanded,
            ),
            const _AreaProgressLine(),
            if (filters.areasExpanded) ...[
              _CategoryTile(
                leading: const Icon(Icons.public),
                label: 'All areas',
                count: total,
                color: AppTheme.coral,
                selected: selectedCity == null,
                onTap: () => onSelectArea(null, null),
              ),
              for (final country in areas.countries)
                _CountryTile(
                  key: ValueKey('country:${country.code}'),
                  country: country,
                  initiallyExpanded:
                      expandCountries ||
                      country.cities.any((c) => c.city == selectedCity),
                  selectedCity: selectedCity,
                  selectedArea: selectedArea,
                  onSelectArea: onSelectArea,
                ),
              if (areas.unknownCount > 0)
                _CategoryTile(
                  leading: const Icon(Icons.help_outline),
                  label: 'Unknown area',
                  count: areas.unknownCount,
                  color: AppTheme.coral,
                  selected: selectedCity == '',
                  onTap: () => onSelectArea('', null),
                ),
            ],
            const Divider(height: 24),
            const _SectionLabel('Settings'),
            // Manual trigger for the rescan that also runs automatically
            // after a detection-keyword update (restaurant_type_rescan.dart).
            ListTile(
              leading: const Icon(Icons.manage_search),
              title: const Text('Re-scan food types'),
              onTap: () async {
                // Captured before the await so the result still shows if
                // the drawer is closed mid-scan.
                final messenger = ScaffoldMessenger.of(context);
                final changed = await PlaceStore.instance
                    .rescanRestaurantTypes();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      changed == 0
                          ? 'Food types are up to date'
                          : 'Updated the food type of $changed '
                                '${changed == 1 ? 'place' : 'places'}',
                    ),
                  ),
                );
              },
            ),
            // Moved here from the map's floating row (commit ec3b355) so the
            // search pill can stay a single, uninterrupted control.
            const ListTile(
              leading: Icon(Icons.brightness_6_outlined),
              title: Text('Theme'),
              trailing: ThemeToggleButton(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Non-collapsible drawer section label ("Favourites", "Categories",
/// "Settings").
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
        child: Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// "1,650" — thousands separators without pulling in package:intl.
String _formatCount(int n) {
  final digits = '$n';
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Collapsible drawer section title ("Boards", "Areas"): the whole row
/// toggles, with a chevron and the expanded state exposed to screen readers.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.expanded,
    required this.onToggle,
  });

  final String title;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      expanded: expanded,
      label: title,
      excludeSemantics: true,
      child: InkWell(
        onTap: onToggle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Icon(expanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A board in the drawer's Boards section: emoji + name + places on the
/// map, with a checkbox — tapping toggles it in the (multi-select) filter.
class _BoardFilterTile extends StatelessWidget {
  const _BoardFilterTile({
    required this.board,
    required this.count,
    required this.selected,
    required this.onToggle,
  });

  final BoardRef board;
  final int count;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: MergeSemantics(
        child: Semantics(
          checked: selected,
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            selected: selected,
            selectedTileColor: AppTheme.coral.withValues(alpha: 0.16),
            selectedColor: scheme.onSurface,
            leading: SizedBox(
              width: 28,
              child: Center(
                child: AccessibleEmoji(
                  emoji: board.emoji,
                  label: board.shared ? 'Shared board' : 'Board',
                  fontSize: 22,
                ),
              ),
            ),
            title: Text(
              board.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            subtitle: board.shared ? const Text('Shared') : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$count'),
                const SizedBox(width: 8),
                ExcludeSemantics(
                  child: Icon(
                    selected ? Icons.check_box : Icons.check_box_outline_blank,
                    color: selected ? AppTheme.coral : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            onTap: onToggle,
          ),
        ),
      ),
    );
  }
}

/// Country row in the drawer's Areas section: flag + name + count; the
/// whole row expands/collapses its cities (A–Z, each a [_CityTile]). There
/// is no country-wide filter — pick a city or district inside. Re-expands
/// when a city inside becomes the picked area.
class _CountryTile extends StatefulWidget {
  const _CountryTile({
    super.key,
    required this.country,
    required this.initiallyExpanded,
    required this.selectedCity,
    required this.selectedArea,
    required this.onSelectArea,
  });

  final CountryGroup country;
  final bool initiallyExpanded;
  final String? selectedCity;
  final String? selectedArea;
  final void Function(String? city, String? district) onSelectArea;

  @override
  State<_CountryTile> createState() => _CountryTileState();
}

class _CountryTileState extends State<_CountryTile> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  void didUpdateWidget(covariant _CountryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final city = widget.selectedCity;
    if (city != null &&
        city != oldWidget.selectedCity &&
        widget.country.cities.any((c) => c.city == city)) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final country = widget.country;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Semantics(
            expanded: _expanded,
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              leading: SizedBox(
                width: 28,
                child: Center(
                  child: AreaFlag(countryCode: country.code, size: 20),
                ),
              ),
              title: Text(
                country.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${country.count}'),
                  const SizedBox(width: 8),
                  ExcludeSemantics(
                    child: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                    ),
                  ),
                ],
              ),
              onTap: () => setState(() => _expanded = !_expanded),
            ),
          ),
        ),
        if (_expanded)
          for (final group in country.cities)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: _CityTile(
                group: group,
                selected: widget.selectedCity == group.city,
                selectedDistrict: widget.selectedCity == group.city
                    ? widget.selectedArea
                    : null,
                onSelectCity: () => widget.onSelectArea(group.city, null),
                onSelectDistrict: (d) => widget.onSelectArea(group.city, d),
              ),
            ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.leading,
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final Widget leading;
  final String label;
  final int count;
  final Color color;
  final bool selected;

  /// null disables the row.
  final VoidCallback? onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        selected: selected,
        selectedTileColor: color.withValues(alpha: 0.16),
        selectedColor: Theme.of(context).colorScheme.onSurface,
        leading: SizedBox(width: 28, child: Center(child: leading)),
        title: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: Text('$count'),
        enabled: onTap != null,
        onTap: onTap,
      ),
    );
  }
}

/// Restaurant row in [FilterDrawer]: same look as [_CategoryTile] plus an
/// expand/collapse chevron when there's at least one sub-type to show (only
/// types with a count > 0, in [RestaurantType] declaration order). Tapping
/// the row itself still filters to all restaurants (via [onSelectCategory]);
/// tapping a sub-type row filters to just that type (via [onSelectType]).
/// Auto-expands whenever a sub-type becomes the active selection, but a
/// manual collapse otherwise sticks — see [_RestaurantCategoryTileState].
class _RestaurantCategoryTile extends StatefulWidget {
  const _RestaurantCategoryTile({
    required this.count,
    required this.typeCounts,
    required this.selected,
    required this.selectedType,
    required this.onSelectCategory,
    required this.onSelectType,
  });

  final int count;
  final Map<RestaurantType, int> typeCounts;
  final bool selected;
  final RestaurantType? selectedType;
  final VoidCallback onSelectCategory;
  final ValueChanged<RestaurantType> onSelectType;

  @override
  State<_RestaurantCategoryTile> createState() =>
      _RestaurantCategoryTileState();
}

class _RestaurantCategoryTileState extends State<_RestaurantCategoryTile> {
  late bool _expanded = widget.selected;

  @override
  void didUpdateWidget(covariant _RestaurantCategoryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedType != null &&
        widget.selectedType != oldWidget.selectedType) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = AppTheme.categoryColor(PlaceCategory.restaurant, brightness);
    final orderedTypes = [
      for (final type in RestaurantType.values)
        if ((widget.typeCounts[type] ?? 0) > 0) type,
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            selected: widget.selected,
            selectedTileColor: color.withValues(alpha: 0.16),
            selectedColor: Theme.of(context).colorScheme.onSurface,
            leading: SizedBox(
              width: 28,
              child: Center(
                child: AccessibleEmoji(
                  emoji: PlaceCategory.restaurant.emoji,
                  label: PlaceCategory.restaurant.labelEn,
                  fontSize: 22,
                ),
              ),
            ),
            title: Text(
              PlaceCategory.restaurant.labelEn,
              style: TextStyle(
                fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${widget.count}'),
                if (orderedTypes.isNotEmpty)
                  IconButton(
                    icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    tooltip: _expanded ? 'Hide cuisines' : 'Show cuisines',
                    onPressed: () => setState(() => _expanded = !_expanded),
                  ),
              ],
            ),
            onTap: widget.onSelectCategory,
          ),
        ),
        if (_expanded)
          for (final type in orderedTypes)
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 12, top: 2),
              child: ListTile(
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                selected: widget.selectedType == type,
                selectedTileColor: color.withValues(alpha: 0.12),
                selectedColor: Theme.of(context).colorScheme.onSurface,
                leading: SizedBox(
                  width: 24,
                  child: Center(
                    child: AccessibleEmoji(
                      emoji: type.emoji,
                      label: type.labelEn,
                      fontSize: 17,
                    ),
                  ),
                ),
                title: Text(
                  type.labelEn,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: widget.selectedType == type
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                trailing: Text('${widget.typeCounts[type] ?? 0}'),
                onTap: () => widget.onSelectType(type),
              ),
            ),
      ],
    );
  }
}

/// "Finding areas… 320 / 1,650" + a thin bar while [AreaResolver] is
/// backfilling cities/districts; nothing otherwise.
class _AreaProgressLine extends StatelessWidget {
  const _AreaProgressLine();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AreaProgress>(
      valueListenable: AreaResolver.instance.progress,
      builder: (context, progress, _) {
        if (!progress.running || progress.total == 0) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Finding areas… ${_formatCount(progress.done)} / '
                '${_formatCount(progress.total)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: progress.done / progress.total,
                minHeight: 3,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// City row in the drawer's Areas section (under its [_CountryTile]): city
/// + count, expandable (same pattern as [_RestaurantCategoryTile]) to its
/// districts A–Z.
/// Tapping the row filters to the city; a district row to that district.
class _CityTile extends StatefulWidget {
  const _CityTile({
    required this.group,
    required this.selected,
    required this.selectedDistrict,
    required this.onSelectCity,
    required this.onSelectDistrict,
  });

  final CityGroup group;
  final bool selected;
  final String? selectedDistrict;
  final VoidCallback onSelectCity;
  final ValueChanged<String> onSelectDistrict;

  @override
  State<_CityTile> createState() => _CityTileState();
}

class _CityTileState extends State<_CityTile> {
  late bool _expanded = widget.selectedDistrict != null;

  @override
  void didUpdateWidget(covariant _CityTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedDistrict != null &&
        widget.selectedDistrict != oldWidget.selectedDistrict) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.coral;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final districts = widget.group.sortedDistricts;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            selected: widget.selected && widget.selectedDistrict == null,
            selectedTileColor: color.withValues(alpha: 0.16),
            selectedColor: onSurface,
            // The country row above already shows the flag.
            leading: const SizedBox(
              width: 28,
              child: Center(child: Icon(Icons.location_city_outlined)),
            ),
            title: Text(
              widget.group.city,
              style: TextStyle(
                fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${widget.group.count}'),
                if (districts.isNotEmpty)
                  Semantics(
                    expanded: _expanded,
                    child: IconButton(
                      icon: Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                      ),
                      tooltip: _expanded
                          ? 'Hide ${widget.group.city} districts'
                          : 'Show ${widget.group.city} districts',
                      onPressed: () => setState(() => _expanded = !_expanded),
                    ),
                  ),
              ],
            ),
            onTap: widget.onSelectCity,
          ),
        ),
        if (_expanded)
          for (final entry in districts)
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 12, top: 2),
              child: ListTile(
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                selected: widget.selectedDistrict == entry.key,
                selectedTileColor: color.withValues(alpha: 0.12),
                selectedColor: onSurface,
                leading: const SizedBox(
                  width: 24,
                  child: Icon(Icons.subdirectory_arrow_right, size: 16),
                ),
                title: Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: widget.selectedDistrict == entry.key
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                trailing: Text('${entry.value}'),
                onTap: () => widget.onSelectDistrict(entry.key),
              ),
            ),
      ],
    );
  }
}
