/// "1 place" / "2 places": [n] followed by [one] or [many] (defaults to
/// [one] + 's').
String plural(int n, String one, [String? many]) =>
    '$n ${pluralWord(n, one, many)}';

/// Just the word — for callers that format the count themselves (e.g.
/// "1,234 places").
String pluralWord(int n, String one, [String? many]) =>
    n == 1 ? one : (many ?? '${one}s');
