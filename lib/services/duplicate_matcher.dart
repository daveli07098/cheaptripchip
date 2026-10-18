import 'package:latlong2/latlong.dart';

import '../models/place.dart';

/// Save-time duplicate check for the add-a-find sheet: is this freshly
/// extracted place already in the user's saved places?
///
/// A match is either
/// - the same normalized name within [sameNameRadiusMeters] (so a chain's
///   branch in another city isn't flagged), or
/// - a similar name within [nearbyRadiusMeters] ("Ichiran Shibuya" vs
///   "一蘭 (Ichiran)" pinned on the same corner).
///
/// Separate from `ImportService.isDuplicate` (exact name, 50 m), which
/// silently reuses places during a trip import; this one only *offers* the
/// match — the user picks open / save anyway / merge.
class DuplicateMatcher {
  DuplicateMatcher._();

  static const nearbyRadiusMeters = 80.0;
  static const sameNameRadiusMeters = 30000.0;

  /// Token-overlap (of the shorter name's tokens) that counts as "similar".
  static const similarTokenOverlap = 0.5;

  static const _distance = Distance();

  /// The first of [existing] that [candidate] duplicates, or null. Ignores a
  /// place with [candidate]'s own id.
  static Place? findDuplicate(Place candidate, Iterable<Place> existing) {
    final name = normalizeName(candidate.name);
    if (name.isEmpty) return null;
    Place? nearbySimilar;
    for (final p in existing) {
      if (p.id == candidate.id) continue;
      final meters = _distance.as(
        LengthUnit.Meter,
        candidate.location,
        p.location,
      );
      if (normalizeName(p.name) == name && meters <= sameNameRadiusMeters) {
        return p;
      }
      if (nearbySimilar == null &&
          meters <= nearbyRadiusMeters &&
          isSimilarName(candidate.name, p.name)) {
        nearbySimilar = p;
      }
    }
    return nearbySimilar;
  }

  /// Lowercase, with punctuation and whitespace removed: "Ramen  Bon!" and
  /// "ramen-bon" both become "ramenbon". Letters/digits of every script are
  /// kept, so "五感 (Gogo)" → "五感gogo".
  static String normalizeName(String name) => name.toLowerCase().replaceAll(
    RegExp(r'[^\p{L}\p{N}]+', unicode: true),
    '',
  );

  /// Name variants: the whole name plus each part split on parentheses /
  /// slashes / dashes, so "五感 (Gogo)" also matches "Gogo" and "五感".
  static Set<String> _variants(String name) => {
    normalizeName(name),
    for (final part in name.split(RegExp(r'[()（）/|｜\-–—·・]')))
      normalizeName(part),
  }..removeWhere((s) => s.isEmpty);

  static Set<String> _tokens(String name) => name
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((t) => t.isNotEmpty)
      .toSet();

  /// Whether [a] and [b] plausibly name the same place: a shared name
  /// variant, one normalized name containing the other (≥3 chars), or at
  /// least [similarTokenOverlap] of the shorter name's words in common.
  static bool isSimilarName(String a, String b) {
    final va = _variants(a);
    final vb = _variants(b);
    if (va.isEmpty || vb.isEmpty) return false;
    if (va.intersection(vb).isNotEmpty) return true;
    final na = normalizeName(a);
    final nb = normalizeName(b);
    final shorter = na.length <= nb.length ? na : nb;
    final longer = identical(shorter, na) ? nb : na;
    if (shorter.length >= 3 && longer.contains(shorter)) return true;
    final ta = _tokens(a);
    final tb = _tokens(b);
    final smaller = ta.length <= tb.length ? ta.length : tb.length;
    if (smaller == 0) return false;
    return ta.intersection(tb).length / smaller >= similarTokenOverlap;
  }

  /// The note "merge" appends to the existing place, or null when that
  /// source is already recorded on it (merging twice is a no-op).
  static String? mergeNote(Place existing, {String? sourceUrl, String? via}) {
    final url = sourceUrl?.trim() ?? '';
    final handle = via?.trim() ?? '';
    if (url.isEmpty && (handle.isEmpty || handle == '@unknown')) return null;
    final note = url.isNotEmpty
        ? 'Also saved from $url'
        : 'Also saved from a post by $handle';
    final marker = url.isNotEmpty ? url : note;
    final alreadyThere =
        existing.originalCaption.contains(marker) ||
        existing.extraNotes.any((n) => n.text.contains(marker));
    return alreadyThere ? null : note;
  }
}
