/// One member's rating of a place on a shared board, at
/// `sharedBoards/{boardId}/places/{placeId}/ratings/{uid}` — the doc id is
/// the rater's uid, so firestore.rules can check ownership directly. Every
/// member (any role) can read a board's ratings; each writes only their own.
///
/// [score] is required (1..10, the same scale as `Place.myScore` /
/// `ScoreStars`) — clearing your stars deletes the rating, remark included.
class PlaceRating {
  const PlaceRating({
    required this.uid,
    required this.placeId,
    required this.displayName,
    required this.score,
    this.photoUrl,
    this.notes = '',
  });

  final String uid;
  final String placeId;

  /// The rater's name when they last saved; the board's live `memberNames`
  /// wins when shown.
  final String displayName;
  final String? photoUrl;
  final int score;
  final String notes;

  /// Rules caps (firestore.rules `validRating`).
  static const maxNotesLength = 1000;
  static const maxNameLength = 100;

  /// Plain JSON for Firestore (the repository adds `updatedAt`).
  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'placeId': placeId,
      'displayName': displayName,
      'photoUrl': ?photoUrl,
      'score': score,
      'notes': notes,
    };
  }

  /// Lenient parse; returns null for a doc without a usable score.
  static PlaceRating? fromJson(Map<String, dynamic> json) {
    final score = json['score'];
    final uid = json['uid'];
    if (score is! num || uid is! String) return null;
    return PlaceRating(
      uid: uid,
      placeId: json['placeId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      photoUrl: json['photoUrl'] as String?,
      score: score.toInt().clamp(1, 10),
      notes: json['notes'] as String? ?? '',
    );
  }
}
