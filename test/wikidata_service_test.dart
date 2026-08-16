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
  mainThemed();
  mainScaffolding();
  mainReadiness();
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
      // properties + one round per notability tier + one relaxed pass. No
      // second hop, because nothing was seated to hop from.
      expect(
        calls,
        lessThanOrEqualTo(WikidataService.notabilityTiers.length + 2),
      );
    });

    test('serves a prefetched draw without touching the network', () async {
      var calls = 0;
      final service = WikidataService(
        fetcher: (url) async {
          calls++;
          return twoProperties(url);
        },
        random: Random(4),
      );

      service.prefetch(['Q1741']);
      await Future<void>.delayed(Duration.zero);
      while (service.isPrefetching) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final warmed = calls;
      expect(warmed, greaterThan(0));

      final n = await service.sampleNeighbors('Q1741');
      expect(n, isNotEmpty);
      // Served entirely from the warmed draw.
      expect(calls, warmed);
    });

    test('re-draws on a return visit, so a prefetch is used once', () async {
      var calls = 0;
      final service = WikidataService(
        fetcher: (url) async {
          calls++;
          return twoProperties(url);
        },
        random: Random(4),
      );
      service.prefetch(['Q1741']);
      while (service.isPrefetching) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await service.sampleNeighbors('Q1741');
      final afterFirst = calls;
      await service.sampleNeighbors('Q1741');
      // The second visit draws again rather than repeating the same six.
      expect(calls, greaterThan(afterFirst));
    });

    test('never runs more prefetches at once than it promises', () async {
      var concurrent = 0;
      var peak = 0;
      final service = WikidataService(
        fetcher: (url) async {
          concurrent++;
          peak = peak > concurrent ? peak : concurrent;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          concurrent--;
          return twoProperties(url);
        },
        random: Random(4),
      );
      service.prefetch(
        List.generate(12, (i) => 'Q${2000 + i}'),
      );
      while (service.isPrefetching) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(peak, lessThanOrEqualTo(WikidataService.maxConcurrentPrefetch));
    });

    test('ignores ids that are not items', () async {
      final service = WikidataService(fetcher: (_) async => _bindings([]));
      service.prefetch(['not-a-qid', 'P31', '']);
      expect(service.isPrefetching, isFalse);
    });

    test('keeps the request url short enough for the endpoint to accept',
        () async {
      // Regression: repeating a filter inside every subquery pushed the URL
      // past 9kB and the endpoint answered 414, which looked like a dead tap.
      var longest = 0;
      final service = WikidataService(
        fetcher: (url) async {
          longest = url.toString().length > longest
              ? url.toString().length
              : longest;
          if (url.queryParameters['query']!.contains('SELECT DISTINCT ?pd')) {
            return _bindings([
              for (var i = 0; i < 60; i++)
                _row({'pd': '${_wd}P${100000 + i}', 'dir': 'in'}),
            ]);
          }
          return _bindings([]);
        },
        random: Random(6),
      );
      await service.sampleNeighbors('Q1741');
      expect(longest, lessThanOrEqualTo(WikidataService.maxRequestUrlLength));
    });

    test('excludes Wikimedia\'s own category and list pages', () {
      for (final type in ['Q4167836', 'Q13406463', 'Q4167410']) {
        expect(WikidataService.wikimediaInternalTypes, contains(type));
      }
      // Reached via properties that only ever point at those pages.
      expect(WikidataService.blockedProperties, contains('P971'));
      expect(WikidataService.blockedProperties, contains('P301'));
    });

    test('tries the widest-known neighbours before the obscure ones', () {
      expect(WikidataService.notabilityTiers.first, greaterThan(0));
      expect(
        WikidataService.notabilityTiers,
        orderedEquals(
          List<int>.of(WikidataService.notabilityTiers)
            ..sort((a, b) => b.compareTo(a)),
        ),
      );
      // The last tier accepts anything, so seats still fill.
      expect(WikidataService.notabilityTiers.last, 0);
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

  group('random topic warming', () {
    /// Answers the random-article call, the property list and the neighbour
    /// query, so a whole random topic can be warmed offline.
    Future<String> everything(Uri url) async {
      if (url.host == 'en.wikipedia.org') {
        return jsonEncode({
          'query': {
            'pages': [
              {'title': 'Vienna', 'pageprops': {'wikibase_item': 'Q1741'}},
            ],
          },
        });
      }
      final q = url.queryParameters['query']!;
      if (q.contains('SELECT DISTINCT ?pd')) {
        return _bindings([_row({'pd': '${_wd}P19', 'dir': 'in'})]);
      }
      if (q.contains('rdfs:label')) {
        return _bindings([
          _row({'label': 'Vienna', 'type': '${_entity}Q515'}),
        ]);
      }
      return _bindings([
        for (var i = 0; i < 8; i++)
          _row({
            'pd': '${_wd}P19', 'dir': 'in', 'other': '${_entity}Q${70 + i}',
            'otherLabel': 'Person $i', 'propLabel': 'place of birth',
            'type': '${_entity}Q5',
          }),
      ]);
    }

    test('has nothing warm before it is asked', () {
      final service = WikidataService(fetcher: (_) async => _bindings([]));
      expect(service.hasWarmRandomTopic, isFalse);
      expect(service.takeWarmRandomQid(), isNull);
    });

    test('warms a topic and hands it over once', () async {
      final service =
          WikidataService(fetcher: everything, random: Random(9));
      service.prefetchRandomTopics();
      var spins = 0;
      while (!service.hasWarmRandomTopic && spins++ < 200) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(service.hasWarmRandomTopic, isTrue);
      expect(service.takeWarmRandomQid(), 'Q1741');
      // Handed over, not kept.
      expect(service.takeWarmRandomQid(), isNull);
    });

    test('keeps only topics that can fill every seat', () async {
      // One usable neighbour, so this topic is rejected rather than warmed.
      final service = WikidataService(
        fetcher: (url) async {
          if (url.host == 'en.wikipedia.org') {
            return jsonEncode({
              'query': {
                'pages': [
                  {'title': 'Stub', 'pageprops': {'wikibase_item': 'Q9001'}},
                ],
              },
            });
          }
          final q = url.queryParameters['query']!;
          if (q.contains('SELECT DISTINCT ?pd')) {
            return _bindings([_row({'pd': '${_wd}P19', 'dir': 'in'})]);
          }
          if (q.contains('rdfs:label')) {
            return _bindings([_row({'label': 'Stub'})]);
          }
          return _bindings([
            _row({
              'pd': '${_wd}P19', 'dir': 'in', 'other': '${_entity}Q77',
              'otherLabel': 'Only One', 'propLabel': 'place of birth',
            }),
          ]);
        },
        random: Random(9),
      );
      service.prefetchRandomTopics();
      var spins = 0;
      while (spins++ < 60) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(service.hasWarmRandomTopic, isFalse);
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

/// Answers anchor resolution, the backlink theme fetch, the property list and
/// the neighbour draw, so a themed session can be exercised offline.
Future<String> themedWorld(Uri url) async {
  if (url.host == 'en.wikipedia.org') {
    return jsonEncode({
      'query': {
        'pages': [
          {'title': 'Bebop', 'pageprops': {'wikibase_item': 'Q105513'}},
          {'title': 'Miles Davis', 'pageprops': {'wikibase_item': 'Q93341'}},
          {'title': 'No item here'},
        ],
      },
    });
  }
  final q = url.queryParameters['query']!;
  if (q.contains('EntitySearch')) {
    return jsonEncode({
      'results': {
        'bindings': [
          {
            'item': {'value': 'http://www.wikidata.org/entity/Q8341'},
            'itemLabel': {'value': 'jazz'},
            'title': {'value': 'Jazz'},
          },
        ],
      },
    });
  }
  if (q.contains('SELECT DISTINCT ?pd')) {
    return jsonEncode({
      'results': {
        'bindings': [
          {
            'pd': {'value': 'http://www.wikidata.org/prop/direct/P136'},
            'dir': {'value': 'in'},
          },
        ],
      },
    });
  }
  return jsonEncode({
    'results': {
      'bindings': [
        for (final e in [
          ['Q93341', 'Miles Davis'], // in theme
          ['Q105513', 'Bebop'], // in theme
          ['Q999001', 'Unrelated One'],
          ['Q999002', 'Unrelated Two'],
        ])
          {
            'pd': {'value': 'http://www.wikidata.org/prop/direct/P136'},
            'dir': {'value': 'in'},
            'other': {'value': 'http://www.wikidata.org/entity/${e[0]}'},
            'otherLabel': {'value': e[1]},
            'propLabel': {'value': 'genre'},
          },
      ],
    },
  });
}

void mainThemed() {
  group('theme steering', () {
    test('starts unsteered', () {
      final s = WikidataService(fetcher: themedWorld);
      expect(s.isFiltered, isFalse);
      expect(s.filterLabel, isEmpty);
    });

    test('resolves the concept and loads its topical neighbourhood', () async {
      final s = WikidataService(fetcher: themedWorld);
      await s.applyFilter('jazz');
      expect(s.isFiltered, isTrue);
      // Ranked by sitelinks, so the genre wins over a same-named album.
      expect(s.filterLabel, 'jazz');
      expect(s.isThemed('Q105513'), isTrue);
      expect(s.isThemed('Q93341'), isTrue);
      expect(s.isThemed('Q999001'), isFalse);
      // Pages without a Wikidata item are skipped, not counted.
      expect(s.themeSize, greaterThanOrEqualTo(2));
    });

    test('seats themed neighbours first but still fills all six', () async {
      final s = WikidataService(fetcher: themedWorld, random: Random(3));
      await s.applyFilter('jazz');
      final n = await s.sampleNeighbors('Q1');
      expect(n, isNotEmpty);
      // Steering is a pull, not a fence: unthemed neighbours still appear.
      expect(n.first.themed, isTrue);
      expect(n.map((x) => x.node.qid), contains('Q93341'));
    });

    test('marks which neighbours came from the theme', () async {
      final s = WikidataService(fetcher: themedWorld, random: Random(3));
      await s.applyFilter('jazz');
      final n = await s.sampleNeighbors('Q1');
      for (final x in n) {
        expect(x.themed, s.isThemed(x.node.qid));
      }
    });

    test('starts inside the theme rather than anywhere at all', () async {
      final s = WikidataService(fetcher: themedWorld, random: Random(3));
      await s.applyFilter('jazz');
      final start = await s.randomStartQid();
      expect(s.isThemed(start), isTrue);
    });

    test('clearing returns to unsteered browsing', () async {
      final s = WikidataService(fetcher: themedWorld);
      await s.applyFilter('jazz');
      s.clearFilter();
      expect(s.isFiltered, isFalse);
      expect(s.filterLabel, isEmpty);
      expect(s.isThemed('Q105513'), isFalse);
    });

    test('an empty phrase clears rather than steering nowhere', () async {
      final s = WikidataService(fetcher: themedWorld);
      await s.applyFilter('jazz');
      await s.applyFilter('   ');
      expect(s.isFiltered, isFalse);
    });

    test('reports words that match nothing, keeping the old theme', () async {
      final s = WikidataService(
        fetcher: (url) async {
          if (url.queryParameters['query']?.contains('EntitySearch') ?? false) {
            return jsonEncode({'results': {'bindings': <dynamic>[]}});
          }
          return themedWorld(url);
        },
      );
      await expectLater(
        s.applyFilter('qwertyuiopasdf'),
        throwsA(isA<WikidataUnavailable>()),
      );
      expect(s.isFiltered, isFalse);
    });

    test('opens on the subject itself, not merely near it', () async {
      final s = WikidataService(fetcher: themedWorld, random: Random(3));
      await s.applyFilter('jazz');
      // Steering toward dogs should put the dog article at the centre.
      expect(s.anchorQid, 'Q8341');
      expect(s.isThemed(s.anchorQid!), isTrue);
    });

    test('discards pre-warmed topics when steering changes', () async {
      // Regression: the warmed topic pool survived a filter change, so
      // asking to steer opened on whatever unrelated topic was waiting.
      final s = WikidataService(fetcher: themedWorld, random: Random(3));
      s.prefetchRandomTopics();
      var spins = 0;
      while (!s.hasWarmRandomTopic && spins++ < 200) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      if (!s.hasWarmRandomTopic) return; // fixture did not warm; nothing to prove
      await s.applyFilter('jazz');
      expect(s.hasWarmRandomTopic, isFalse);
    });

    test('drops warmed draws when steering changes', () async {
      final s = WikidataService(fetcher: themedWorld, random: Random(3));
      s.prefetch(['Q1']);
      while (s.isPrefetching) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(s.hasReadyDraw('Q1'), isTrue);
      await s.applyFilter('jazz');
      expect(s.hasReadyDraw('Q1'), isFalse);
    });
  });
}

void mainReadiness() {
  group('readiness signalling', () {
    test('warms one topic, not two, within its attempt budget', () {
      // Two at once inside a small budget usually warmed neither.
      expect(WikidataService.randomTopicsWarm, 1);
      expect(WikidataService.randomWarmAttempts, greaterThan(6));
      // A near-full rosette is good enough; insisting on six rejected most
      // articles and left nothing warm at all.
      expect(WikidataService.randomWarmMinSeats,
          lessThan(WikidataService.seatCount));
      expect(WikidataService.randomWarmMinSeats, greaterThan(1));
    });

    test('announces when a satellite becomes ready', () async {
      final service = WikidataService(fetcher: themedWorld, random: Random(4));
      var ticks = 0;
      service.cacheRevision.addListener(() => ticks++);
      service.prefetch(['Q1741']);
      while (service.isPrefetching) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(service.hasReadyDraw('Q1741'), isTrue);
      expect(ticks, greaterThan(0));
    });

    test('announces again when that readiness is spent', () async {
      final service = WikidataService(fetcher: themedWorld, random: Random(4));
      service.prefetch(['Q1741']);
      while (service.isPrefetching) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      var ticks = 0;
      service.cacheRevision.addListener(() => ticks++);
      await service.sampleNeighbors('Q1741');
      expect(service.hasReadyDraw('Q1741'), isFalse);
      expect(ticks, greaterThan(0));
    });

    test('reports nothing ready before any warming', () {
      final service = WikidataService(fetcher: themedWorld);
      expect(service.hasReadyDraw('Q1741'), isFalse);
      expect(service.hasWarmRandomTopic, isFalse);
    });
  });
}

void mainScaffolding() {
  group('Wikipedia scaffolding is never a topic', () {
    Future<String> stubWithFurniture(Uri url) async {
      final q = url.queryParameters['query']!;
      if (q.contains('SELECT DISTINCT ?pd')) {
        return _bindings([_row({'pd': '${_wd}P31', 'dir': 'out'})]);
      }
      return _bindings([
        for (final e in [
          // All on an unblocked property, so only the namespace guard can
          // exclude them — that is what this test is for.
          ['Q1', 'Wikipedia:Vital articles/Level/4', 'P155'],
          ['Q2', 'Category:Battles', 'P155'],
          ['Q3', 'Portal:Military history', 'P155'],
          ['Q4', 'Template:Infobox', 'P155'],
          ['Q5', 'Encyclopaedia Britannica', 'P1343'], // blocked property
          ['Q6', 'war', 'P155'], // the only real topic
        ])
          {
            'pd': {'value': '$_wd${e[2]}'},
            'dir': {'value': 'out'},
            'other': {'value': '$_entity${e[0]}'},
            'otherLabel': {'value': e[1]},
            'propLabel': {'value': 'subclass of'},
          },
      ]);
    }

    test('drops project, category, portal and template pages', () async {
      final service =
          WikidataService(fetcher: stubWithFurniture, random: Random(2));
      final n = await service.sampleNeighbors('Q999');
      final labels = n.map((x) => x.node.label).toList();
      expect(labels, isNot(contains('Wikipedia:Vital articles/Level/4')));
      expect(labels, isNot(contains('Category:Battles')));
      expect(labels, isNot(contains('Portal:Military history')));
      expect(labels, isNot(contains('Template:Infobox')));
    });

    test('honours the property blocklist wherever rows are absorbed',
        () async {
      // The second-hop query builds its own SPARQL and used to skip this.
      final service =
          WikidataService(fetcher: stubWithFurniture, random: Random(2));
      final n = await service.sampleNeighbors('Q999');
      expect(n.map((x) => x.node.label), isNot(contains('Encyclopaedia Britannica')));
    });

    test('keeps the real topic', () async {
      final service =
          WikidataService(fetcher: stubWithFurniture, random: Random(2));
      final n = await service.sampleNeighbors('Q999');
      expect(n.map((x) => x.node.label), contains('war'));
    });
  });
}
