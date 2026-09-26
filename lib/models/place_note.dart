/// A single dated entry under "My review" — lets the user keep adding notes
/// to their own place over time (e.g. "2nd visit: …") beyond the single
/// [Place.myNotes] remark box. See [Place.extraNotes].
class PlaceNote {
  const PlaceNote({
    required this.id,
    required this.text,
    required this.createdAt,
  });

  /// Unique within a place's [Place.extraNotes] — see PlaceStore's id
  /// generator (microsecond timestamp + counter, no uuid dependency).
  final String id;

  /// Free-form text, capped at 1000 chars by the editor UI.
  final String text;

  /// When the note was first written; kept stable across edits (only [text]
  /// changes) so notes stay in the order they were added.
  final DateTime createdAt;

  PlaceNote copyWith({String? text}) =>
      PlaceNote(id: id, text: text ?? this.text, createdAt: createdAt);

  /// Serializes to plain JSON types only, same convention as [Place.toJson].
  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  /// Lenient parse counterpart to [toJson]: returns `null` for a malformed
  /// entry (missing/non-string id or text, unparsable date) rather than
  /// throwing, so one bad entry doesn't take down the whole list — see
  /// [Place.fromJson]'s `extraNotes` handling, which skips nulls.
  static PlaceNote? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final text = raw['text'];
    if (id is! String || id.isEmpty || text is! String) return null;
    final createdAt = _parseCreatedAt(raw['createdAt']);
    if (createdAt == null) return null;
    return PlaceNote(id: id, text: text, createdAt: createdAt);
  }

  /// Same leniency as [Place.fromJson]'s `_parseMyPhotoAt`: an ISO-8601
  /// string (what [toJson] writes) or epoch milliseconds.
  static DateTime? _parseCreatedAt(dynamic raw) {
    if (raw is String) return DateTime.tryParse(raw);
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
    }
    return null;
  }
}
