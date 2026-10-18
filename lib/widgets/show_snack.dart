import 'package:flutter/material.dart';

/// Shows [message] in a plain [SnackBar] on the nearest messenger. Callers
/// after an `await` should check `context.mounted` first (or capture the
/// messenger before the gap).
void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// The app's one wording for a failed action: "Couldn't {verb} — try
/// again" (e.g. `errorMessage('save')`). For callers that hold a
/// [ScaffoldMessengerState] rather than a context (grabbed before an
/// `await`); everyone else uses [showError].
String errorMessage(String verb) => "Couldn't $verb — try again";

/// [showSnack] with [errorMessage] — use for every error SnackBar so failed
/// actions read the same everywhere.
void showError(BuildContext context, String verb) =>
    showSnack(context, errorMessage(verb));
