import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:perihelion/services/wikidata_service.dart';

/// One day's most-read list, trimmed to what the parser reads.
String _mostRead(List<String> titles) => jsonEncode({
      'items': [
        {'articles': [for (final t in titles) {'article': t, 'views': 10000}]},
      ],
    });

/// An extracts response. [intros] maps QID to lead length.
String _intros(Map<String, int> intros) => jsonEncode({
      'query': {
        'pages': [
          for (final entry in intros.entries)
            {
              'title': entry.key,
              'pageprops': {'wikibase_item': entry.key},
              'extract': 'x' * entry.value,
            },
        ],
      },
    });

void main() {
  group('most-read urls', () {
    test('asks Wikimedia for one settled day, zero padded', () {
      final url = WikidataService.topPageviewsUrl(DateTime.utc(2023, 6, 4));
      expect(url.host, 'wikimedia.org');
      expect(url.path, contains('/pageviews/top/en.wikipedia/all-access/'));
      // Unpadded months and days 404 against this endpoint.
      expect(url.path, endsWith('/2023/06/04'));
    });

    test('asks for leads and item ids together', () {
      final url = WikidataService.articleIntrosUrl(['Jazz', 'Vienna']);
      expect(url.host, 'en.wikipedia.org');
      expect(url.queryParameters['titles'], 'Jazz|Vienna');
      expect(url.queryParameters['exintro'], '1');
      expect(url.queryParameters['explaintext'], '1');
      // Keyed by QID, because Wikipedia normalises the titles it returns.
      expect(url.queryParameters['ppprop'], 'wikibase_item');
    });
  });

  group('mainstreamStartQid', () {
    test('skips articles whose lead is a stub', () async {
      final service = WikidataService(
        random: Random(1),
        fetcher: (url) async {
          if (url.host == 'wikimedia.org') return _mostRead(['Q1', 'Q2']);
          return _intros({
            'Q1': WikidataService.minIntroCharacters - 1, // too thin
            'Q2': WikidataService.minIntroCharacters + 1, // passes
          });
        },
      );
      expect(await service.mainstreamStartQid(), 'Q2');
    });

    test('ignores the front page and project pages', () async {
      String? asked;
      final service = WikidataService(
        random: Random(2),
        fetcher: (url) async {
          if (url.host == 'wikimedia.org') {
            return _mostRead(['Main_Page', 'Wikipedia:About', 'Q7']);
          }
          asked = url.queryParameters['titles']!;
          return _intros({'Q7': 900});
        },
      );
      expect(await service.mainstreamStartQid(), 'Q7');
      expect(asked, 'Q7');
    });

    test('falls back to a random article when most-read is unreachable',
        () async {
      final service = WikidataService(
        random: Random(3),
        fetcher: (url) async {
          if (url.host == 'wikimedia.org') throw Exception('offline');
          return jsonEncode({
            'query': {
              'pages': [
                {'title': 'Vienna', 'pageprops': {'wikibase_item': 'Q1741'}},
              ],
            },
          });
        },
      );
      // An obscure topic still beats no topic.
      expect(await service.mainstreamStartQid(), 'Q1741');
    });
  });

  group('satellite quality', () {
    test('never lowers the notability floor past a real threshold', () {
      // The tiered rounds must stay selective; the unbounded pass below them
      // is what guarantees six seats.
      expect(WikidataService.notabilityTiers.last, greaterThanOrEqualTo(12));
      expect(WikidataService.notabilityTiers.first, greaterThanOrEqualTo(40));
      for (var i = 1; i < WikidataService.notabilityTiers.length; i++) {
        expect(WikidataService.notabilityTiers[i],
            lessThan(WikidataService.notabilityTiers[i - 1]));
      }
    });

    test('a paragraph is more than a one-line description', () {
      expect(WikidataService.minIntroCharacters, greaterThanOrEqualTo(200));
    });
  });
}
