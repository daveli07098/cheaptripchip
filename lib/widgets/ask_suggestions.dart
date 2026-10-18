import 'package:flutter/material.dart';

import '../services/ai_search.dart';

/// "Ask your places" chips under the search pill, shown while the field is
/// focused: with no text, [suggestions] (grounded in the user's places, see
/// [askSuggestionsFor]); with question-like text ([looksLikeQuestion]), a
/// single "Ask “…”" chip. Tapping one calls [onAsk] with its text.
///
/// Inside a [TextFieldTapRegion], so tapping a chip doesn't count as a tap
/// outside the field (which would unfocus it first and hide the row).
class AskSuggestions extends StatelessWidget {
  const AskSuggestions({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.suggestions,
    required this.onAsk,
    this.padding = EdgeInsets.zero,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String> suggestions;
  final ValueChanged<String> onAsk;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([focusNode, controller]),
      builder: (context, _) {
        if (!focusNode.hasFocus) return const SizedBox.shrink();
        final text = controller.text.trim();
        final chips = text.isEmpty
            ? suggestions
            : (looksLikeQuestion(text) ? [text] : const <String>[]);
        if (chips.isEmpty) return const SizedBox.shrink();
        final asking = text.isNotEmpty;
        return TextFieldTapRegion(
          child: Padding(
            padding: padding,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final chip in chips)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _AskChip(
                        label: asking ? 'Ask “$chip”' : chip,
                        semanticsLabel: 'Ask your places: $chip',
                        onTap: () => onAsk(chip),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AskChip extends StatelessWidget {
  const _AskChip({
    required this.label,
    required this.semanticsLabel,
    required this.onTap,
  });

  final String label;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: ActionChip(
        avatar: Icon(Icons.auto_awesome, size: 16, color: scheme.primary),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        backgroundColor: scheme.surface,
        elevation: 1,
        shape: const StadiumBorder(),
        onPressed: onTap,
      ),
    );
  }
}
