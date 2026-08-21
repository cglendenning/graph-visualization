import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:perihelion/services/traversal_session.dart';
import 'package:perihelion/services/wikidata_service.dart';

String _bindings(List<Map<String, Map<String, String>>> rows) =>
    jsonEncode({'results': {'bindings': rows}});

Map<String, Map<String, String>> _row(Map<String, String> values) =>
    {for (final e in values.entries) e.key: {'value': e.value}};

const _wd = 'http://www.wikidata.org/prop/direct/';
const _entity = 'http://www.wikidata.org/entity/';

/// A world where every draw for the same center returns a different six.
///
/// That is the point: if stepping back redrew, the satellites would come
/// back different, and the assertions below would fail.
class _ShiftingWorld {
  int draws = 0;
  int fetches = 0;

  Future<String> call(Uri url) async {
    fetches++;
    if (url.host == 'en.wikipedia.org') {
      final titles = url.queryParameters['titles'];
      if (titles != null) {
        // Echo each title back with an intro long enough to pass the gate.
        return jsonEncode({
          'query': {
            'pages': [
              for (final title in titles.split('|'))
                {
                  'title': title,
                  'pageprops': {'wikibase_item': 'Q${title.split(' ').last}'},
                  'extract': 'x' * (WikidataService.minIntroCharacters + 50),
                },
            ],
          },
        });
      }
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
      return _bindings([_row({'label': 'A topic'})]);
    }
    // Each draw yields a disjoint set of neighbours from the last.
    final base = 1000 + (draws++ * 100);
    return _bindings([
      for (var i = 0; i < 8; i++)
        _row({
          'pd': '${_wd}P19',
          'dir': 'in',
          'other': '$_entity Q${base + i}'.replaceAll(' ', ''),
          'article': 'Person ${base + i}',
          'otherLabel': 'Person ${base + i}',
          'propLabel': 'place of birth',
          'type': '${_entity}Q5',
        }),
    ]);
  }
}

List<String?> _seatQids(RosetteState? r) =>
    [for (final s in r!.seats) s?.node.qid];

void main() {
  group('stepping back', () {
    test('restores the same center and the same satellites', () async {
      final world = _ShiftingWorld();
      final session = TraversalSession(
        service: WikidataService(fetcher: world.call, random: Random(1)),
      );

      await session.startAt('Q1741');
      final centerBefore = session.rosette!.center.qid;
      final seatsBefore = _seatQids(session.rosette);
      expect(seatsBefore.whereType<String>(), isNotEmpty);

      final target = session.rosette!.occupied.first.node.qid;
      await session.jumpTo(target);
      expect(session.rosette!.center.qid, target);
      // The fixture really would hand back a different six.
      expect(_seatQids(session.rosette), isNot(equals(seatsBefore)));

      await session.goBack();
      expect(session.rosette!.center.qid, centerBefore);
      expect(_seatQids(session.rosette), equals(seatsBefore));
    });

    test('costs no network at all', () async {
      final world = _ShiftingWorld();
      final session = TraversalSession(
        service: WikidataService(fetcher: world.call, random: Random(2)),
      );
      await session.startAt('Q1741');
      await session.jumpTo(session.rosette!.occupied.first.node.qid);

      final before = world.fetches;
      await session.goBack();
      expect(world.fetches, before, reason: 'stepping back must not refetch');
    });

    test('unwinds several jumps, each exactly as it was', () async {
      final world = _ShiftingWorld();
      final session = TraversalSession(
        service: WikidataService(fetcher: world.call, random: Random(3)),
      );
      await session.startAt('Q1741');

      final trail = <List<String?>>[];
      final centers = <String>[];
      for (var hop = 0; hop < 3; hop++) {
        trail.add(_seatQids(session.rosette));
        centers.add(session.rosette!.center.qid);
        await session.jumpTo(session.rosette!.occupied.first.node.qid);
      }

      for (var hop = 2; hop >= 0; hop--) {
        await session.goBack();
        expect(session.rosette!.center.qid, centers[hop]);
        expect(_seatQids(session.rosette), equals(trail[hop]));
      }
      expect(session.canGoBack, isFalse);
    });

    test('a new topic throws the whole trail away', () async {
      final world = _ShiftingWorld();
      final session = TraversalSession(
        service: WikidataService(fetcher: world.call, random: Random(4)),
      );
      await session.startAt('Q1741');
      await session.jumpTo(session.rosette!.occupied.first.node.qid);
      expect(session.canGoBack, isTrue);

      await session.startAt('Q42');
      expect(session.canGoBack, isFalse);
      expect(session.depth, 0);
    });
  });
}
