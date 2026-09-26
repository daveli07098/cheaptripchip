import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// Opens the system share sheet for [params]; if the platform refuses,
/// says so in a SnackBar rather than failing silently.
Future<void> shareOrReport(BuildContext context, ShareParams params) async {
  // Grabbed before the await — the caller's sheet may be gone by then.
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await SharePlus.instance.share(params);
  } catch (e) {
    debugPrint('Share failed: $e');
    messenger?.showSnackBar(
      const SnackBar(content: Text('Could not open the share sheet')),
    );
  }
}
