/// A lead-section extract fetched from Wikipedia at runtime.
///
/// The text is CC BY-SA 4.0 and is never bundled into the app or modified —
/// it is displayed verbatim alongside the attribution this license requires.
/// See [attribution] and [licenseUrl].
class WikipediaExtract {
  const WikipediaExtract({
    required this.title,
    required this.text,
    required this.articleUrl,
  });

  /// The canonical article title, after redirects have been followed.
  final String title;

  /// Plain-text lead section, verbatim.
  final String text;

  final Uri articleUrl;

  static final Uri licenseUrl =
      Uri.parse('https://creativecommons.org/licenses/by-sa/4.0/');

  static const String licenseName = 'CC BY-SA 4.0';

  /// The credit line shown under the text.
  String get attribution => '"$title" on Wikipedia';
}

/// Thrown when an extract cannot be retrieved.
///
/// [message] is written for the reader, not the log — it is shown on the
/// detail screen directly.
class WikipediaUnavailable implements Exception {
  const WikipediaUnavailable(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'WikipediaUnavailable: $message${cause == null ? '' : ' ($cause)'}';
}
