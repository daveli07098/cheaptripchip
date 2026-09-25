import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/import_service.dart';
import '../services/my_maps_import.dart';
import '../theme/app_theme.dart';

/// Downloads and parses map [mid]. Parsing a large export (1.3 MB, ~1,700
/// placemarks) takes a few hundred ms, so it runs in a background isolate
/// via [compute] (inline on web, where fetching fails first anyway).
Future<MyMapsDocument> loadMyMap(String mid) async {
  final xml = await fetchKml(mid);
  try {
    return await compute(parseMyMapsKml, xml);
  } on FormatException catch (e) {
    debugPrint('My Maps KML unreadable: $e');
    throw const MyMapsImportException(
      "That link didn't return a readable map. Check it and try again.",
    );
  }
}

/// Thousands separators for counts ("1,721").
String _formatCount(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// "Import from Google My Maps" — paste dialog. Resolves to the map id, or
/// null when cancelled. Prefills from the clipboard when it holds a My Maps
/// link.
class MyMapsLinkDialog extends StatefulWidget {
  const MyMapsLinkDialog({super.key});

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (_) => const MyMapsLinkDialog(),
    );
  }

  @override
  State<MyMapsLinkDialog> createState() => _MyMapsLinkDialogState();
}

class _MyMapsLinkDialogState extends State<MyMapsLinkDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefillFromClipboard();
  }

  Future<void> _prefillFromClipboard() async {
    try {
      final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (!mounted || text == null || _controller.text.isNotEmpty) return;
      if (text.contains('maps/d/') && parseMyMapsId(text) != null) {
        _controller.text = text.trim();
      }
    } catch (e) {
      // Clipboard access is best-effort (denied / unavailable in tests).
      debugPrint('clipboard unavailable: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final mid = parseMyMapsId(_controller.text);
    if (mid == null) {
      setState(() => _error = "That doesn't look like a Google My Maps link");
    } else {
      Navigator.pop(context, mid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import from Google My Maps'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 1,
        maxLines: 4,
        decoration: InputDecoration(
          hintText: 'https://www.google.com/maps/d/…?mid=…',
          helperText: 'The map must be shared: anyone with the link can view.',
          helperMaxLines: 2,
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

/// Loads map [mid] (spinner), then previews it: title, total, one checkbox
/// per layer, and the board name (default "temp"). Import runs
/// [ImportService.importMyMaps]; [show] resolves to its result, or null
/// when the user cancels. [loader] is a test seam.
class MyMapsImportSheet extends StatefulWidget {
  const MyMapsImportSheet({super.key, required this.mid, this.loader});

  final String mid;
  final Future<MyMapsDocument> Function(String mid)? loader;

  static Future<ImportResult?> show(BuildContext context, String mid) {
    return showModalBottomSheet<ImportResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: MyMapsImportSheet(mid: mid),
      ),
    );
  }

  @override
  State<MyMapsImportSheet> createState() => _MyMapsImportSheetState();
}

class _MyMapsImportSheetState extends State<MyMapsImportSheet> {
  final _nameController = TextEditingController(
    text: ImportService.defaultMyMapsBoardName,
  );
  MyMapsDocument? _map;
  List<bool> _selected = const [];
  String? _error;
  bool _importing = false;
  bool _skipAreaLabels = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final map = await (widget.loader ?? loadMyMap)(widget.mid);
      if (!mounted) return;
      setState(() {
        _map = map;
        _selected = List.filled(map.folders.length, true);
      });
    } catch (e) {
      debugPrint('My Maps load failed: $e');
      if (!mounted) return;
      setState(
        () => _error = e is MyMapsImportException
            ? e.message
            : "Couldn't read this map. Try again later.",
      );
    }
  }

  int get _selectedCount {
    final map = _map;
    if (map == null) return 0;
    var n = 0;
    for (var i = 0; i < map.folders.length; i++) {
      if (!_selected[i]) continue;
      final folder = map.folders[i];
      n += folder.count - (_skipAreaLabels ? folder.areaLabelCount : 0);
    }
    return n;
  }

  Future<void> _import() async {
    final map = _map;
    if (map == null) return;
    setState(() => _importing = true);
    try {
      final result = await ImportService.importMyMaps(
        map,
        folders: [
          for (var i = 0; i < map.folders.length; i++)
            if (_selected[i]) map.folders[i],
        ],
        boardName: _nameController.text,
        skipAreaLabels: _skipAreaLabels,
      );
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      debugPrint('My Maps import failed: $e');
      if (!mounted) return;
      setState(() {
        _importing = false;
        _error = 'Import failed. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final map = _map;
    final Widget body;
    if (map == null && _error == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading map…'),
          ],
        ),
      );
    } else if (map == null) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Import from Google My Maps',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppTheme.coral)),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    } else {
      body = _preview(context, map, colors);
    }
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: body,
        ),
      ),
    );
  }

  Widget _preview(BuildContext context, MyMapsDocument map, ColorScheme c) {
    final total = map.placeCount;
    final layers = map.folders.length;
    final count = _selectedCount;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          map.title.isEmpty ? 'Untitled map' : map.title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          '${_formatCount(total)} ${total == 1 ? 'place' : 'places'} in '
          '$layers ${layers == 1 ? 'layer' : 'layers'}',
          style: TextStyle(color: c.onSurfaceVariant.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: layers,
            itemBuilder: (context, i) {
              final folder = map.folders[i];
              return CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _selected[i],
                onChanged: _importing
                    ? null
                    : (v) => setState(() => _selected[i] = v ?? false),
                title: Text(folder.name),
                secondary: Text(_formatCount(folder.count)),
              );
            },
          ),
        ),
        if (map.areaLabelCount > 0)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _skipAreaLabels,
            onChanged: _importing
                ? null
                : (v) => setState(() => _skipAreaLabels = v ?? true),
            title: Text(
              'Skip area labels (${_formatCount(map.areaLabelCount)})',
            ),
            subtitle: const Text('Pins like 東京都 or 千葉市 that only name an area'),
          ),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          enabled: !_importing,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Board name'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: AppTheme.coral)),
        ],
        if (_importing) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _importing ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _importing || count == 0 ? null : _import,
                style: FilledButton.styleFrom(backgroundColor: AppTheme.coral),
                child: Text(
                  _importing ? 'Importing…' : 'Import ${_formatCount(count)}',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
