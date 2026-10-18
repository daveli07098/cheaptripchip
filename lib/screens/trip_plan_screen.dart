import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/board.dart';
import '../models/place.dart';
import '../models/trip_plan.dart';
import '../services/trip_planner.dart';
import '../services/trip_share.dart';
import '../theme/app_theme.dart';
import '../widgets/accessible_emoji.dart';
import '../widgets/share_or_report.dart';

/// Opens [uri] outside the app; false when the platform refuses.
typedef UrlLauncher = Future<bool> Function(Uri uri);

Future<bool> _launchExternal(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// Board ⋮ → "Plan a trip ✨": asks for [TripPlanOptions], plans [board]'s
/// places (Gemini, else the on-device fallback) and opens [TripPlanScreen].
/// [onSave] persists the plan with the board — null for boards that can't
/// store one (shared boards, the auto "New finds" board), whose plan then
/// lives only on screen.
Future<void> openTripPlanner(
  BuildContext context, {
  required Board board,
  required Map<String, Place> placesById,
  ValueChanged<TripPlan>? onSave,
  TripPlanner? planner,
  UrlLauncher? launch,
}) async {
  final places = boardPlaces(board, placesById);
  if (places.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Add some places to plan a trip')),
    );
    return;
  }
  final saved = board.tripPlan;
  final request = await TripPlanOptionsSheet.show(
    context,
    initial: saved?.options ?? const TripPlanOptions(),
    hasSavedPlan: saved != null,
  );
  if (request == null || !context.mounted) return;

  final TripPlan plan;
  if (request.openSaved && saved != null) {
    plan = saved.reconciledWith(
      TripPlanner.candidatesFor(places, saved.options).map((p) => p.id),
    );
  } else {
    final options = request.options;
    final navigator = Navigator.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(child: Text('Planning your trip…')),
            ],
          ),
        ),
      ),
    );
    try {
      plan = await (planner ?? TripPlanner()).plan(places, options);
    } finally {
      navigator.pop();
    }
    onSave?.call(plan);
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TripPlanScreen(
        title: board.name,
        plan: plan,
        placesById: placesById,
        onChanged: onSave,
        launch: launch,
      ),
    ),
  );
}

/// [board]'s places in board order, each once; ids with no place dropped.
List<Place> boardPlaces(Board board, Map<String, Place> placesById) {
  final seen = <String>{};
  return [
    for (final section in board.sections)
      for (final id in section.placeIds)
        if (seen.add(id)) ?placesById[id],
  ];
}

/// What the options sheet returns: plan anew with [options], or reopen
/// the board's saved plan.
class TripPlanRequest {
  const TripPlanRequest(this.options, {this.openSaved = false});

  final TripPlanOptions options;
  final bool openSaved;
}

/// "Plan a trip" options: days, start date, pace, start point and
/// must-visits only.
class TripPlanOptionsSheet extends StatefulWidget {
  const TripPlanOptionsSheet({
    super.key,
    required this.initial,
    this.hasSavedPlan = false,
  });

  final TripPlanOptions initial;
  final bool hasSavedPlan;

  static Future<TripPlanRequest?> show(
    BuildContext context, {
    required TripPlanOptions initial,
    bool hasSavedPlan = false,
  }) {
    return showModalBottomSheet<TripPlanRequest>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          TripPlanOptionsSheet(initial: initial, hasSavedPlan: hasSavedPlan),
    );
  }

  @override
  State<TripPlanOptionsSheet> createState() => _TripPlanOptionsSheetState();
}

class _TripPlanOptionsSheetState extends State<TripPlanOptionsSheet> {
  late int _days = widget.initial.days;
  late DateTime? _startDate = widget.initial.startDate;
  late TripPace _pace = widget.initial.pace;
  late bool _mustVisitOnly = widget.initial.mustVisitOnly;
  late final _startPoint = TextEditingController(
    text: widget.initial.startPoint,
  );

  @override
  void dispose() {
    _startPoint.dispose();
    super.dispose();
  }

  TripPlanOptions get _options => TripPlanOptions(
    days: _days,
    startDate: _startDate,
    pace: _pace,
    startPoint: _startPoint.text.trim(),
    mustVisitOnly: _mustVisitOnly,
  );

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final date = _startDate;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Plan a trip', style: textTheme.titleLarge),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Text('Days', style: textTheme.titleSmall)),
                IconButton(
                  tooltip: 'Fewer days',
                  icon: const Icon(Icons.remove),
                  onPressed: _days > TripPlanOptions.minDays
                      ? () => setState(() => _days--)
                      : null,
                ),
                Text('$_days', style: textTheme.titleMedium),
                IconButton(
                  tooltip: 'More days',
                  icon: const Icon(Icons.add),
                  onPressed: _days < TripPlanOptions.maxDays
                      ? () => setState(() => _days++)
                      : null,
                ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(
                date == null
                    ? 'Start date (optional)'
                    : 'Starts ${date.day}/${date.month}/${date.year}',
              ),
              trailing: date == null
                  ? null
                  : IconButton(
                      tooltip: 'Clear start date',
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _startDate = null),
                    ),
              onTap: _pickDate,
            ),
            const SizedBox(height: 8),
            Text('Pace', style: textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<TripPace>(
              segments: [
                for (final pace in TripPace.values)
                  ButtonSegment(value: pace, label: Text(pace.label)),
              ],
              selected: {_pace},
              onSelectionChanged: (s) => setState(() => _pace = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _startPoint,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Start point (optional)',
                hintText: 'Hotel or station',
                prefixIcon: Icon(Icons.hotel_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Must-visits only'),
              subtitle: const Text(
                'Only favourites — otherwise favourites go first',
              ),
              value: _mustVisitOnly,
              onChanged: (v) => setState(() => _mustVisitOnly = v),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.auto_awesome),
              label: Text(widget.hasSavedPlan ? 'Plan again' : 'Plan my trip'),
              onPressed: () =>
                  Navigator.of(context).pop(TripPlanRequest(_options)),
            ),
            if (widget.hasSavedPlan) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(
                  context,
                ).pop(TripPlanRequest(widget.initial, openSaved: true)),
                child: const Text('Open saved plan'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A trip plan: one tab per day (mini map, Google Maps links, the ordered
/// stops — drag to reorder, ⋮ to move to another day) plus "Didn't fit".
/// Every edit is reported through [onChanged] (which saves it with the
/// board); without one the plan is local to this screen.
class TripPlanScreen extends StatefulWidget {
  const TripPlanScreen({
    super.key,
    required this.title,
    required this.plan,
    required this.placesById,
    this.onChanged,
    this.launch,
    this.showMaps = true,
  });

  final String title;
  final TripPlan plan;
  final Map<String, Place> placesById;
  final ValueChanged<TripPlan>? onChanged;

  /// Opens Google Maps links; defaults to url_launcher (external app).
  final UrlLauncher? launch;

  /// The per-day mini map; off in widget tests (no tile network).
  final bool showMaps;

  @override
  State<TripPlanScreen> createState() => _TripPlanScreenState();
}

class _TripPlanScreenState extends State<TripPlanScreen> {
  late TripPlan _plan = widget.plan;

  void _update(TripPlan plan) {
    setState(() => _plan = plan);
    widget.onChanged?.call(plan);
  }

  List<Place> _dayPlaces(int day) => [
    for (final stop in _plan.days[day]) ?widget.placesById[stop.placeId],
  ];

  Future<void> _openInMaps(Uri url) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await (widget.launch ?? _launchExternal)(url);
    if (!ok) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Could not open Google Maps')),
      );
    }
  }

  Future<void> _share() => shareOrReport(
    context,
    ShareParams(
      text: TripPlanner.shareText(widget.title, _plan, widget.placesById),
      subject: '${widget.title} trip plan',
    ),
  );

  String _dayLabel(int day) {
    final date = _plan.dateOf(day);
    if (date == null) return 'Day ${day + 1}';
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return 'Day ${day + 1} · ${weekdays[date.weekday - 1]} ${date.day}/${date.month}';
  }

  @override
  Widget build(BuildContext context) {
    final saved = widget.onChanged != null;
    return DefaultTabController(
      length: _plan.days.length + 1,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, overflow: TextOverflow.ellipsis),
              Text(
                [
                  _plan.source == TripPlanSource.ai
                      ? 'Planned with AI'
                      : 'Planned by distance',
                  saved ? 'saved with the board' : 'not saved',
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Share plan',
              icon: const Icon(Icons.ios_share),
              onPressed: _share,
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (var d = 0; d < _plan.days.length; d++)
                Tab(text: _dayLabel(d)),
              Tab(text: "Didn't fit (${_plan.unplaced.length})"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (var d = 0; d < _plan.days.length; d++) _buildDay(context, d),
            _buildUnplaced(context),
          ],
        ),
      ),
    );
  }

  Widget _buildDay(BuildContext context, int day) {
    final stops = _plan.days[day];
    final places = _dayPlaces(day);
    final urls = TripShare.googleMapsRouteUrls(
      places,
      origin: _plan.options.startPoint,
    );
    final header = Column(
      key: const ValueKey('header'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showMaps && places.isNotEmpty)
          SizedBox(height: 200, child: _DayMap(places: places)),
        if (urls.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < urls.length; i++)
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.directions_walk),
                    label: Text(
                      urls.length == 1
                          ? 'Open day in Google Maps'
                          : 'Google Maps · part ${i + 1} of ${urls.length}',
                    ),
                    onPressed: () => _openInMaps(urls[i]),
                  ),
              ],
            ),
          ),
        if (stops.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Free day — move stops here from another day',
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
    return ReorderableListView.builder(
      key: PageStorageKey('day-$day'),
      buildDefaultDragHandles: false,
      header: header,
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: stops.length,
      onReorder: (oldIndex, newIndex) {
        // ReorderableListView reports newIndex as if the item were still in
        // place; moveStop expects the index after removal.
        if (newIndex > oldIndex) newIndex--;
        _update(
          _plan.moveStop(
            fromDay: day,
            fromIndex: oldIndex,
            toDay: day,
            toIndex: newIndex,
          ),
        );
      },
      itemBuilder: (context, index) => _StopTile(
        key: ValueKey(stops[index].placeId),
        index: index,
        stop: stops[index],
        place: widget.placesById[stops[index].placeId],
        otherDays: [
          for (var d = 0; d < _plan.days.length; d++)
            if (d != day) d,
        ],
        onMoveToDay: (target) => _update(
          _plan.moveStop(
            fromDay: day,
            fromIndex: index,
            toDay: target,
            toIndex: _plan.days[target].length,
          ),
        ),
        onRemove: () => _update(_plan.removeStop(day, index)),
      ),
    );
  }

  Widget _buildUnplaced(BuildContext context) {
    final ids = _plan.unplaced;
    if (ids.isEmpty) {
      return const Center(child: Text('Everything fit into the plan'));
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final id in ids)
          if (widget.placesById[id] case final place?)
            ListTile(
              leading: AccessibleEmoji(
                emoji: place.category.emoji,
                label: place.category.labelEn,
                fontSize: 22,
              ),
              title: Text(place.name),
              subtitle: place.areaDisplay.isEmpty
                  ? null
                  : Text(place.areaDisplay),
              trailing: PopupMenuButton<int>(
                tooltip: 'Add to a day',
                icon: const Icon(Icons.playlist_add),
                onSelected: (day) => _update(_plan.addToDay(id, day)),
                itemBuilder: (_) => [
                  for (var d = 0; d < _plan.days.length; d++)
                    PopupMenuItem(value: d, child: Text('Add to Day ${d + 1}')),
                ],
              ),
            ),
      ],
    );
  }
}

class _StopTile extends StatelessWidget {
  const _StopTile({
    super.key,
    required this.index,
    required this.stop,
    required this.place,
    required this.otherDays,
    required this.onMoveToDay,
    required this.onRemove,
  });

  final int index;
  final TripStop stop;
  final Place? place;
  final List<int> otherDays;
  final ValueChanged<int> onMoveToDay;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final place = this.place;
    final scheme = Theme.of(context).colorScheme;
    final color = place == null
        ? scheme.primary
        : AppTheme.categoryColor(place.category, Theme.of(context).brightness);
    return ListTile(
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ReorderableDragStartListener(
            index: index,
            child: const Icon(Icons.drag_indicator, semanticLabel: 'Reorder'),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 14,
            backgroundColor: color,
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
      title: Text(place?.name ?? 'Unknown place'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AccessibleEmoji(emoji: stop.slot.emoji, label: stop.slot.label),
              const SizedBox(width: 4),
              Text(
                stop.slot.label,
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (place != null && place.areaDisplay.isNotEmpty)
                Flexible(
                  child: Text(
                    ' · ${place.areaDisplay}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          if (stop.reason.isNotEmpty) Text(stop.reason),
        ],
      ),
      trailing: PopupMenuButton<int>(
        tooltip: 'Stop options',
        onSelected: (value) => value < 0 ? onRemove() : onMoveToDay(value),
        itemBuilder: (_) => [
          for (final d in otherDays)
            PopupMenuItem(value: d, child: Text('Move to Day ${d + 1}')),
          const PopupMenuItem(value: -1, child: Text('Remove from plan')),
        ],
      ),
    );
  }
}

/// Static map of one day: the route as a polyline through numbered pins.
class _DayMap extends StatelessWidget {
  const _DayMap({required this.places});

  final List<Place> places;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final points = [for (final p in places) p.location];
    final fit = points.length > 1
        ? CameraFit.coordinates(
            coordinates: points,
            padding: const EdgeInsets.all(36),
            maxZoom: 16,
          )
        : null;
    return Stack(
      children: [
        FlutterMap(
          // Refit whenever the route changes (reorder / move).
          key: ValueKey(places.map((p) => p.id).join(',')),
          options: MapOptions(
            initialCenter: points.first,
            initialZoom: 15,
            initialCameraFit: fit,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: AppTheme.mapTileUrl,
              userAgentPackageName: 'com.cheaptripchip.app',
            ),
            if (points.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: points,
                    strokeWidth: 4,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                for (var i = 0; i < places.length; i++)
                  Marker(
                    point: points[i],
                    width: 28,
                    height: 28,
                    child: Semantics(
                      label: 'Stop ${i + 1}: ${places[i].name}',
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppTheme.categoryColor(
                            places[i].category,
                            brightness,
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Center(
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          right: 4,
          bottom: 2,
          child: Text(
            AppTheme.mapAttribution,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: Colors.black54),
          ),
        ),
      ],
    );
  }
}
