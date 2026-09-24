import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/photo_store.dart';
import '../models/place.dart';

/// A place's picture in preference order: the user's own photo
/// ([PhotoStore]), then the first of [Place.photoUrls], then [fallback]
/// (callers pass their own — an emoji tile, a gradient header…). Shows a
/// pulsing placeholder while the user's photo is loading.
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
            child: Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              cacheWidth: cacheWidth,
              errorBuilder: (_, _, _) => fallback,
            ),
          );
        }
        return ValueListenableBuilder<bool>(
          valueListenable: store.loadingFor(place.id),
          builder: (context, loading, _) {
            if (loading) return const PhotoLoadingPlaceholder();
            if (place.photoUrls.isNotEmpty) {
              return Image.network(
                place.photoUrls.first,
                fit: BoxFit.cover,
                cacheWidth: cacheWidth,
                errorBuilder: (_, _, _) => fallback,
              );
            }
            return fallback;
          },
        );
      },
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
