import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:constellation/models/node_category.dart';
import 'package:constellation/services/graph_repository.dart';

/// Guards the hand-authored asset. The UI assumes six satellites are always
/// available and that no edge dead-ends, so those assumptions are checked
/// here rather than discovered on a phone.
void main() {
  late Map<String, dynamic> raw;
  late GraphRepository repo;

  setUpAll(() {
    raw = jsonDecode(File(GraphRepository.assetPath).readAsStringSync())
        as Map<String, dynamic>;
    repo = GraphRepository.fromJson(raw);
  });

  test('parses and holds the full graph', () {
    expect(repo.nodeCount, greaterThanOrEqualTo(120));
  });

  test('every node has at least six neighbours', () {
    final short = repo.nodeIds.where((id) => repo.degreeOf(id) < 6).toList();
    expect(short, isEmpty,
        reason: 'these nodes cannot fill a rosette: $short');
  });

  test('no edge names a node that does not exist', () {
    // GraphRepository.fromJson throws on a dangling edge, so reaching this
    // point already proves it; assert explicitly for intent.
    expect(() => GraphRepository.fromJson(raw), returnsNormally);
  });

  test('the graph is fully connected, so traversal never dead-ends', () {
    final seen = <String>{};
    final stack = <String>[repo.nodeIds.first];
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      if (!seen.add(current)) continue;
      for (final n in repo.neighborsOf(current)) {
        stack.add(n.node.id);
      }
    }
    expect(seen.length, repo.nodeCount);
  });

  test('every category in the asset is a known category', () {
    for (final id in repo.nodeIds) {
      expect(NodeCategory.values, contains(repo.node(id).category));
    }
  });

  test('every node carries display copy and facts', () {
    for (final id in repo.nodeIds) {
      final node = repo.node(id);
      expect(node.name, isNotEmpty);
      expect(node.tagline, isNotEmpty);
      expect(node.summary.length, greaterThan(40));
      expect(node.facts, isNotEmpty);
      for (final f in node.facts) {
        expect(f.label, isNotEmpty);
        expect(f.value, isNotEmpty);
      }
    }
  });

  test('edge weights stay in range', () {
    for (final id in repo.nodeIds) {
      for (final n in repo.neighborsOf(id)) {
        expect(n.weight, inInclusiveRange(0.0, 1.0));
        expect(n.relation, isNotEmpty);
      }
    }
  });
}
