import 'dart:convert';
import 'dart:io';

import '../models/wikipedia_extract.dart';

/// Fetches a page body for [url]. Injected so the service can be tested
/// without a network.
typedef WikipediaFetcher = Future<String> Function(Uri url);

/// Retrieves article lead sections from Wikipedia.
///
/// Nothing here is bundled with the app: the CC BY-SA text is fetched when a
/// detail screen asks for it and held only in memory for the session. That is
/// what keeps the shipped asset entirely public domain.
class WikipediaService {
  WikipediaService({WikipediaFetcher? fetcher})
      : _fetch = fetcher ?? _httpFetch;

  final WikipediaFetcher _fetch;

  /// Successful lookups only. A failure is worth retrying when the user
  /// returns, since the usual cause is a dropped connection.
  final Map<String, WikipediaExtract> _cache = <String, WikipediaExtract>{};

  static const Duration timeout = Duration(seconds: 10);

  /// Wikimedia's User-Agent policy requires a descriptive agent with a way to
  /// make contact; requests without one are refused.
  static const String userAgent =
      'Perihelion/1.1 (https://github.com/cglendenning/graph-visualization)';

  static Uri endpointFor(String title) =>
      Uri.https('en.wikipedia.org', '/w/api.php', {
        'action': 'query',
        'format': 'json',
        'formatversion': '2',
        'prop': 'extracts',
        'exintro': '1',
        'explaintext': '1',
        'redirects': '1',
        'titles': title,
      });

  static Uri articleUrlFor(String title) =>
      Uri.https('en.wikipedia.org', '/wiki/${title.replaceAll(' ', '_')}');

  bool isCached(String title) => _cache.containsKey(title);

  /// Returns the lead section for [title].
  ///
  /// Throws [WikipediaUnavailable] with a message intended for display.
  Future<WikipediaExtract> extractFor(String title) async {
    final cached = _cache[title];
    if (cached != null) return cached;

    final String body;
    try {
      body = await _fetch(endpointFor(title)).timeout(timeout);
    } on Object catch (error) {
      throw WikipediaUnavailable(
        'Could not reach Wikipedia. Check your connection and try again.',
        cause: error,
      );
    }

    final extract = _parse(body, title);
    _cache[title] = extract;
    return extract;
  }

  WikipediaExtract _parse(String body, String requestedTitle) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(body) as Map<String, dynamic>;
    } on FormatException catch (error) {
      throw WikipediaUnavailable(
        'Wikipedia returned an unreadable response.',
        cause: error,
      );
    }

    final pages = (json['query'] as Map<String, dynamic>?)?['pages'];
    if (pages is! List || pages.isEmpty) {
      throw const WikipediaUnavailable('Wikipedia returned no article.');
    }

    final page = pages.first as Map<String, dynamic>;
    if (page['missing'] == true) {
      throw WikipediaUnavailable('No Wikipedia article for "$requestedTitle".');
    }

    final text = (page['extract'] as String?)?.trim();
    if (text == null || text.isEmpty) {
      throw WikipediaUnavailable(
        'The Wikipedia article for "$requestedTitle" has no summary.',
      );
    }

    final canonical = page['title'] as String? ?? requestedTitle;
    return WikipediaExtract(
      title: canonical,
      text: text,
      articleUrl: articleUrlFor(canonical),
    );
  }

  static Future<String> _httpFetch(Uri url) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Wikipedia responded ${response.statusCode}',
          uri: url,
        );
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }
}
