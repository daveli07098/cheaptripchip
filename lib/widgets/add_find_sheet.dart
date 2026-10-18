import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/place_store.dart';
import '../models/place.dart';
import '../screens/place_detail_sheet.dart';
import '../services/duplicate_matcher.dart';
import '../services/geocoding_service.dart';
import '../services/image_prep.dart';
import '../services/place_extractor.dart';
import '../theme/app_theme.dart';
import 'accessible_emoji.dart';
import 'show_snack.dart';

/// What the user chose in the "Already saved" dialog.
enum DuplicateChoice { open, merge, saveAnyway }

/// The "Add a find" sheet: paste a link or caption (or pick a screenshot) →
/// Gemini extraction → geocode → saved to the store and shown on the
/// map/feed.
///
/// A post listing several places shows a checklist (all ticked) first; a
/// low-confidence or ambiguous place asks "Which one?" before it is saved;
/// a place that is already saved offers open / merge / save anyway. A
/// single confident new place saves straight away and opens its page.
class AddFindSheet extends StatefulWidget {
  const AddFindSheet({
    super.key,
    this.initialText = '',
    this.autoExtract = false,
    this.initialImage,
    this.extractor,
    this.pickImage,
  });

  final String initialText;

  /// Starts extracting [initialText] as soon as the sheet opens (web link
  /// intake), instead of waiting for the user to tap the button.
  final bool autoExtract;

  /// An image shared into the app (Android share sheet) — extracted as a
  /// screenshot as soon as the sheet opens.
  final Uint8List? initialImage;

  /// Test seams; default to a real [PlaceExtractor] and the gallery picker.
  final PlaceExtractor? extractor;
  final Future<Uint8List?> Function()? pickImage;

  @override
  State<AddFindSheet> createState() => _AddFindSheetState();
}

class _AddFindSheetState extends State<AddFindSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  late final PlaceExtractor _extractor = widget.extractor ?? PlaceExtractor();
  bool _busy = false;
  String _busyLabel = 'Extracting…';
  String? _error;

  /// The caption couldn't be read (IG login wall, private post) — offer the
  /// screenshot route instead.
  bool _offerScreenshot = false;

  /// Multi-place review: the extraction and which rows are ticked.
  ExtractionResult? _review;
  final Set<int> _checked = {};

  @override
  void initState() {
    super.initState();
    final image = widget.initialImage;
    if (image != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _extractImage(image);
      });
    } else if (widget.autoExtract && widget.initialText.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _extract();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    // An injected extractor belongs to the caller.
    if (widget.extractor == null) _extractor.dispose();
    super.dispose();
  }

  Future<void> _extract() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;
    await _run('Extracting…', () => _extractor.extractAll(input));
  }

  Future<void> _pickScreenshot() async {
    final Uint8List? bytes;
    try {
      bytes = await (widget.pickImage ?? _pickFromGallery)();
    } catch (e) {
      debugPrint('screenshot pick failed: $e');
      if (mounted) setState(() => _error = "Couldn't open your photos.");
      return;
    }
    if (bytes == null || !mounted) return; // cancelled
    await _extractImage(bytes);
  }

  static Future<Uint8List?> _pickFromGallery() async {
    // The platform picker downscales and JPEG-re-encodes, so the result is
    // usually already within ImagePrep's limits.
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: ImagePrep.maxDimension.toDouble(),
      maxHeight: ImagePrep.maxDimension.toDouble(),
      imageQuality: 85,
    );
    return file?.readAsBytes();
  }

  Future<void> _extractImage(Uint8List raw) async {
    await _run('Reading screenshot…', () async {
      final image = await ImagePrep.prepare(raw);
      return _extractor.extractFromImage(
        image.bytes,
        mimeType: image.mimeType,
        hint: _controller.text,
      );
    });
  }

  Future<void> _run(
    String label,
    Future<ExtractionResult> Function() extraction,
  ) async {
    setState(() {
      _busy = true;
      _busyLabel = label;
      _error = null;
      _offerScreenshot = false;
    });
    try {
      final result = await extraction();
      if (!mounted) return;
      if (result.places.length == 1) {
        await _save(result, const [0]);
      } else {
        setState(() {
          _review = result;
          _checked
            ..clear()
            ..addAll(List.generate(result.places.length, (i) => i));
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendly(e);
        _offerScreenshot = e is CaptionUnavailableException;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Saves [indices] of [result]: confirms each low-confidence pick, checks
  /// each against saved places, then closes the sheet and opens the place
  /// (one) or reports the count (several).
  Future<void> _save(ExtractionResult result, List<int> indices) async {
    final store = PlaceStore.instance;
    final toSave = <Place>[];
    Place? toOpen;
    var merged = 0;
    for (final i in indices) {
      final item = result.places[i];
      final place = item.needsConfirmation
          ? await _confirmWhich(item)
          : item.place;
      if (!mounted) return;
      if (place == null) continue; // "None of these" / dismissed

      final dup = DuplicateMatcher.findDuplicate(place, [
        ...toSave,
        ...store.places.value,
      ]);
      if (dup != null) {
        final choice = await _askDuplicate(place, dup);
        if (!mounted) return;
        if (choice == null) continue;
        if (choice == DuplicateChoice.open) {
          toOpen ??= dup;
          continue;
        }
        if (choice == DuplicateChoice.merge) {
          if (toSave.contains(dup)) continue; // same place twice in one post
          final note = DuplicateMatcher.mergeNote(
            dup,
            sourceUrl: result.sourceUrl,
            via: place.sourceHandle,
          );
          if (note != null) await store.addNote(dup.id, note);
          merged++;
          toOpen ??= dup;
          continue;
        }
      }
      toSave.add(place);
    }
    if (!mounted) return;

    if (toSave.length == 1) {
      store.add(toSave.first);
    } else if (toSave.length > 1) {
      store.addAll(toSave);
    }

    if (toSave.isEmpty && toOpen == null) {
      // Nothing confirmed — stay on the sheet so the user can try again.
      setState(() => _error = 'Nothing saved.');
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.pop(context);
    if (toSave.length == 1 && merged == 0) {
      PlaceDetailSheet.show(context, toSave.first);
    } else if (toSave.isEmpty && merged <= 1) {
      if (merged == 1) {
        messenger?.showSnackBar(
          SnackBar(content: Text('Added this post to “${toOpen!.name}”')),
        );
      }
      PlaceDetailSheet.show(context, toOpen!);
    } else {
      final parts = [
        if (toSave.isNotEmpty)
          'Saved ${toSave.length} find${toSave.length == 1 ? '' : 's'}',
        if (merged > 0) 'merged $merged into saved places',
      ];
      messenger?.showSnackBar(SnackBar(content: Text(parts.join(', '))));
    }
  }

  /// "Which one?" for a low-confidence or ambiguous [item]: the best guess
  /// (or each distinct geocode match), Gemini's alternatives, or none.
  Future<Place?> _confirmWhich(ExtractedPlace item) async {
    final base = item.place;
    final geo = item.geocodeAmbiguous
        ? item.geocodeCandidates
        : const <GeocodeCandidate>[];
    final choice = await showDialog<Object>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Which one?'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              item.geocodeAmbiguous
                  ? '“${base.name}” matches more than one place.'
                  : 'Not sure about “${base.name}” '
                        '(${(item.confidence * 100).round()}% sure).',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (geo.isEmpty)
            _option(context, base.category, base.name, base.areaDisplay, base)
          else
            for (final c in geo)
              _option(
                context,
                base.category,
                base.name,
                c.displayName.isEmpty ? base.areaDisplay : c.displayName,
                GeocodeCandidateChoice(c),
              ),
          for (final alt in item.alternatives)
            _option(context, base.category, alt.name, alt.subtitle, alt),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('None of these — skip'),
            ),
          ),
        ],
      ),
    );
    if (choice is Place) return choice.copyWith(matchConfident: true);
    if (choice is GeocodeCandidateChoice) {
      return _extractor.placeAt(item, choice.candidate);
    }
    if (choice is PlaceAlternative) {
      final resolved = await _extractor.resolveAlternative(item, choice);
      if (resolved == null && mounted) {
        showSnack(context, "Couldn't locate “${choice.name}” — skipped.");
      }
      return resolved;
    }
    return null;
  }

  Widget _option(
    BuildContext context,
    PlaceCategory category,
    String title,
    String subtitle,

    /// What the dialog returns: a [Place], [PlaceAlternative] or
    /// [GeocodeCandidateChoice].
    Object value,
  ) {
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(context, value),
      child: Row(
        children: [
          AccessibleEmoji(
            emoji: category.emoji,
            label: category.labelEn,
            fontSize: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<DuplicateChoice?> _askDuplicate(Place place, Place existing) =>
      showDialog<DuplicateChoice>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Already saved'),
          content: Text(
            '“${existing.name}” (${existing.areaDisplay}) is already in your '
            'finds. Merge adds this post to it as a note.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, DuplicateChoice.open),
              child: const Text('Open it'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, DuplicateChoice.saveAnyway),
              child: const Text('Save anyway'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, DuplicateChoice.merge),
              child: const Text('Merge'),
            ),
          ],
        ),
      );

  String _friendly(Object e) {
    debugPrint('extraction error: $e');
    if (e is CaptionUnavailableException) {
      return "Couldn't read this post's caption (it may be private or behind "
          "Instagram's login). Paste the caption or place name too, or use a "
          'screenshot.';
    }
    if (e is NoPlaceFoundException) {
      return "Couldn't find a place in this post. "
          'Add the place name and try again.';
    }
    if (e is ImageTooLargeException) {
      return 'That image is too large to read. Try cropping the screenshot.';
    }
    if (e is UnsupportedImageException) {
      return "Couldn't read that image. Try a PNG or JPEG screenshot.";
    }
    final msg = e.toString();
    if (msg.contains('GEMINI_API_KEY')) {
      return 'No Gemini key set. Run with '
          '--dart-define=GEMINI_API_KEY=your_key to enable extraction.';
    }
    if (msg.contains('413')) {
      return 'That screenshot is too large to send. Try cropping it.';
    }
    if (msg.contains('403') ||
        msg.contains('API_KEY_SERVICE_BLOCKED') ||
        msg.contains('are blocked')) {
      return 'The Gemini key isn\'t allowed to use this API yet. In Google '
          'Cloud Console → Credentials → this key → API restrictions, add '
          '"Generative Language API".';
    }
    // Strip the leading `Exception: ` prefix `Exception.toString()` adds,
    // so the user sees the underlying message, not Dart plumbing.
    final stripped = msg.startsWith('Exception: ')
        ? msg.substring('Exception: '.length)
        : msg;
    return 'Extraction failed: $stripped';
  }

  Widget _busyIcon(BuildContext context) => SizedBox(
    width: 18,
    height: 18,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: Theme.of(context).colorScheme.onPrimary,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final review = _review;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: review == null ? _buildInput(context) : _buildReview(review),
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    final muted = Theme.of(
      context,
    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.65);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Add a find',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Paste an Instagram/TikTok link (and its caption for best results), '
          'or add a screenshot. Gemini extracts the places, we map them and '
          'write a summary.',
          style: TextStyle(color: muted, height: 1.4),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          maxLines: 4,
          minLines: 2,
          enabled: !_busy,
          decoration: const InputDecoration(
            hintText:
                'https://instagram.com/reel/...\n\nPaste the caption here too',
            alignLabelWithHint: true,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: const TextStyle(color: AppTheme.coral, fontSize: 13),
          ),
          if (_offerScreenshot) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickScreenshot,
              icon: const Icon(Icons.screenshot_outlined, size: 18),
              label: const Text('Use a screenshot instead'),
            ),
          ],
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _extract,
          icon: _busy
              ? _busyIcon(context)
              : const Icon(Icons.auto_awesome, size: 18),
          label: Text(_busy ? _busyLabel : 'Extract & save'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.coral,
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _busy ? null : _pickScreenshot,
          icon: const Icon(Icons.image_outlined, size: 18),
          label: const Text('Add from screenshot'),
          style: TextButton.styleFrom(
            minimumSize: const Size(double.infinity, 44),
          ),
        ),
      ],
    );
  }

  Widget _buildReview(ExtractionResult review) {
    final count = _checked.length;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.5;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${review.places.length} places in this post',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Untick any you don’t want to save.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: review.places.length,
              itemBuilder: (context, i) {
                final item = review.places[i];
                final p = item.place;
                return CheckboxListTile(
                  value: _checked.contains(i),
                  onChanged: _busy
                      ? null
                      : (v) => setState(
                          () =>
                              v == true ? _checked.add(i) : _checked.remove(i),
                        ),
                  secondary: AccessibleEmoji(
                    emoji: p.category.emoji,
                    label: p.category.labelEn,
                    fontSize: 22,
                  ),
                  title: Text(p.name),
                  subtitle: Text(
                    item.needsConfirmation
                        ? '${p.areaDisplay} · not sure — you’ll pick'
                        : p.areaDisplay,
                  ),
                  contentPadding: EdgeInsets.zero,
                );
              },
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: const TextStyle(color: AppTheme.coral, fontSize: 13),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy || count == 0
              ? null
              : () async {
                  setState(() {
                    _busy = true;
                    _busyLabel = 'Saving…';
                    _error = null;
                  });
                  try {
                    await _save(review, _checked.toList()..sort());
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          icon: _busy
              ? _busyIcon(context)
              : const Icon(Icons.bookmark_add_outlined, size: 18),
          label: Text(
            _busy ? _busyLabel : 'Save $count find${count == 1 ? '' : 's'}',
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.coral,
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
        TextButton(
          onPressed: _busy ? null : () => setState(() => _review = null),
          style: TextButton.styleFrom(
            minimumSize: const Size(double.infinity, 44),
          ),
          child: const Text('Back'),
        ),
      ],
    );
  }
}

/// Wraps a [GeocodeCandidate] picked in "Which one?" so the dialog's result
/// type can be told apart from a [Place] or [PlaceAlternative].
class GeocodeCandidateChoice {
  const GeocodeCandidateChoice(this.candidate);

  final GeocodeCandidate candidate;
}
