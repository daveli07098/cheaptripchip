import 'dart:async';

import 'package:flutter/material.dart';

import '../data/shared_board_store.dart';
import '../services/auth_service.dart';
import '../services/board_invite_link.dart';

/// Opens a shared-board [invite] (from an https or cheaptripchip:// link):
/// signs in first when needed, joins with the link's role, then calls
/// [onShowBoards] so the shell can switch to the Boards tab.
Future<void> openBoardInvite(
  BuildContext context,
  BoardInvite invite, {
  required VoidCallback onShowBoards,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));

  if (SharedBoardStore.instance.uid == null) {
    if (!AuthService.instance.isConfigured) {
      say("Shared boards need sign-in, which isn't set up in this build.");
      return;
    }
    final signIn = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Open a shared board'),
        content: const Text(
          'Sign in to join this board. It will appear in your Boards tab.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
    if (signIn != true) return;
    try {
      await AuthService.instance.signInWithGoogle();
    } on AuthException catch (e) {
      say(e.message);
      return;
    }
    if (!await _waitUntilBound()) {
      say("Couldn't finish signing in. Open the link again.");
      return;
    }
  }

  try {
    final (result, board) = await SharedBoardStore.instance.join(invite);
    final name = board == null ? 'the board' : '“${board.name}”';
    switch (result) {
      case JoinResult.joined:
        onShowBoards();
        say('Joined $name');
      case JoinResult.alreadyMember:
        onShowBoards();
        say("You're already on $name");
      case JoinResult.invalid:
        say(
          'This invite link no longer works — it may have been reset or '
          'turned off. Ask for a new one.',
        );
      case JoinResult.signedOut:
        say('Sign in to open shared boards.');
    }
  } catch (e) {
    debugPrint('join board failed: $e');
    say("Couldn't open the board. Check your connection and try again.");
  }
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
