import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:perihelion/services/wikidata_service.dart';

String _bindings(List<Map<String, Map<String, String>>> rows) =>
    jsonEncode({'results': {'bindings': rows}});

Map<String, Map<String, String>> _row(Map<String, String> values) =>
    {for (final e in values.entries) e.key: {'value': e.value}};

const _wd = 'http://www.wikidata.org/prop/direct/';
const _entity = 'http://www.wikidata.org/entity/';

void main() {
  group('missing English label', () {
    // Q36301 is Anne Hathaway: labelled in Arabic, Czech, Greek, Hebrew and
    // Korean, but not English. Without a fallback the app showed "Q36301"
    // and then searched Wikipedia for that, which found nothing.
    test('a center falls back to the English article title', () async {
      final service = WikidataService(
        fetcher: (_) async => _bindings([
          _row({
            'description': 'American actress (born 1982)',
            'type': '${_entity}Q5',
            'article': 'Anne Hathaway',
          }),
        ]),
      );
      final node = await service.node('Q36301');
      expect(node.label, 'Anne Hathaway');
      expect(node.description, 'American actress (born 1982)');
      // The detail screen looks the article up by this, so it must not be
      // the bare id.
      expect(node.wikipediaTitle, 'Anne Hathaway');
    });

    test('a real English label still wins over the article title', () async {
      final service = WikidataService(
        fetcher: (_) async => _bindings([
          _row({'label': 'Vienna', 'article': 'Vienna, Austria'}),
        ]),
      );
      expect((await service.node('Q1741')).label, 'Vienna');
    });

    test('only the bare id remains when there is no name anywhere', () async {
      final service = WikidataService(
        fetcher: (_) async => _bindings([_row({'type': '${_entity}Q5'})]),
      );
      expect((await service.node('Q999')).label, 'Q999');
    });

    test('a satellite takes its seat under the article title', () async {
      // wikibase:label hands back the bare Q-number for an unlabelled item.
      // These used to be discarded, losing genuinely notable topics.
      final service = WikidataService(
        random: Random(1),
        fetcher: (url) async {
          final q = url.queryParameters['query'] ?? '';
          if (url.host == 'en.wikipedia.org') {
            final titles = url.queryParameters['titles'] ?? '';
            return jsonEncode({
              'query': {
                'pages': [
                  for (final t in titles.split('|'))
                    {
                      'title': t,
                      'pageprops': {'wikibase_item': 'Q36301'},
                      'extract':
                          'x' * (WikidataService.minIntroCharacters + 10),
                    },
                ],
              },
            });
          }
          if (q.contains('SELECT DISTINCT ?pd')) {
            return _bindings([_row({'pd': '${_wd}P19', 'dir': 'in'})]);
          }
          return _bindings([
            _row({
              'pd': '${_wd}P19',
              'dir': 'in',
              'other': '${_entity}Q36301',
              'otherLabel': 'Q36301', // the service's fallback
              'article': 'Anne Hathaway',
              'propLabel': 'place of birth',
              'type': '${_entity}Q5',
            }),
          ]);
        },
      );
      final drawn = await service.sampleNeighbors('Q1741');
      expect(drawn, hasLength(1));
      expect(drawn.first.node.label, 'Anne Hathaway');
    });
  });
}
