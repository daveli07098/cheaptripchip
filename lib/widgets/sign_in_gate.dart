import 'dart:async';

import 'package:flutter/material.dart';

import '../data/shared_board_store.dart';
import '../services/auth_service.dart';
import 'confirm_dialog.dart';

/// Gate for shared-board actions: resolves true once the user is signed in
/// and [SharedBoardStore] is bound, so the caller can carry on with what it
/// was doing (share the board, join the invite) without a second tap.
///
/// Already signed in → true at once. Otherwise asks with [title]/[message]
/// ("Not now" / "Sign in"), signs in with Google, and waits for the store to
/// bind. Every failure (sign-in not set up in this build, the user
/// declining, a provider error, a bind timeout) resolves false, with a
/// SnackBar for everything but declining.
Future<bool> ensureSignedInForSharing(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  if (SharedBoardStore.instance.uid != null) return true;
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));

  if (!AuthService.instance.isConfigured) {
    say("Shared boards need sign-in, which isn't set up in this build.");
    return false;
  }
  final signIn = await showConfirmDialog(
    context,
    title: title,
    body: message,
    action: 'Sign in',
    cancel: 'Not now',
    destructive: false,
  );
  if (!signIn) return false;
  try {
    await AuthService.instance.signInWithGoogle();
  } on AuthException catch (e) {
    say(e.message);
    return false;
  }
  if (!await _waitUntilBound()) {
    say("Couldn't finish signing in. Try again.");
    return false;
  }
  return true;
}

/// Waits (up to 10 s) for the auth change to bind [SharedBoardStore] —
/// main.dart's auth listener runs before this one, so the store is bound
/// by the time the user shows up here.
Future<bool> _waitUntilBound() async {
  if (SharedBoardStore.instance.uid != null) return true;
  final completer = Completer<bool>();
  void check() {
    if (SharedBoardStore.instance.uid != null && !completer.isCompleted) {
      completer.complete(true);
    }
  }

  AuthService.instance.user.addListener(check);
  try {
    return await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => SharedBoardStore.instance.uid != null,
    );
  } finally {
    AuthService.instance.user.removeListener(check);
  }
}
