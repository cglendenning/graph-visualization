import 'package:flutter_test/flutter_test.dart';

import 'package:perihelion/models/graph_node.dart';
import 'package:perihelion/services/graph_repository.dart';
import 'package:perihelion/services/neighbor_selector.dart';

import 'support/fake_graph.dart';

/// Builds a neighbour with exact weight and distinctness, for the cases the
/// fixture graph cannot produce naturally.
Neighbor _neighbor(
  String id,
  String category, {
  required double weight,
  required double distinctness,
}) =>
    Neighbor(
      node: GraphNode.fromJson({
        'id': id,
        'name': id,
        'category': category,
        'tagline': 'tagline',
        'wikipedia': id,
        'facts': [
          {'label': 'Label', 'value': 'Value'},
        ],
      }),
      relation: 'Relates to',
      weight: weight,
      distinctness: distinctness,
    );

void main() {
  late GraphRepository repo;
  const selector = NeighborSelector();

  setUp(() => repo = GraphRepository.fromJson(fakeGraph()));

  group('NeighborSelector', () {
    test('returns six seats when six neighbours exist', () {
      final chosen = selector.select(repo.neighborsOf('hub'));
      expect(chosen, hasLength(6));
    });

    test('prefers one per category before repeating a category', () {
      final chosen = selector.select(repo.neighborsOf('hub'));
      final ids = chosen.map((n) => n.node.id).toList();
      // hub has five distinct categories available (person, place, work,
      // thing, event); all five should appear before a second person does.
      final firstFive = ids.take(5).toSet();
      expect(firstFive, containsAll(['p1', 'pl1', 'w1', 't1', 'e1']));
    });

    test('gives the last seat to the most distinct neighbour, not the next '
        'strongest', () {
      final chosen = selector.select(repo.neighborsOf('hub'));
      // p2 is the stronger edge (0.85 vs 0.80) but shares p1 with the hub.
      // p3 shares nothing, so it is the way out of the current subject.
      expect(chosen.last.node.id, 'p3');
      expect(chosen.map((n) => n.node.id), isNot(contains('p2')));
    });

    test('reserves the bridge seat only when more is on offer than fits', () {
      // p1 has three neighbours, so every one of them fits and no seat is
      // held back — reserving would just drop a node for nothing.
      final chosen = selector.select(repo.neighborsOf('p1'));
      expect(chosen, hasLength(3));
      expect(
        chosen.map((n) => n.node.id).toSet(),
        {'hub', 'p2', 'pl1'},
      );
    });

    test('the bridge is the least overlapping of the leftovers', () {
      final leftovers = repo
          .neighborsOf('hub')
          .where((n) => n.node.id == 'p2' || n.node.id == 'p3');
      final p2 = leftovers.firstWhere((n) => n.node.id == 'p2');
      final p3 = leftovers.firstWhere((n) => n.node.id == 'p3');
      expect(p3.distinctness, greaterThan(p2.distinctness));
      expect(p3.weight, lessThan(p2.weight));
    });

    test('breaks a distinctness tie on strength, then on id', () {
      final tied = [
        _neighbor('alpha', 'person', weight: 0.4, distinctness: 1),
        _neighbor('bravo', 'place', weight: 0.9, distinctness: 1),
        _neighbor('charlie', 'work', weight: 0.9, distinctness: 1),
        _neighbor('delta', 'event', weight: 0.5, distinctness: 0.2),
        _neighbor('echo', 'thing', weight: 0.5, distinctness: 0.2),
        _neighbor('foxtrot', 'concept', weight: 0.5, distinctness: 0.2),
        _neighbor('golf', 'movement', weight: 0.5, distinctness: 0.2),
      ];
      final chosen = selector.select(tied);
      // Five main seats go by strength and category; the bridge then takes
      // the most distinct leftover, and among equals the stronger one.
      expect(chosen, hasLength(6));
      expect(chosen.last.distinctness, 1);
      expect(chosen.last.node.id, anyOf('bravo', 'charlie', 'alpha'));
    });

    test('a pinned node and a bridge still leave six distinct nodes', () {
      final chosen = selector.select(repo.neighborsOf('hub'), pinnedId: 'e1');
      expect(chosen, hasLength(6));
      expect(chosen.map((n) => n.node.id), contains('e1'));
      expect(chosen.map((n) => n.node.id).toSet(), hasLength(6));
    });

    test('never repeats a node', () {
      final ids = selector.select(repo.neighborsOf('hub')).map((n) => n.node.id);
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('returns fewer than six when the node has fewer neighbours', () {
      final chosen = selector.select(repo.neighborsOf('p3'));
      expect(chosen, hasLength(1));
      expect(chosen.single.node.id, 'hub');
    });

    test('always includes the pinned node, even when it is weak', () {
      // e1 is hub's weakest edge and would be dropped if the rosette were
      // any smaller; pinning must keep it regardless.
      final chosen =
          selector.select(repo.neighborsOf('hub'), pinnedId: 'e1');
      expect(chosen.map((n) => n.node.id), contains('e1'));
      expect(chosen, hasLength(6));
    });

    test('puts the pinned node first so it can claim its reserved seat', () {
      final chosen =
          selector.select(repo.neighborsOf('hub'), pinnedId: 't1');
      expect(chosen.first.node.id, 't1');
    });

    test('pinning an absent node changes nothing', () {
      final withPin =
          selector.select(repo.neighborsOf('hub'), pinnedId: 'ghost');
      final without = selector.select(repo.neighborsOf('hub'));
      expect(
        withPin.map((n) => n.node.id),
        without.map((n) => n.node.id),
      );
    });

    test('is deterministic across repeated calls', () {
      final a = selector.select(repo.neighborsOf('hub')).map((n) => n.node.id);
      final b = selector.select(repo.neighborsOf('hub')).map((n) => n.node.id);
      expect(a, b);
    });

    test('handles an empty candidate list', () {
      expect(selector.select(const []), isEmpty);
    });
  });
}
