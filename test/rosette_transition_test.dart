import 'package:flutter_test/flutter_test.dart';

import 'package:perihelion/models/node_category.dart';
import 'package:perihelion/models/rosette_layout.dart';
import 'package:perihelion/models/wikidata_node.dart';
import 'package:perihelion/services/traversal_session.dart';

WikidataNode _node(String qid) => WikidataNode(
      qid: qid,
      label: qid,
      description: '',
      category: NodeCategory.thing,
    );

WikidataNeighbor _neighbor(String qid) => WikidataNeighbor(
      node: _node(qid),
      relation: 'related to',
      incoming: false,
    );

/// A rosette centered on [center] with [seated] filling seats from the top.
RosetteState _rosette(String center, List<String> seated) => RosetteState(
      center: _node(center),
      seats: List<WikidataNeighbor?>.generate(
        RosetteLayout.seatCount,
        (i) => i < seated.length ? _neighbor(seated[i]) : null,
      ),
      depth: 0,
      degree: seated.length,
    );

void main() {
  group('RosetteTransition', () {
    test('locates the center and each seat', () {
      final r = _rosette('C', ['A', 'B']);
      expect(RosetteTransition.seatIn(r, 'C'), RosetteTransition.centerSeat);
      expect(RosetteTransition.seatIn(r, 'A'), 0);
      expect(RosetteTransition.seatIn(r, 'B'), 1);
      expect(RosetteTransition.seatIn(r, 'Z'), isNull);
      expect(RosetteTransition.seatIn(null, 'C'), isNull);
    });

    test('a first appearance has no origin, only a destination', () {
      final steps = RosetteTransition.between(null, _rosette('C', ['A']));
      expect(steps, hasLength(2));
      for (final s in steps) {
        expect(s.from, isNull);
        expect(s.to, isNotNull);
      }
    });

    test('a node on both sides carries both seats, so it can be moved', () {
      // A was seat 0, becomes the center; C was the center, becomes seat 0.
      final steps = RosetteTransition.between(
        _rosette('C', ['A', 'B']),
        _rosette('A', ['C', 'D']),
      );
      final a = steps.firstWhere((s) => s.node.qid == 'A');
      expect(a.from, 0);
      expect(a.to, RosetteTransition.centerSeat);

      final c = steps.firstWhere((s) => s.node.qid == 'C');
      expect(c.from, RosetteTransition.centerSeat);
      expect(c.to, 0);
    });

    test('a node only on the way out keeps its origin and no destination', () {
      final steps = RosetteTransition.between(
        _rosette('C', ['A', 'B']),
        _rosette('A', ['C']),
      );
      final b = steps.firstWhere((s) => s.node.qid == 'B');
      expect(b.from, 1);
      expect(b.to, isNull);
    });

    test('lists every node exactly once', () {
      final steps = RosetteTransition.between(
        _rosette('C', ['A', 'B']),
        _rosette('A', ['C', 'D']),
      );
      final ids = steps.map((s) => s.node.qid).toList();
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids.toSet(), {'A', 'B', 'C', 'D'});
    });

    test('centers come last, so they paint above their satellites', () {
      final steps = RosetteTransition.between(
        _rosette('C', ['A', 'B']),
        _rosette('A', ['C', 'D']),
      );
      final firstCenter = steps.indexWhere((s) => s.isCenter);
      expect(firstCenter, isNot(-1));
      // Nothing after the first center may be a satellite.
      for (var i = firstCenter; i < steps.length; i++) {
        expect(steps[i].isCenter, isTrue);
      }
    });

    test('carries the relationship, so the label survives the move', () {
      final steps = RosetteTransition.between(null, _rosette('C', ['A']));
      final a = steps.firstWhere((s) => s.node.qid == 'A');
      expect(a.neighbor, isNotNull);
      final c = steps.firstWhere((s) => s.node.qid == 'C');
      expect(c.neighbor, isNull, reason: 'a center has no relation to itself');
    });

    test('two empty sides plan nothing', () {
      expect(RosetteTransition.between(null, null), isEmpty);
    });

    test('the result cannot be mutated by a caller', () {
      final steps = RosetteTransition.between(null, _rosette('C', ['A']));
      expect(() => steps.clear(), throwsUnsupportedError);
    });
  });
}
