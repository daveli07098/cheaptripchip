import 'dart:async';

import 'package:flutter/material.dart';

import '../data/photo_store.dart';
import '../data/place_store.dart';
import '../models/place.dart';

/// How long "Deleted “Name”" (and its UNDO) stays up.
const _undoWindow = Duration(seconds: 6);

/// Deletes the find [place] ([PlaceStore.deletePlace]: off the Saved list
/// and every personal board) and shows "Deleted “Name”" with an UNDO that
/// puts it back where it was ([PlaceStore.restoreDeleted]). Its stored
/// photo is discarded only once that SnackBar closes without UNDO — after
/// [_undoWindow], a swipe, or being replaced by the next SnackBar.
///
/// [messenger] is grabbed by the caller before anything is awaited (the
/// optimistic delete rebuilds the caller's ancestors without it). A failed
/// write is reverted by the store and reported as "Couldn't delete — try
/// again". Resolves true if the place was deleted.
Future<bool> deleteFindWithUndo(
  ScaffoldMessengerState messenger,
  Place place, {
  SnackBarBehavior? behavior,
}) async {
  final DeletedPlace? deleted;
  try {
    deleted = await PlaceStore.instance.deletePlace(place.id);
  } catch (error) {
    debugPrint('deleteFindWithUndo: ${place.id} failed: $error');
    if (messenger.mounted) {
      messenger
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text("Couldn't delete — try again"),
            behavior: behavior,
          ),
        );
    }
    return false;
  }
  if (deleted == null) return false;
  if (!messenger.mounted) {
    unawaited(PhotoStore.instance.discardPhotoOf(deleted));
    return true;
  }
  // Deleting several in quick succession replaces the SnackBar rather than
  // queueing them; the replaced one's photo is discarded (reason: remove).
  messenger.removeCurrentSnackBar();
  final controller = messenger.showSnackBar(
    SnackBar(
      content: Text('Deleted “${place.name}”'),
      behavior: behavior,
      // A SnackBar with an action persists by default; this one closes so
      // the undo window ends (and the photo is discarded) — except under
      // accessible navigation, where a screen-reader user needs the time
      // (it then closes when the next SnackBar replaces it).
      persist:
          MediaQuery.maybeAccessibleNavigationOf(messenger.context) ?? false,
      duration: _undoWindow,
      action: SnackBarAction(
        label: 'UNDO',
        onPressed: () => unawaited(_restore(messenger, deleted!)),
      ),
    ),
  );
  unawaited(
    controller.closed.then((reason) {
      if (reason != SnackBarClosedReason.action) {
        return PhotoStore.instance.discardPhotoOf(deleted!);
      }
    }),
  );
  return true;
}

Future<void> _restore(
  ScaffoldMessengerState messenger,
  DeletedPlace deleted,
) async {
  try {
    await PlaceStore.instance.restoreDeleted(deleted);
  } catch (error) {
    debugPrint('deleteFindWithUndo: restore failed: $error');
    if (messenger.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't restore — try again")),
      );
    }
  }
}
