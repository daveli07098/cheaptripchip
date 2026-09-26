import 'package:cheaptripchip/widgets/app_version_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  testWidgets('shows the installed version and build number', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'cheaptripchip',
      packageName: 'com.cheaptripchip.cheaptripchip',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppVersionLabel())),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Version 1.0.0 (1)'), findsOneWidget);
  });
}
