import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cheaptripchip/services/image_prep.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  // Gradient so the PNG doesn't compress to almost nothing.
  for (var x = 0; x < width; x += 16) {
    canvas.drawRect(
      ui.Rect.fromLTWH(x.toDouble(), 0, 16, height.toDouble()),
      ui.Paint()..color = ui.Color.fromARGB(255, x % 256, (x * 7) % 256, 90),
    );
  }
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<({int width, int height})> _size(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final d = await ui.ImageDescriptor.encoded(buffer);
  final size = (width: d.width, height: d.height);
  d.dispose();
  buffer.dispose();
  return size;
}

void main() {
  group('fitWithin', () {
    test('scales the longer side down to the max, keeping aspect', () {
      expect(ImagePrep.fitWithin(2560, 1440), (width: 1280, height: 720));
      expect(ImagePrep.fitWithin(1170, 2532), (width: 591, height: 1280));
    });
    test('never upscales', () {
      expect(ImagePrep.fitWithin(800, 600), (width: 800, height: 600));
      expect(ImagePrep.fitWithin(1280, 1280), (width: 1280, height: 1280));
    });
    test('keeps sides at least 1 px', () {
      expect(ImagePrep.fitWithin(10000, 1, maxSide: 100), (
        width: 100,
        height: 1,
      ));
    });
  });

  group('sniffMimeType', () {
    test('recognizes JPEG, PNG, WebP and HEIC magic bytes', () {
      expect(
        ImagePrep.sniffMimeType(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])),
        'image/jpeg',
      );
      expect(
        ImagePrep.sniffMimeType(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47])),
        'image/png',
      );
      expect(
        ImagePrep.sniffMimeType(
          Uint8List.fromList([
            ...'RIFF'.codeUnits,
            0,
            0,
            0,
            0,
            ...'WEBP'.codeUnits,
          ]),
        ),
        'image/webp',
      );
      expect(
        ImagePrep.sniffMimeType(
          Uint8List.fromList([0, 0, 0, 0x18, ...'ftypheic'.codeUnits]),
        ),
        'image/heic',
      );
      expect(ImagePrep.sniffMimeType(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });

  group('prepare', () {
    testWidgets('passes a small supported image through unchanged', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final png = await _png(400, 300);
        final out = await ImagePrep.prepare(png);
        expect(out.mimeType, 'image/png');
        expect(identical(out.bytes, png), isTrue);
      });
    });

    testWidgets('downscales an oversized image to fit 1280 px', (tester) async {
      await tester.runAsync(() async {
        final png = await _png(2560, 1600);
        final out = await ImagePrep.prepare(png);
        expect(out.mimeType, 'image/png');
        expect(await _size(out.bytes), (width: 1280, height: 800));
      });
    });

    testWidgets('steps the size down until it fits the byte budget', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final png = await _png(1200, 900);
        final budget = png.length ~/ 2;
        final out = await ImagePrep.prepare(png, byteBudget: budget);
        expect(out.bytes.length, lessThanOrEqualTo(budget));
        final size = await _size(out.bytes);
        expect(size.width, lessThan(1200));
      });
    });

    testWidgets('rejects bytes that are not an image', (tester) async {
      await tester.runAsync(() async {
        await expectLater(
          ImagePrep.prepare(Uint8List.fromList(List.filled(64, 7))),
          throwsA(isA<UnsupportedImageException>()),
        );
      });
    });
  });
}
