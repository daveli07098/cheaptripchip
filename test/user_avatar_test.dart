import 'package:cheaptripchip/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('no photo: shows the upper-cased initial', (tester) async {
    await _pump(tester, const UserAvatar(photoUrl: null, name: ' alice'));
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('blank name: falls back to "?"', (tester) async {
    await _pump(tester, const UserAvatar(photoUrl: '', name: '  '));
    expect(find.text('?'), findsOneWidget);
  });

  testWidgets('sized by radius', (tester) async {
    await _pump(
      tester,
      const UserAvatar(photoUrl: null, name: 'Bo', radius: 24),
    );
    expect(tester.getSize(find.byType(CircleAvatar)), const Size(48, 48));
  });

  test('initialOf handles non-Latin names by grapheme', () {
    expect(UserAvatar.initialOf('陳大文'), '陳');
    expect(UserAvatar.initialOf(''), '?');
  });
}
