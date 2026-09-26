import 'package:flutter/material.dart';

import '../data/shared_board_store.dart';
import '../services/board_invite_link.dart';
import 'sign_in_gate.dart';

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

  final signedIn = await ensureSignedInForSharing(
    context,
    title: 'Open a shared board',
    message: 'Sign in to join this board. It will appear in your Boards tab.',
  );
  if (!signedIn) return;

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
