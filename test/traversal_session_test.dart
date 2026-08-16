import 'package:flutter_test/flutter_test.dart';

import 'package:perihelion/models/rosette_layout.dart';
import 'package:perihelion/services/graph_repository.dart';
import 'package:perihelion/services/traversal_session.dart';

import 'support/fake_graph.dart';

void main() {
  late GraphRepository repo;

  setUp(() => repo = GraphRepository.fromJson(fakeGraph()));

  TraversalSession sessionAt(String id) =>
      TraversalSession(repository: repo, startId: id);

  group('TraversalSession', () {
    test('starts at the given node with no history', () {
      final s = sessionAt('hub');
      expect(s.currentId, 'hub');
      expect(s.depth, 0);
      expect(s.canGoBack, isFalse);
      expect(s.rosette.center.id, 'hub');
    });

    test('reports the full degree, not the number of seats shown', () {
      final s = sessionAt('hub');
      expect(s.rosette.occupied, hasLength(6));
      expect(s.rosette.degree, 7);
    });

    test('fills seats from the top when there is nothing to pin', () {
      final s = sessionAt('hub');
      expect(s.rosette.seats[0], isNotNull);
      expect(s.rosette.seatOf('p1'), 0);
    });

    test('jumping re-centres and records history', () {
      final s = sessionAt('hub')..jumpTo('p1');
      expect(s.currentId, 'p1');
      expect(s.depth, 1);
      expect(s.history, ['hub']);
      expect(s.rosette.center.id, 'p1');
    });

    test('the node just left is always still on screen', () {
      final s = sessionAt('hub')..jumpTo('e1');
      expect(s.rosette.seatOf('hub'), isNotNull);
    });

    test('the node just left sits opposite the direction of travel', () {
      final s = sessionAt('hub');
      final seat = s.rosette.seatOf('p1')!;
      s.jumpTo('p1');
      expect(s.rosette.seatOf('hub'), RosetteLayout.oppositeSeat(seat));
    });

    test('rejects a jump to a node that is not on screen', () {
      final s = sessionAt('hub');
      expect(() => s.jumpTo('p3'), throwsArgumentError);
      expect(() => s.jumpTo('ghost'), throwsArgumentError);
      expect(s.currentId, 'hub');
    });

    test('depth counts jumps across a long traversal', () {
      final s = sessionAt('hub');
      var hops = 0;
      for (var i = 0; i < 12; i++) {
        final next = s.rosette.occupied.first.node.id;
        s.jumpTo(next);
        hops++;
      }
      expect(s.depth, hops);
      expect(s.history, hasLength(hops));
    });

    test('going back restores the previous centre and shortens history', () {
      final s = sessionAt('hub')
        ..jumpTo('p1')
        ..jumpTo('p2');
      expect(s.depth, 2);
      s.goBack();
      expect(s.currentId, 'p1');
      expect(s.depth, 1);
      s.goBack();
      expect(s.currentId, 'hub');
      expect(s.canGoBack, isFalse);
    });

    test('going back keeps the node being left reachable', () {
      final s = sessionAt('hub')..jumpTo('p1');
      s.goBack();
      expect(s.rosette.center.id, 'hub');
      expect(s.rosette.seatOf('p1'), isNotNull);
    });

    test('going back at the root is a no-op', () {
      final s = sessionAt('hub');
      s.goBack();
      expect(s.currentId, 'hub');
      expect(s.depth, 0);
    });

    test('seats never hold the centre itself', () {
      final s = sessionAt('hub')..jumpTo('p1');
      expect(s.rosette.seatOf('p1'), isNull);
    });

    test('seats never repeat a node', () {
      final s = sessionAt('hub')..jumpTo('pl1');
      final ids = s.rosette.occupied.map((n) => n.node.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('a sparse node leaves empty seats rather than inventing links', () {
      final s = sessionAt('p3');
      expect(s.rosette.occupied, hasLength(1));
      expect(s.rosette.seats.where((x) => x == null), hasLength(5));
    });

    test('relation labels read from the current centre outward', () {
      final s = sessionAt('hub');
      final toP1 = s.rosette.occupied.firstWhere((n) => n.node.id == 'p1');
      expect(toP1.relation, 'Employs');
      s.jumpTo('p1');
      final backToHub = s.rosette.occupied.firstWhere((n) => n.node.id == 'hub');
      expect(backToHub.relation, 'Employed by');
    });
  });
}
