import 'package:flutter/material.dart';

/// Two-button confirmation dialog; resolves true only when [action] is
/// tapped (Cancel, back or a barrier tap resolve false).
///
/// [destructive] actions get an error-coloured text button; otherwise the
/// action is a [FilledButton].
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
  String cancel = 'Cancel',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(cancel),
        ),
        if (destructive)
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(action),
          )
        else
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(action),
          ),
      ],
    ),
  );
  return result == true;
}
