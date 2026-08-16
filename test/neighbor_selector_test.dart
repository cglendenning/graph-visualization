import 'package:flutter_test/flutter_test.dart';

import 'package:perihelion/services/graph_repository.dart';
import 'package:perihelion/services/neighbor_selector.dart';

import 'support/fake_graph.dart';

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

    test('fills the leftover seat with the next strongest of any type', () {
      final chosen = selector.select(repo.neighborsOf('hub'));
      // Sixth seat falls back to the strongest unused node, another person.
      expect(chosen.last.node.id, 'p2');
      expect(chosen.map((n) => n.node.id), isNot(contains('p3')));
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
