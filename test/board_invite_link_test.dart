import 'dart:math';

import 'package:cheaptripchip/services/board_invite_link.dart';
import 'package:flutter_test/flutter_test.dart';

const _invite = BoardInvite(
  boardId: 'Ab12_-xyz',
  code: 'k9Zq2LmN8pR4sT6vW0xY1aB3',
);

void main() {
  test('https link round-trips', () {
    final uri = BoardInviteLink.https(_invite.boardId, _invite.code);
    expect(
      uri.toString(),
      'https://cheaptripchip-api.vercel.app/b/Ab12_-xyz?c=k9Zq2LmN8pR4sT6vW0xY1aB3',
    );
    expect(BoardInviteLink.parse(uri), _invite);
  });

  test('custom-scheme link round-trips', () {
    final uri = BoardInviteLink.appLink(_invite.boardId, _invite.code);
    expect(
      uri.toString(),
      'cheaptripchip://board/Ab12_-xyz?c=k9Zq2LmN8pR4sT6vW0xY1aB3',
    );
    expect(BoardInviteLink.parse(uri), _invite);
  });

  test('rejects other hosts, paths, schemes and malformed tokens', () {
    for (final link in [
      'https://evil.example/b/Ab12?c=k9Zq2LmN8pR4sT6vW0xY1aB3',
      'https://cheaptripchip-api.vercel.app/x/Ab12?c=k9Zq2LmN8pR4sT6vW0xY1aB3',
      'https://cheaptripchip-api.vercel.app/b/Ab12/extra?c=abc',
      'https://cheaptripchip-api.vercel.app/b/Ab12',
      'https://cheaptripchip-api.vercel.app/b/Ab%2012?c=abc',
      'cheaptripchip://import?v=1&d=xyz',
      'cheaptripchip://board/Ab12?c=bad%20code',
      'cheaptripchip://board/?c=abc',
      'ftp://cheaptripchip-api.vercel.app/b/Ab12?c=abc',
    ]) {
      expect(BoardInviteLink.parse(Uri.parse(link)), isNull, reason: link);
    }
  });

  test('fromText finds the link inside a shared message', () {
    const text =
        'Join my board “Tokyo” on CheapTripChip:\n'
        'https://cheaptripchip-api.vercel.app/b/Ab12_-xyz?c=k9Zq2LmN8pR4sT6vW0xY1aB3';
    expect(BoardInviteLink.fromText(text), _invite);
    expect(BoardInviteLink.fromText('https://instagram.com/reel/abc'), isNull);
  });

  test('generated codes are long enough for the rules and URL-safe', () {
    final a = BoardInviteLink.generateCode(Random(1));
    final b = BoardInviteLink.generateCode(Random(2));
    expect(a.length, greaterThanOrEqualTo(22));
    expect(a, matches(RegExp(r'^[A-Za-z0-9]+$')));
    expect(a, isNot(b));
    expect(BoardInviteLink.parse(BoardInviteLink.https('id', a))?.code, a);
  });
}
