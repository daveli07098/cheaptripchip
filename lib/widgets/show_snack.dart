import 'package:flutter/material.dart';

/// Shows [message] in a plain [SnackBar] on the nearest messenger. Callers
/// after an `await` should check `context.mounted` first (or capture the
/// messenger before the gap).
void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
