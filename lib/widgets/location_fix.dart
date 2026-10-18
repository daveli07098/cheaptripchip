import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/place.dart';
import '../services/geocoding_service.dart';

/// Badge text for a place whose pin is a stand-in ([Place.locationConfirmed]
/// false) and that the user can fix from its place page.
const String kLocationUnconfirmedFixLabel = 'Location unconfirmed — tap to fix';

/// Same badge where it can't be fixed (a read-only shared-board copy).
const String kLocationUnconfirmedLabel = 'Location unconfirmed';

/// Title of [FixLocationDialog]'s "Use current map center" action.
const String kUseMapCenterLabel = 'Use current map center';

/// Warning badge for [Place.locationConfirmed] false — on the place card,
/// the map's preview card and the detail sheet. [fixable] says "tap to fix"
/// (whatever [onTap] does — the card opens the place page, the place page
/// opens [FixLocationDialog]); a read-only copy just says it's unconfirmed.
class LocationUnconfirmedBadge extends StatelessWidget {
  const LocationUnconfirmedBadge({super.key, this.fixable = true, this.onTap});

  final bool fixable;

  /// Makes the badge itself a button (the detail sheet); null leaves taps
  /// to the surrounding widget (the card's own onTap).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = fixable
        ? kLocationUnconfirmedFixLabel
        : kLocationUnconfirmedLabel;
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wrong_location, size: 14, color: scheme.onErrorContainer),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
    final onTap = this.onTap;
    if (onTap == null) return badge;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        // ≥48 px tall hit area around the small badge.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: badge,
          ),
        ),
      ),
    );
  }
}

/// Where [FixLocationDialog] put the place: the picked spot and, for an
/// address-search hit, OSM's display name (fills an empty address).
class FixedLocation {
  const FixedLocation(this.location, {this.address});

  final LatLng location;
  final String? address;
}

/// "Fix location" for an unconfirmed place: search an address (Nominatim
/// via [GeocodingService.geocodeCandidates]) and pick a match, or — when
/// opened over the map ([currentMapCenter] non-null) — use the centre of
/// the visible map. Resolves null when cancelled.
Future<FixedLocation?> showFixLocationDialog(
  BuildContext context,
  Place place, {
  LatLng Function()? currentMapCenter,
  GeocodingService? geocoder,
}) => showDialog<FixedLocation>(
  context: context,
  builder: (_) => FixLocationDialog(
    place: place,
    currentMapCenter: currentMapCenter,
    geocoder: geocoder,
  ),
);

class FixLocationDialog extends StatefulWidget {
  const FixLocationDialog({
    super.key,
    required this.place,
    this.currentMapCenter,
    this.geocoder,
  });

  final Place place;
  final LatLng Function()? currentMapCenter;

  /// Test seam; defaults to a real [GeocodingService] owned (and disposed)
  /// by the dialog.
  final GeocodingService? geocoder;

  @override
  State<FixLocationDialog> createState() => _FixLocationDialogState();
}

class _FixLocationDialogState extends State<FixLocationDialog> {
  late final TextEditingController _query = TextEditingController(
    text: _initialQuery(widget.place),
  );
  late final GeocodingService _geocoder = widget.geocoder ?? GeocodingService();
  bool _searching = false;
  List<GeocodeCandidate>? _results;

  static String _initialQuery(Place place) {
    if (place.address.trim().isNotEmpty) return place.address.trim();
    return [place.name.trim(), place.city].where((s) => s.isNotEmpty).join(' ');
  }

  @override
  void dispose() {
    _query.dispose();
    // An injected geocoder belongs to the caller.
    if (widget.geocoder == null) _geocoder.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty || _searching) return;
    setState(() => _searching = true);
    final results = await _geocoder.geocodeCandidates(query, limit: 5);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = results;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final results = _results;
    final mapCenter = widget.currentMapCenter;
    return AlertDialog(
      title: const Text('Fix location'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'We couldn’t find where “${widget.place.name}” is. Search its '
              'address, or use the centre of the map behind this page.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                labelText: 'Address or place',
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.search),
                        tooltip: 'Search address',
                        onPressed: _search,
                      ),
              ),
            ),
            if (results != null && results.isEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'No matches — try a fuller address.',
                style: TextStyle(color: scheme.error),
              ),
            ],
            if (results != null && results.isNotEmpty)
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in results)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.place_outlined),
                        title: Text(
                          c.displayName.isEmpty
                              ? '${c.location.latitude.toStringAsFixed(5)}, '
                                    '${c.location.longitude.toStringAsFixed(5)}'
                              : c.displayName,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.pop(
                          context,
                          FixedLocation(
                            c.location,
                            address: c.displayName.isEmpty
                                ? null
                                : c.displayName,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (mapCenter != null)
          TextButton.icon(
            icon: const Icon(Icons.center_focus_strong, size: 18),
            label: const Text(kUseMapCenterLabel),
            onPressed: () => Navigator.pop(context, FixedLocation(mapCenter())),
          ),
      ],
    );
  }
}
