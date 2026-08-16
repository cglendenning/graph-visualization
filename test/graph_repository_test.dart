import 'package:flutter_test/flutter_test.dart';

import 'package:perihelion/models/node_category.dart';
import 'package:perihelion/services/graph_repository.dart';

import 'support/fake_graph.dart';

void main() {
  group('GraphRepository', () {
    test('indexes nodes by id', () {
      final repo = GraphRepository.fromJson(fakeGraph());
      expect(repo.nodeCount, 8);
      expect(repo.node('hub').name, 'Hub');
      expect(repo.node('hub').category, NodeCategory.concept);
      expect(() => repo.node('nope'), throwsArgumentError);
    });

    test('mirrors each edge so adjacency is symmetric', () {
      final repo = GraphRepository.fromJson(fakeGraph());
      final fromHub = repo.neighborsOf('hub').map((n) => n.node.id);
      expect(fromHub, contains('p1'));
      final backToHub = repo.neighborsOf('p1').map((n) => n.node.id);
      expect(backToHub, contains('hub'));
    });

    test('uses the inverse label on the mirrored direction', () {
      final repo = GraphRepository.fromJson(fakeGraph());
      final outward =
          repo.neighborsOf('hub').firstWhere((n) => n.node.id == 'p1');
      final inward =
          repo.neighborsOf('p1').firstWhere((n) => n.node.id == 'hub');
      expect(outward.relation, 'Employs');
      expect(inward.relation, 'Employed by');
    });

    test('falls back to the forward label when no inverse is given', () {
      final repo = GraphRepository.fromJson(fakeGraph());
      final inward =
          repo.neighborsOf('w1').firstWhere((n) => n.node.id == 'hub');
      expect(inward.relation, 'Symmetric with');
    });

    test('does not duplicate a relationship stated from both ends', () {
      // p1 -> pl1 is also stated as pl1 -> p1 in the fixture.
      final repo = GraphRepository.fromJson(fakeGraph());
      final links =
          repo.neighborsOf('p1').where((n) => n.node.id == 'pl1').toList();
      expect(links, hasLength(1));
    });

    test('returns neighbours strongest first', () {
      final repo = GraphRepository.fromJson(fakeGraph());
      final weights = repo.neighborsOf('hub').map((n) => n.weight).toList();
      final sorted = List<double>.of(weights)..sort((a, b) => b.compareTo(a));
      expect(weights, sorted);
    });

    test('degree counts all neighbours, not just the six shown', () {
      final repo = GraphRepository.fromJson(fakeGraph());
      expect(repo.degreeOf('hub'), 7);
      expect(repo.maxDegree, 7);
    });

    test('rejects an edge to an unknown node', () {
      final json = fakeGraph();
      (json['nodes'] as List).first['edges'].add({
        'to': 'ghost',
        'relation': 'Points at nothing',
        'weight': 0.5,
      });
      expect(() => GraphRepository.fromJson(json), throwsFormatException);
    });

    test('rejects a duplicate node id', () {
      final json = fakeGraph();
      (json['nodes'] as List).add((json['nodes'] as List).first);
      expect(() => GraphRepository.fromJson(json), throwsFormatException);
    });

    test('rejects a self link', () {
      final json = fakeGraph();
      (json['nodes'] as List).first['edges'].add({
        'to': 'hub',
        'relation': 'Itself',
        'weight': 0.5,
      });
      expect(() => GraphRepository.fromJson(json), throwsFormatException);
    });
  });
}
