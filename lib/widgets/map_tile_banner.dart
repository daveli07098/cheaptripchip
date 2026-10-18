import 'package:flutter/material.dart';

/// Banner text shown over the map while tiles keep failing.
const String kMapUnavailableMessage = 'Map unavailable — check your connection';

/// Tracks map tile loads to decide when the map is "unavailable": after
/// [threshold] tile errors within [window] with no successful tile in
/// between, [unavailable] turns true; the next successful tile turns it
/// false and starts the count over.
///
/// Anti-flap rules: errors only count since the last success (a stray
/// failure among good tiles never adds up), the banner only hides on a
/// real success, and [dismiss] keeps it hidden until a tile loads again —
/// a fresh run of [threshold] errors after that success is needed to show
/// it again.
class TileHealthMonitor {
  TileHealthMonitor({
    this.threshold = 6,
    this.window = const Duration(seconds: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int threshold;
  final Duration window;
  final DateTime Function() _clock;

  /// Whether the banner should show.
  final ValueNotifier<bool> unavailable = ValueNotifier(false);

  /// Errors since the last success, oldest first, pruned to [window].
  final List<DateTime> _errors = [];

  /// When the latest error was recorded — a tile that finished loading
  /// before it (an old, already-shown tile being rebuilt) isn't evidence
  /// the connection is back.
  DateTime? _lastErrorAt;

  bool _dismissed = false;

  /// Whether a tile error is waiting for a success to clear it — callers
  /// that report successes from a build (TileLayer.tileBuilder) check this
  /// first and defer [recordSuccess] out of the build.
  bool get awaitingRecovery => _lastErrorAt != null;

  /// A tile failed to load.
  void recordError() {
    final now = _clock();
    _lastErrorAt = now;
    _errors
      ..add(now)
      ..removeWhere((at) => now.difference(at) > window);
    if (!_dismissed && _errors.length >= threshold) unavailable.value = true;
  }

  /// A tile finished loading successfully at [loadedAt]. Cheap no-op when
  /// nothing is pending, so it can be called for every tile rebuild.
  void recordSuccess(DateTime loadedAt) {
    final lastError = _lastErrorAt;
    if (lastError == null || !loadedAt.isAfter(lastError)) return;
    _lastErrorAt = null;
    _errors.clear();
    _dismissed = false;
    unavailable.value = false;
  }

  /// The user closed the banner: stays hidden until a tile loads again.
  void dismiss() {
    _dismissed = true;
    unavailable.value = false;
  }

  void dispose() => unavailable.dispose();
}

/// Small dismissible "Map unavailable — check your connection" banner,
/// shown while [monitor] says tiles keep failing.
class MapTileBanner extends StatelessWidget {
  const MapTileBanner({super.key, required this.monitor, this.padding});

  final TileHealthMonitor monitor;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: monitor.unavailable,
      builder: (context, unavailable, _) {
        if (!unavailable) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: padding ?? EdgeInsets.zero,
          child: Semantics(
            liveRegion: true,
            child: Material(
              color: scheme.inverseSurface,
              elevation: 3,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 14),
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_off,
                      size: 18,
                      color: scheme.onInverseSurface,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        kMapUnavailableMessage,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: scheme.onInverseSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Dismiss',
                      icon: const Icon(Icons.close, size: 18),
                      color: scheme.onInverseSurface,
                      onPressed: monitor.dismiss,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
