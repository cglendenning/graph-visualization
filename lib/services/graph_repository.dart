import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;

import '../models/graph_edge.dart';
import '../models/graph_node.dart';

/// Loads the graph asset and answers structural questions about it.
///
/// Edges are stored once in the asset and mirrored here, so adjacency is
/// symmetric and traversal can move in either direction.
class GraphRepository {
  GraphRepository._(this._nodes, this._adjacency);

  final Map<String, GraphNode> _nodes;
  final Map<String, List<GraphEdge>> _adjacency;

  static const String assetPath = 'assets/graph.json';

  /// Parses an already-decoded asset payload.
  ///
  /// Throws [FormatException] if an edge names a node that does not exist —
  /// a dangling edge would otherwise surface as an empty circle at runtime.
  factory GraphRepository.fromJson(Map<String, dynamic> json) {
    final nodes = <String, GraphNode>{};
    for (final raw in json['nodes'] as List<dynamic>) {
      final node = GraphNode.fromJson(raw as Map<String, dynamic>);
      if (nodes.containsKey(node.id)) {
        throw FormatException('Duplicate node id: ${node.id}');
      }
      nodes[node.id] = node;
    }

    final adjacency = <String, List<GraphEdge>>{
      for (final id in nodes.keys) id: <GraphEdge>[],
    };
    final seen = <String>{};

    for (final raw in json['nodes'] as List<dynamic>) {
      final map = raw as Map<String, dynamic>;
      final from = map['id'] as String;
      for (final rawEdge in map['edges'] as List<dynamic>) {
        final edge = GraphEdge.fromJson(from, rawEdge as Map<String, dynamic>);
        if (!nodes.containsKey(edge.to)) {
          throw FormatException('Edge $from -> ${edge.to} names an unknown node');
        }
        if (edge.to == from) {
          throw FormatException('Node $from links to itself');
        }
        // The asset may state a relationship from either end; keep the first.
        final key = _pairKey(edge.from, edge.to);
        if (!seen.add(key)) continue;
        adjacency[edge.from]!.add(edge);
        adjacency[edge.to]!.add(edge.mirrored);
      }
    }

    for (final entry in adjacency.entries) {
      entry.value.sort((a, b) {
        final byWeight = b.weight.compareTo(a.weight);
        return byWeight != 0 ? byWeight : a.to.compareTo(b.to);
      });
    }

    return GraphRepository._(nodes, adjacency);
  }

  static String _pairKey(String a, String b) =>
      a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';

  static Future<GraphRepository> load() async {
    final raw = await rootBundle.loadString(assetPath);
    return GraphRepository.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  int get nodeCount => _nodes.length;

  Iterable<String> get nodeIds => _nodes.keys;

  GraphNode node(String id) {
    final node = _nodes[id];
    if (node == null) throw ArgumentError('Unknown node id: $id');
    return node;
  }

  /// How many nodes connect to [id]. Drawn as the centre tick ring.
  int degreeOf(String id) => _adjacency[id]?.length ?? 0;

  /// All neighbours of [id], strongest edge first.
  List<Neighbor> neighborsOf(String id) {
    final edges = _adjacency[id];
    if (edges == null) throw ArgumentError('Unknown node id: $id');
    return edges
        .map((e) => Neighbor(
              node: node(e.to),
              relation: e.relation,
              weight: e.weight,
            ))
        .toList(growable: false);
  }

  /// The largest degree in the graph, used to normalise the tick ring.
  int get maxDegree =>
      _adjacency.values.fold(0, (m, e) => e.length > m ? e.length : m);

  String randomNodeId(Random random) {
    final ids = _nodes.keys.toList(growable: false);
    return ids[random.nextInt(ids.length)];
  }
}
