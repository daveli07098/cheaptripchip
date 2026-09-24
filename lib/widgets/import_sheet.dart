import 'package:flutter/material.dart';

import '../services/import_service.dart';
import '../services/trip_share.dart';
import '../theme/app_theme.dart';

/// Preview of an incoming shared [TripBundle] with Import / Cancel. Confirming
/// runs [ImportService.importBundle]; [show] resolves to its result, or null
/// when the user cancels.
class ImportSheet extends StatefulWidget {
  const ImportSheet({super.key, required this.bundle});

  final TripBundle bundle;

  static Future<ImportResult?> show(BuildContext context, TripBundle bundle) {
    return showModalBottomSheet<ImportResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ImportSheet(bundle: bundle),
    );
  }

  @override
  State<ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<ImportSheet> {
  bool _busy = false;

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final result = await ImportService.importBundle(widget.bundle);
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      debugPrint('import failed: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('Import failed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bundle = widget.bundle;
    final count = bundle.places.length;
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Import “${bundle.title}” — $count '
                '${count == 1 ? 'place' : 'places'}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Adds a new board. Places you already saved are reused, '
                'not duplicated.',
                style: TextStyle(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: count,
                  itemBuilder: (context, i) {
                    final place = bundle.places[i];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Semantics(
                        label: place.category.labelEn,
                        child: ExcludeSemantics(
                          child: Text(
                            place.category.emoji,
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                      ),
                      title: Text(
                        place.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: place.areaLabel.isEmpty
                          ? null
                          : Text(place.areaLabel),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy || count == 0 ? null : _import,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.coral,
                      ),
                      child: Text(_busy ? 'Importing…' : 'Import'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Import from link" dialog: paste a `cheaptripchip://import` link (or a
/// whole shared message containing one). Resolves to the decoded bundle, or
/// null when cancelled. Works on every platform, including web.
class ImportLinkDialog extends StatefulWidget {
  const ImportLinkDialog({super.key});

  static Future<TripBundle?> show(BuildContext context) {
    return showDialog<TripBundle>(
      context: context,
      builder: (_) => const ImportLinkDialog(),
    );
  }

  @override
  State<ImportLinkDialog> createState() => _ImportLinkDialogState();
}

class _ImportLinkDialogState extends State<ImportLinkDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final bundle = TripShare.fromText(_controller.text);
    if (bundle == null) {
      setState(() => _error = 'That doesn\'t look like a Cheaptripchip link');
    } else {
      Navigator.pop(context, bundle);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import from link'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 1,
        maxLines: 4,
        decoration: InputDecoration(
          hintText: 'Paste a shared link or message',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Continue')),
      ],
    );
  }
}
