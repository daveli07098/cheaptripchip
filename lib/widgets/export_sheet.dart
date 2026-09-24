import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/trip_share.dart';

/// Bottom sheet offering every way to get a [TripBundle] out of the app:
/// app link, portable file, KML for Google My Maps, and a Google Maps route.
class ExportSheet extends StatelessWidget {
  const ExportSheet({super.key, required this.bundle});

  final TripBundle bundle;

  /// Google's directions URL holds at most this many stops.
  static const maxRouteStops = TripShare.maxRouteWaypoints + 2;

  static Future<void> show(BuildContext context, TripBundle bundle) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ExportSheet(bundle: bundle),
    );
  }

  int get _count => bundle.places.length;

  String get _countLabel => '$_count ${_count == 1 ? 'place' : 'places'}';

  Future<void> _shareLink(BuildContext context) async {
    final route = TripShare.googleMapsRouteUrl(bundle.places);
    final text = StringBuffer()
      ..writeln('${bundle.title} — $_countLabel')
      ..writeln()
      ..writeln('Open in Cheaptripchip:')
      ..writeln(TripShare.toAppLink(bundle));
    if (route != null) {
      text
        ..writeln()
        ..writeln('No app? View in Google Maps:')
        ..writeln(route);
    }
    await _sharePlus(
      context,
      ShareParams(text: text.toString().trimRight(), subject: bundle.title),
    );
  }

  Future<void> _shareFile(BuildContext context) => _shareData(
    context,
    TripShare.toFileJson(bundle),
    mimeType: 'application/json',
    name: TripShare.fileName(bundle),
  );

  Future<void> _shareKml(BuildContext context) => _shareData(
    context,
    TripShare.toKml(bundle),
    mimeType: 'application/vnd.google-earth.kml+xml',
    name: TripShare.kmlFileName(bundle),
  );

  Future<void> _shareData(
    BuildContext context,
    String contents, {
    required String mimeType,
    required String name,
  }) {
    final file = XFile.fromData(
      utf8.encode(contents),
      mimeType: mimeType,
      name: name,
    );
    return _sharePlus(
      context,
      ShareParams(files: [file], fileNameOverrides: [name], subject: name),
    );
  }

  Future<void> _sharePlus(BuildContext context, ShareParams params) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await SharePlus.instance.share(params);
    } catch (e) {
      debugPrint('Share failed: $e');
      messenger?.showSnackBar(
        const SnackBar(content: Text('Could not open the share sheet')),
      );
    }
  }

  Future<void> _openRoute(BuildContext context) async {
    final url = TripShare.googleMapsRouteUrl(bundle.places);
    if (url == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Could not open Google Maps')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = colors.onSurfaceVariant.withValues(alpha: 0.7);
    final linkFits = _count > 0 && TripShare.linkFits(bundle);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 20, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Share “${bundle.title}”',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(_countLabel, style: TextStyle(color: muted)),
            ),
            if (_count == 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(
                  'Nothing to share yet — save some places first.',
                  style: TextStyle(color: muted, height: 1.4),
                ),
              )
            else ...[
              ListTile(
                enabled: linkFits,
                leading: const Icon(Icons.link),
                title: const Text('Share link'),
                subtitle: Text(
                  linkFits
                      ? 'Friends with the app import it in one tap'
                      : 'Too many places for a link — share as a file',
                ),
                onTap: () => _shareLink(context),
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Share file'),
                subtitle: Text(TripShare.fileName(bundle)),
                onTap: () => _shareFile(context),
              ),
              ListTile(
                leading: const Icon(Icons.layers_outlined),
                title: const Text('Export to Google My Maps'),
                subtitle: const Text(
                  'In Google My Maps: Create map → Import → choose this file.',
                ),
                onTap: () => _shareKml(context),
              ),
              ListTile(
                leading: const Icon(Icons.directions_outlined),
                title: const Text('Open route in Google Maps'),
                subtitle: Text(
                  _count == 1
                      ? 'Pins this place in Google Maps'
                      : _count > maxRouteStops
                      ? 'Only the first $maxRouteStops stops fit in a route'
                      : 'Walking route through every stop',
                ),
                onTap: () => _openRoute(context),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
