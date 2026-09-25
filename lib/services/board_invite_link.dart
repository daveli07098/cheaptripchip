import 'dart:math';

/// A parsed shared-board invite: open [boardId], proving the link with
/// [code] (the board's current `inviteCode`).
class BoardInvite {
  const BoardInvite({required this.boardId, required this.code});

  final String boardId;
  final String code;

  @override
  bool operator ==(Object other) =>
      other is BoardInvite && other.boardId == boardId && other.code == code;

  @override
  int get hashCode => Object.hash(boardId, code);

  @override
  String toString() => 'BoardInvite($boardId)';
}

/// Builds and parses shared-board invite links in both forms:
///
/// - `https://cheaptripchip-api.vercel.app/b/{boardId}?c={code}` — what
///   people share. Android App Links open the app directly; otherwise the
///   server's `/b/` page (server/lib/board_page.ts) offers "Open in
///   CheapTripChip".
/// - `cheaptripchip://board/{boardId}?c={code}` — the custom scheme that
///   page's button uses (and iOS until universal links are set up).
class BoardInviteLink {
  BoardInviteLink._();

  static const host = 'cheaptripchip-api.vercel.app';
  static const scheme = 'cheaptripchip';
  static const appLinkHost = 'board';

  /// Minimum length of a generated [inviteCode] — firestore.rules rejects
  /// codes shorter than 22.
  static const codeLength = 24;

  static final _token = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
  static const _alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  /// A fresh random invite code ([codeLength] base-62 chars, ~143 bits).
  static String generateCode([Random? random]) {
    final rng = random ?? Random.secure();
    return String.fromCharCodes(
      List.generate(
        codeLength,
        (_) => _alphabet.codeUnitAt(rng.nextInt(_alphabet.length)),
      ),
    );
  }

  static Uri https(String boardId, String code) =>
      Uri.https(host, '/b/$boardId', {'c': code});

  static Uri appLink(String boardId, String code) => Uri(
    scheme: scheme,
    host: appLinkHost,
    path: '/$boardId',
    queryParameters: {'c': code},
  );

  /// The invite in [uri], or null when it isn't a well-formed board link.
  static BoardInvite? parse(Uri uri) {
    final String? boardId;
    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host == host &&
        uri.pathSegments.length == 2 &&
        uri.pathSegments.first == 'b') {
      boardId = uri.pathSegments[1];
    } else if (uri.scheme == scheme &&
        uri.host == appLinkHost &&
        uri.pathSegments.length == 1) {
      boardId = uri.pathSegments.first;
    } else {
      return null;
    }
    final code = uri.queryParameters['c'];
    if (code == null || !_token.hasMatch(boardId) || !_token.hasMatch(code)) {
      return null;
    }
    return BoardInvite(boardId: boardId, code: code);
  }

  static final _urlPattern = RegExp(
    r'(?:https?://cheaptripchip-api\.vercel\.app/b/|cheaptripchip://board/)\S+',
  );

  /// The first invite link found in shared [text] (e.g. "Join my board …
  /// https://…/b/…?c=…" arriving through the share sheet), or null.
  static BoardInvite? fromText(String text) {
    for (final match in _urlPattern.allMatches(text)) {
      final uri = Uri.tryParse(match.group(0)!);
      final invite = uri == null ? null : parse(uri);
      if (invite != null) return invite;
    }
    return null;
  }
}
