import 'dart:typed_data';
import 'dart:ui' as ui;

/// Gets a screenshot/photo small enough for a Gemini vision request through
/// the proxy (4 MB body cap, base64 inflates by 4/3).
///
/// The gallery path already asks image_picker for `maxDimension` px and
/// JPEG quality 85 (native re-encode on iOS/Android, canvas on web), so it
/// usually passes through untouched. Images shared into the app arrive at
/// full size; those are decoded with `dart:ui`, downscaled to fit
/// [maxDimension] and re-encoded as PNG — dart:ui has no JPEG encoder and the
/// app has no image-codec package, and Gemini accepts PNG. If that is still
/// over [maxBytes] the size steps down until it fits.
class ImagePrep {
  ImagePrep._();

  static const maxDimension = 1280;

  /// Raw-byte budget: 2.8 MB → ~3.7 MB of base64, under the proxy's 4 MB.
  static const maxBytes = 2800 * 1024;

  /// Supported input types, sniffed from magic bytes (null = unknown/unsupported).
  static String? sniffMimeType(Uint8List bytes) {
    bool startsWith(List<int> sig, [int offset = 0]) {
      if (bytes.length < offset + sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (bytes[offset + i] != sig[i]) return false;
      }
      return true;
    }

    if (startsWith([0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (startsWith([0x89, 0x50, 0x4E, 0x47])) return 'image/png';
    if (startsWith([0x52, 0x49, 0x46, 0x46]) &&
        startsWith([0x57, 0x45, 0x42, 0x50], 8)) {
      return 'image/webp';
    }
    // ISO-BMFF "ftyp" box with a HEIF brand (iPhone photos).
    if (startsWith([0x66, 0x74, 0x79, 0x70], 4)) {
      final brand = String.fromCharCodes(bytes.sublist(8, 12));
      if (const {'heic', 'heix', 'mif1', 'msf1', 'heis'}.contains(brand)) {
        return 'image/heic';
      }
    }
    return null;
  }

  /// [width]×[height] scaled down (aspect kept, never up) so the longer side
  /// is at most [maxSide]; each side at least 1.
  static ({int width, int height}) fitWithin(
    int width,
    int height, {
    int maxSide = maxDimension,
  }) {
    if (width <= 0 || height <= 0) return (width: width, height: height);
    final longer = width > height ? width : height;
    if (longer <= maxSide) return (width: width, height: height);
    final scale = maxSide / longer;
    int side(int v) {
      final r = (v * scale).round();
      return r < 1 ? 1 : r;
    }

    return (width: side(width), height: side(height));
  }

  /// [bytes] ready to send: unchanged when already a supported type within
  /// [maxSide] and [byteBudget]; otherwise downscaled and PNG-encoded.
  /// Throws [ImageTooLargeException] if it can't get under [byteBudget],
  /// or [UnsupportedImageException] for bytes that aren't a decodable image.
  static Future<PreparedImage> prepare(
    Uint8List bytes, {
    int maxSide = maxDimension,
    int byteBudget = maxBytes,
  }) async {
    final mime = sniffMimeType(bytes);
    final ui.ImmutableBuffer buffer;
    final ui.ImageDescriptor descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
    } catch (_) {
      // dart:ui can't decode it (e.g. HEIC on some Android builds) — Gemini
      // may still read it, so send a known type as-is if it fits.
      if (mime != null && bytes.length <= byteBudget) {
        return PreparedImage(bytes, mime);
      }
      throw const UnsupportedImageException();
    }
    try {
      final w = descriptor.width;
      final h = descriptor.height;
      final longer = w > h ? w : h;
      if (mime != null && longer <= maxSide && bytes.length <= byteBudget) {
        return PreparedImage(bytes, mime);
      }
      var side = longer < maxSide ? longer : maxSide;
      while (side >= 320) {
        final target = fitWithin(w, h, maxSide: side);
        final codec = await descriptor.instantiateCodec(
          targetWidth: target.width,
          targetHeight: target.height,
        );
        final frame = await codec.getNextFrame();
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        frame.image.dispose();
        codec.dispose();
        if (data == null) throw const UnsupportedImageException();
        final png = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        if (png.length <= byteBudget) return PreparedImage(png, 'image/png');
        side = (side * 0.75).round();
      }
      throw const ImageTooLargeException();
    } finally {
      descriptor.dispose();
      buffer.dispose();
    }
  }
}

/// Image bytes plus the mime type to declare in the Gemini request.
class PreparedImage {
  const PreparedImage(this.bytes, this.mimeType);

  final Uint8List bytes;
  final String mimeType;
}

class ImageTooLargeException implements Exception {
  const ImageTooLargeException();

  @override
  String toString() => 'ImageTooLargeException: screenshot too large to send';
}

class UnsupportedImageException implements Exception {
  const UnsupportedImageException();

  @override
  String toString() => 'UnsupportedImageException: not a readable image';
}
