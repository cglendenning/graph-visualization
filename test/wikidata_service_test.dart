import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:perihelion/models/node_category.dart';
import 'package:perihelion/models/wikidata_node.dart';
import 'package:perihelion/services/wikidata_category_map.dart';
import 'package:perihelion/services/wikidata_service.dart';

String _bindings(List<Map<String, Map<String, String>>> rows) =>
    jsonEncode({'results': {'bindings': rows}});

Map<String, Map<String, String>> _row(Map<String, String> values) =>
    {for (final e in values.entries) e.key: {'value': e.value}};

const _wd = 'http://www.wikidata.org/prop/direct/';
const _entity = 'http://www.wikidata.org/entity/';

void main() {
  group('WikidataService queries', () {
    test('sends SPARQL as a json-formatted GET', () {
      final url = WikidataService.sparqlUrl('SELECT * WHERE {}');
      expect(url.host, 'query.wikidata.org');
      expect(url.path, '/sparql');
      expect(url.queryParameters['format'], 'json');
      expect(url.queryParameters['query'], 'SELECT * WHERE {}');
    });

    test('draws random topics from Wikipedia, not raw Wikidata', () {
      // A third of Wikidata is bot-imported scholarly records, so a raw
      // random item would almost never be worth landing on.
      final url = WikidataService.randomArticleUrl();
      expect(url.host, 'en.wikipedia.org');
      expect(url.queryParameters['generator'], 'random');
      expect(url.queryParameters['grnnamespace'], '0');
      expect(url.queryParameters['ppprop'], 'wikibase_item');
    });

    test('declares a descriptive user agent, as Wikimedia policy requires',
        () {
      expect(WikidataService.userAgent, contains('Perihelion'));
      expect(WikidataService.userAgent, contains('https://'));
    });

    test('blocks Wikimedia bookkeeping properties', () {
      for (final pid in ['P31', 'P910', 'P1424', 'P1343', 'P5008']) {
        expect(WikidataService.blockedProperties, contains(pid));
      }
    });
  });

  group('randomStartQid', () {
    test('returns the article\'s Wikidata item', () async {
      final service = WikidataService(
        fetcher: (_) async => jsonEncode({
          'query': {
            'pages': [
              {'title': 'Vienna', 'pageprops': {'wikibase_item': 'Q1741'}},
            ],
          },
        }),
      );
      expect(await service.randomStartQid(), 'Q1741');
    });

    test('draws again when an article has no Wikidata item', () async {
      var calls = 0;
      final service = WikidataService(fetcher: (_) async {
        calls++;
        return jsonEncode({
          'query': {
            'pages': [
              if (calls == 1) {'title': 'Orphan'} else
                {'title': 'Vienna', 'pageprops': {'wikibase_item': 'Q1741'}},
            ],
          },
        });
      });
      expect(await service.randomStartQid(), 'Q1741');
      expect(calls, 2);
    });
  });

  group('node', () {
    test('reads label, description and category', () async {
      final service = WikidataService(
        fetcher: (_) async => _bindings([
          _row({
            'label': 'Vienna',
            'description': 'capital of Austria',
            'type': '${_entity}Q515',
          }),
        ]),
      );
      final node = await service.node('Q1741');
      expect(node.label, 'Vienna');
      expect(node.description, 'capital of Austria');
      expect(node.category, NodeCategory.place);
      expect(node.wikipediaTitle, 'Vienna');
    });

    test('caches, so a revisit costs nothing', () async {
      var calls = 0;
      final service = WikidataService(fetcher: (_) async {
        calls++;
        return _bindings([
          _row({'label': 'Vienna', 'type': '${_entity}Q515'}),
        ]);
      });
      await service.node('Q1741');
      await service.node('Q1741');
      expect(calls, 1);
    });

    test('rejects anything that is not an item id', () async {
      final service = WikidataService(fetcher: (_) async => _bindings([]));
      expect(() => service.node('P31'), throwsArgumentError);
      expect(() => service.node('Q1741; DROP'), throwsArgumentError);
      expect(() => service.node(''), throwsArgumentError);
    });

    test('reports an item that does not exist', () async {
      final service = WikidataService(fetcher: (_) async => _bindings([]));
      await expectLater(
        service.node('Q99999999999'),
        throwsA(isA<WikidataUnavailable>()),
      );
    });
  });

  group('propertiesFor', () {
    test('keeps direction, and keeps blocked properties for the fallback',
        () async {
      // Blocked properties stay in this list and are filtered when sampling,
      // so a thinly connected topic can still fall back on them rather than
      // leave a seat empty.
      final service = WikidataService(
        fetcher: (_) async => _bindings([
          _row({'pd': '${_wd}P19', 'dir': 'in'}),
          _row({'pd': '${_wd}P36', 'dir': 'out'}),
          _row({'pd': '${_wd}P31', 'dir': 'out'}),
        ]),
      );
      final links = await service.propertiesFor('Q1741');
      expect(links, hasLength(3));
      expect(links, contains(const PropertyLink(pid: 'P19', incoming: true)));
      expect(links, contains(const PropertyLink(pid: 'P36', incoming: false)));
      expect(links, contains(const PropertyLink(pid: 'P31', incoming: false)));
    });

    test('caches, since an item\'s property set does not move', () async {
      var calls = 0;
      final service = WikidataService(fetcher: (_) async {
        calls++;
        return _bindings([_row({'pd': '${_wd}P19', 'dir': 'in'})]);
      });
      await service.propertiesFor('Q1741');
      await service.propertiesFor('Q1741');
      expect(calls, 1);
    });
  });

  group('sampleNeighbors', () {
    String twoProperties(Uri url) {
      if (url.queryParameters['query']!.contains('SELECT DISTINCT ?pd')) {
        return _bindings([
          _row({'pd': '${_wd}P19', 'dir': 'in'}),
          _row({'pd': '${_wd}P36', 'dir': 'out'}),
        ]);
      }
      return _bindings([
        _row({
          'pd': '${_wd}P19', 'dir': 'in', 'other': '${_entity}Q7304',
          'otherLabel': 'Gustav Mahler', 'propLabel': 'place of birth',
          'type': '${_entity}Q5',
        }),
        _row({
          'pd': '${_wd}P36', 'dir': 'out', 'other': '${_entity}Q40',
          'otherLabel': 'Austria', 'propLabel': 'capital of',
          'type': '${_entity}Q6256',
        }),
      ]);
    }

    test('returns one neighbour per property, phrased from the centre',
        () async {
      final service = WikidataService(
        fetcher: (url) async => twoProperties(url),
        random: Random(1),
      );
      final n = await service.sampleNeighbors('Q1741');
      expect(n, hasLength(2));

      final mahler = n.firstWhere((x) => x.node.qid == 'Q7304');
      expect(mahler.node.label, 'Gustav Mahler');
      expect(mahler.node.category, NodeCategory.person);
      expect(mahler.incoming, isTrue);
      // The statement lives on Mahler, so it reads back the other way.
      expect(mahler.phrasing, 'place of birth of');

      final austria = n.firstWhere((x) => x.node.qid == 'Q40');
      expect(austria.incoming, isFalse);
      expect(austria.phrasing, 'capital of');
    });

    test('never exceeds the six seats', () async {
      final service = WikidataService(
        fetcher: (url) async {
          if (url.queryParameters['query']!.contains('SELECT DISTINCT ?pd')) {
            return _bindings([
              for (var i = 0; i < 20; i++)
                _row({'pd': '${_wd}P${100 + i}', 'dir': 'out'}),
            ]);
          }
          return _bindings([
            for (var i = 0; i < 20; i++)
              _row({
                'pd': '${_wd}P${100 + i}', 'dir': 'out',
                'other': '${_entity}Q${900 + i}',
                'otherLabel': 'Item $i', 'propLabel': 'related to',
              }),
          ]);
        },
        random: Random(7),
      );
      expect(await service.sampleNeighbors('Q1741'), hasLength(6));
    });

    test('skips unlabelled items rather than showing a bare Q-number',
        () async {
      final service = WikidataService(
        fetcher: (url) async {
          if (url.queryParameters['query']!.contains('SELECT DISTINCT ?pd')) {
            return _bindings([_row({'pd': '${_wd}P6', 'dir': 'out'})]);
          }
          return _bindings([
            _row({
              'pd': '${_wd}P6', 'dir': 'out', 'other': '${_entity}Q1560091',
              'otherLabel': 'Q1560091', 'propLabel': 'head of government',
            }),
          ]);
        },
      );
      expect(await service.sampleNeighbors('Q1741'), isEmpty);
    });

    test('never seats the centre as its own satellite', () async {
      final service = WikidataService(
        fetcher: (url) async {
          if (url.queryParameters['query']!.contains('SELECT DISTINCT ?pd')) {
            return _bindings([_row({'pd': '${_wd}P138', 'dir': 'out'})]);
          }
          return _bindings([
            _row({
              'pd': '${_wd}P138', 'dir': 'out', 'other': '${_entity}Q1741',
              'otherLabel': 'Vienna', 'propLabel': 'named after',
            }),
          ]);
        },
      );
      expect(await service.sampleNeighbors('Q1741'), isEmpty);
    });

    test('fills all six from one rich property when others are sparse',
        () async {
      // The bug this guards: a topic where only one property returns rows
      // used to show a single satellite.
      final service = WikidataService(
        fetcher: (url) async {
          if (url.queryParameters['query']!.contains('SELECT DISTINCT ?pd')) {
            return _bindings([_row({'pd': '${_wd}P19', 'dir': 'in'})]);
          }
          return _bindings([
            for (var i = 0; i < 12; i++)
              _row({
                'pd': '${_wd}P19', 'dir': 'in',
                'other': '${_entity}Q${500 + i}',
                'otherLabel': 'Person $i', 'propLabel': 'place of birth',
                'type': '${_entity}Q5',
              }),
          ]);
        },
        random: Random(3),
      );
      final n = await service.sampleNeighbors('Q1741');
      expect(n, hasLength(6));
      expect(n.map((x) => x.node.qid).toSet(), hasLength(6));
    });

    test('prefers a fresh category before repeating one', () async {
      final service = WikidataService(
        fetcher: (url) async {
          if (url.queryParameters['query']!.contains('SELECT DISTINCT ?pd')) {
            return _bindings([
              _row({'pd': '${_wd}P19', 'dir': 'in'}),
              _row({'pd': '${_wd}P36', 'dir': 'out'}),
            ]);
          }
          return _bindings([
            // Three people under one property, one place under another.
            for (var i = 0; i < 3; i++)
              _row({
                'pd': '${_wd}P19', 'dir': 'in', 'other': '${_entity}Q${60 + i}',
                'otherLabel': 'Person $i', 'propLabel': 'place of birth',
                'type': '${_entity}Q5',
              }),
            _row({
              'pd': '${_wd}P36', 'dir': 'out', 'other': '${_entity}Q40',
              'otherLabel': 'Austria', 'propLabel': 'capital of',
              'type': '${_entity}Q6256',
            }),
          ]);
        },
        random: Random(5),
      );
      final n = await service.sampleNeighbors('Q1741');
      final categories = n.map((x) => x.node.category).toList();
      // Both categories must appear before either is doubled up.
      expect(categories.take(2).toSet(), hasLength(2));
      expect(categories, contains(NodeCategory.place));
      expect(categories, contains(NodeCategory.person));
    });

    test('steps out a second hop when a stub cannot fill six on its own',
        () async {
      // Ninette, Manitoba: six properties, one usable neighbour. The empty
      // seats are filled through that neighbour and labelled as such.
      final service = WikidataService(
        fetcher: (url) async {
          final q = url.queryParameters['query']!;
          if (q.contains('SELECT DISTINCT ?pd')) {
            return _bindings([
              _row({'pd': '${_wd}P131', 'dir': 'out'}),
            ]);
          }
          if (q.contains('wd:Q100')) {
            return _bindings([
              _row({
                'pd': '${_wd}P131', 'dir': 'out', 'other': '${_entity}Q200',
                'otherLabel': 'Manitoba', 'propLabel': 'located in',
                'type': '${_entity}Q515',
              }),
            ]);
          }
          return _bindings([
            for (var i = 0; i < 6; i++)
              _row({
                'pd': '${_wd}P131', 'dir': 'out',
                'other': '${_entity}Q${300 + i}',
                'otherLabel': 'Neighbour $i', 'propLabel': 'located in',
                'type': '${_entity}Q5',
              }),
          ]);
        },
        random: Random(11),
      );
      final n = await service.sampleNeighbors('Q100');
      expect(n, hasLength(6));
      expect(n.first.node.label, 'Manitoba');
      // Second-hop seats say so rather than implying a direct statement.
      expect(n.skip(1).every((x) => x.relation == 'via Manitoba'), isTrue);
      expect(n.map((x) => x.node.qid), isNot(contains('Q100')));
    });

    test('bounds how many queries one rosette may run', () async {
      // Regression: an unbounded slice loop chained a dozen queries for a
      // well-connected topic, and the jump looked like it had frozen.
      var calls = 0;
      final service = WikidataService(
        fetcher: (url) async {
          calls++;
          if (url.queryParameters['query']!.contains('SELECT DISTINCT ?pd')) {
            return _bindings([
              for (var i = 0; i < 120; i++)
                _row({'pd': '${_wd}P${1000 + i}', 'dir': 'out'}),
            ]);
          }
          // Every neighbour query comes back empty, the worst case for the
          // fill loop.
          return _bindings([]);
        },
        random: Random(2),
      );
      await service.sampleNeighbors('Q1741');
      // properties + two rounds + one relaxed pass. No second hop, because
      // nothing was seated to hop from.
      expect(calls, lessThanOrEqualTo(4));
    });

    test('returns nothing when the item has no usable properties', () async {
      final service = WikidataService(
        fetcher: (_) async => _bindings([
          _row({'pd': '${_wd}P31', 'dir': 'out'}),
        ]),
      );
      expect(await service.sampleNeighbors('Q1741'), isEmpty);
    });
  });

  group('failures', () {
    test('turns a transport failure into an actionable message', () async {
      final service = WikidataService(
        fetcher: (_) async => throw const _Offline(),
      );
      await expectLater(
        service.node('Q1741'),
        throwsA(isA<WikidataUnavailable>().having(
          (e) => e.message,
          'message',
          contains('Check your connection'),
        )),
      );
    });

    test('reports unreadable json', () async {
      final service = WikidataService(fetcher: (_) async => 'not json');
      await expectLater(
        service.node('Q1741'),
        throwsA(isA<WikidataUnavailable>().having(
          (e) => e.message,
          'message',
          contains('unreadable'),
        )),
      );
    });

    test('keeps the cause for debugging', () async {
      final service = WikidataService(
        fetcher: (_) async => throw const _Offline(),
      );
      try {
        await service.node('Q1741');
        fail('expected WikidataUnavailable');
      } on WikidataUnavailable catch (e) {
        expect(e.cause, isA<_Offline>());
        expect(e.toString(), contains('WikidataUnavailable'));
      }
    });
  });

  group('WikidataCategoryMap', () {
    test('maps the common classes onto the rosette colours', () {
      expect(WikidataCategoryMap.forTypes(['Q5']), NodeCategory.person);
      expect(WikidataCategoryMap.forTypes(['Q515']), NodeCategory.place);
      expect(WikidataCategoryMap.forTypes(['Q11424']), NodeCategory.work);
      expect(WikidataCategoryMap.forTypes(['Q198']), NodeCategory.event);
      expect(WikidataCategoryMap.forTypes(['Q43229']),
          NodeCategory.organization);
    });

    test('takes the first recognised class and ignores unknown ones', () {
      expect(
        WikidataCategoryMap.forTypes(['Q99999999', 'Q5']),
        NodeCategory.person,
      );
    });

    test('falls back to thing rather than guessing', () {
      expect(WikidataCategoryMap.forTypes([]), NodeCategory.thing);
      expect(WikidataCategoryMap.forTypes(['Q99999999']), NodeCategory.thing);
    });
  });
}

class _Offline implements Exception {
  const _Offline();
}
