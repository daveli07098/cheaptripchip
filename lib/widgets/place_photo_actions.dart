import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/photo_store.dart';
import '../models/place.dart';

/// Add / change / remove the user's own photo for [place]: a small bottom
/// sheet (Take photo — mobile only, Choose from library, Remove photo when
/// one exists), then pick → [PhotoStore.setPhoto] or confirm →
/// [PhotoStore.removePhoto]. Errors surface as a SnackBar on the nearest
/// [ScaffoldMessenger] of [context] — callers inside a modal sheet should
/// provide their own messenger so it isn't hidden under the modal.
///
/// Platform notes: Android needs no manifest permission (the system photo
/// picker and the camera capture intent run in other apps; the app doesn't
/// declare `android.permission.CAMERA`, which would otherwise force a
/// runtime prompt). iOS needs `NSPhotoLibraryUsageDescription` and
/// `NSCameraUsageDescription` in Info.plist.
Future<void> showPlacePhotoActions(BuildContext context, Place place) async {
  final messenger = ScaffoldMessenger.of(context);
  final hasPhoto = PhotoStore.instance.photoFor(place.id).value != null;
  final choice = await showModalBottomSheet<_PhotoAction>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!kIsWeb)
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(sheetContext, _PhotoAction.camera),
            ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from library'),
            onTap: () => Navigator.pop(sheetContext, _PhotoAction.gallery),
          ),
          if (hasPhoto)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove photo'),
              onTap: () => Navigator.pop(sheetContext, _PhotoAction.remove),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  switch (choice) {
    case _PhotoAction.camera:
      await _pickAndSave(messenger, place, ImageSource.camera);
    case _PhotoAction.gallery:
      await _pickAndSave(messenger, place, ImageSource.gallery);
    case _PhotoAction.remove:
      await confirmRemovePlacePhoto(context, place);
  }
}

/// Confirm dialog, then [PhotoStore.removePhoto]. Errors → SnackBar.
Future<void> confirmRemovePlacePhoto(BuildContext context, Place place) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Remove photo?'),
      content: Text('Your photo of ${place.name} will be deleted.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await PhotoStore.instance.removePhoto(place.id);
  } catch (error) {
    debugPrint('Remove photo failed: $error');
    _showError(messenger, 'Could not remove the photo. Try again.');
  }
}

Future<void> _pickAndSave(
  ScaffoldMessengerState messenger,
  Place place,
  ImageSource source,
) async {
  try {
    // Downscaling + re-encoding happens in the platform picker, so a
    // typical phone photo lands around 150–400 KB — under Firestore's 1 MiB
    // document limit without any Dart-side image decoding.
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 75,
    );
    if (file == null) return; // Cancelled.
    final bytes = await file.readAsBytes();
    await PhotoStore.instance.setPhoto(place.id, bytes);
  } on PhotoTooLargeException catch (error) {
    _showError(messenger, '$error Try a different photo.');
  } catch (error) {
    debugPrint('Save photo failed: $error');
    _showError(
      messenger,
      source == ImageSource.camera
          ? 'Could not take a photo. Check camera access in Settings.'
          : 'Could not save the photo. Try again.',
    );
  }
}

void _showError(ScaffoldMessengerState messenger, String message) {
  messenger.showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}

enum _PhotoAction { camera, gallery, remove }
