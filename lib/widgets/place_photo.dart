import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/photo_store.dart';
import '../models/place.dart';

/// A place's picture in preference order: the user's own photo
/// ([PhotoStore]), then the first of [Place.photoUrls], then [fallback]
/// (callers pass their own — an emoji tile, a gradient header…). Shows a
/// pulsing placeholder while the user's photo is loading.
///
/// While an image decodes, [fallback] shows underneath and the picture
/// fades in over it once its first frame lands — instead of a blank box
/// that pops. An image already in the [ImageCache] (see [precache]) paints
/// in the first frame with no fade.
///
/// Fills its parent's constraints; callers size and clip it.
class PlacePhoto extends StatelessWidget {
  const PlacePhoto({
    super.key,
    required this.place,
    required this.fallback,
    this.cacheWidth,
  });

  final Place place;
  final Widget fallback;

  /// Decode width hint for thumbnails, so a 1280px JPEG isn't decoded at
  /// full size into a 72px square.
  final int? cacheWidth;

  /// Decode width for a full-width header: the screen's width in physical
  /// pixels. Shared by the detail sheet's header and [precache] callers so
  /// both resolve the identical [ImageCache] key.
  static int headerCacheWidth(BuildContext context) =>
      (MediaQuery.sizeOf(context).width *
              MediaQuery.devicePixelRatioOf(context))
          .round();

  /// The provider [PlacePhoto] paints for [place] right now (the user's
  /// photo bytes if loaded, else the first source URL), or null for the
  /// fallback. [PlacePhoto] and [precache] both build through this so the
  /// cache keys always match.
  static ImageProvider? providerFor(Place place, {int? cacheWidth}) {
    final bytes = PhotoStore.instance.photoFor(place.id).value;
    if (bytes != null) return _memoryProvider(bytes, cacheWidth);
    if (place.photoUrls.isEmpty) return null;
    return _networkProvider(place.photoUrls.first, cacheWidth);
  }

  static ImageProvider _memoryProvider(Uint8List bytes, int? cacheWidth) =>
      ResizeImage.resizeIfNeeded(cacheWidth, null, MemoryImage(bytes));

  static ImageProvider _networkProvider(String url, int? cacheWidth) =>
      ResizeImage.resizeIfNeeded(cacheWidth, null, NetworkImage(url));

  /// Starts decoding [place]'s picture at [cacheWidth] ahead of time (e.g.
  /// the detail header on a pin tap), so the widget that shows it later
  /// finds it in the [ImageCache] and paints in its first frame. Failures
  /// are ignored — the widget itself falls back.
  static Future<void> precache(
    BuildContext context,
    Place place, {
    int? cacheWidth,
  }) {
    final provider = providerFor(place, cacheWidth: cacheWidth);
    if (provider == null) return Future.value();
    return precacheImage(provider, context, onError: (_, _) {});
  }

  /// Same as [precache] but only for a static [url] — for shared-board
  /// copies, whose headers never read [PhotoStore].
  static Future<void> precacheUrl(
    BuildContext context,
    String url, {
    int? cacheWidth,
  }) => precacheImage(
    _networkProvider(url, cacheWidth),
    context,
    onError: (_, _) {},
  );

  /// An [Image] for a static [url] that fades in over [fallback] like
  /// [PlacePhoto] does — for callers that must not read [PhotoStore].
  static Widget network(
    String url, {
    required Widget fallback,
    int? cacheWidth,
  }) => _FadeInImage(
    image: _networkProvider(url, cacheWidth),
    fallback: fallback,
  );

  @override
  Widget build(BuildContext context) {
    final store = PhotoStore.instance;
    return ValueListenableBuilder<Uint8List?>(
      valueListenable: store.photoFor(place.id),
      builder: (context, bytes, _) {
        if (bytes != null) {
          return Semantics(
            image: true,
            label: 'Your photo of ${place.name}',
            child: _FadeInImage(
              image: _memoryProvider(bytes, cacheWidth),
              fallback: fallback,
              // Keep the previous photo up while a replacement decodes.
              gaplessPlayback: true,
            ),
          );
        }
        return ValueListenableBuilder<bool>(
          valueListenable: store.loadingFor(place.id),
          builder: (context, loading, _) {
            if (loading) return const PhotoLoadingPlaceholder();
            if (place.photoUrls.isNotEmpty) {
              return _FadeInImage(
                image: _networkProvider(place.photoUrls.first, cacheWidth),
                fallback: fallback,
              );
            }
            return fallback;
          },
        );
      },
    );
  }
}

/// [image] cover-fitted over [fallback]: the fallback shows while it
/// decodes (and stays if it fails), then the image fades in. A
/// synchronously available image (already cached) skips both.
class _FadeInImage extends StatefulWidget {
  const _FadeInImage({
    required this.image,
    required this.fallback,
    this.gaplessPlayback = false,
  });

  final ImageProvider image;
  final Widget fallback;

  /// Keeps the previous picture fully visible while a replacement decodes
  /// (e.g. the user changed their photo) instead of fading back out.
  final bool gaplessPlayback;

  @override
  State<_FadeInImage> createState() => _FadeInImageState();
}

class _FadeInImageState extends State<_FadeInImage> {
  /// Whether any frame has painted yet — for [_FadeInImage.gaplessPlayback].
  bool _shownFrame = false;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: widget.image,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: widget.gaplessPlayback,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        if (frame != null) _shownFrame = true;
        final visible =
            frame != null || (widget.gaplessPlayback && _shownFrame);
        return Stack(
          fit: StackFit.expand,
          children: [
            // Hidden from a11y once covered, so its label (e.g. the
            // category emoji) doesn't linger under the photo.
            ExcludeSemantics(excluding: visible, child: widget.fallback),
            AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: child,
            ),
          ],
        );
      },
      // Replaces frameBuilder's output entirely, so the fallback has to be
      // returned again here.
      errorBuilder: (_, _, _) => widget.fallback,
    );
  }
}

/// Gently pulsing tile shown while a photo loads.
class PhotoLoadingPlaceholder extends StatefulWidget {
  const PhotoLoadingPlaceholder({super.key});

  @override
  State<PhotoLoadingPlaceholder> createState() =>
      _PhotoLoadingPlaceholderState();
}

class _PhotoLoadingPlaceholderState extends State<PhotoLoadingPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading photo',
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.35, end: 0.8).animate(_controller),
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
