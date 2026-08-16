import 'node_category.dart';

/// A single fact shown on the detail screen.
class NodeFact {
  const NodeFact({required this.label, required this.value});

  final String label;
  final String value;

  factory NodeFact.fromJson(Map<String, dynamic> json) => NodeFact(
        label: json['label'] as String,
        value: json['value'] as String,
      );
}

/// One entity in the graph.
class GraphNode {
  const GraphNode({
    required this.id,
    required this.name,
    required this.category,
    required this.tagline,
    required this.summary,
    required this.facts,
  });

  final String id;
  final String name;
  final NodeCategory category;
  final String tagline;
  final String summary;
  final List<NodeFact> facts;

  factory GraphNode.fromJson(Map<String, dynamic> json) => GraphNode(
        id: json['id'] as String,
        name: json['name'] as String,
        category: NodeCategory.fromId(json['category'] as String),
        tagline: json['tagline'] as String,
        summary: json['summary'] as String,
        facts: (json['facts'] as List<dynamic>)
            .map((f) => NodeFact.fromJson(f as Map<String, dynamic>))
            .toList(growable: false),
      );
}

/// A neighbour of the current centre: the node itself plus how it relates.
class Neighbor {
  const Neighbor({
    required this.node,
    required this.relation,
    required this.weight,
  });

  final GraphNode node;

  /// Reads correctly with the current centre as the subject.
  final String relation;

  final double weight;
}
