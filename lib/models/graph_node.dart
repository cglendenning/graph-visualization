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
    required this.wikipediaTitle,
    required this.facts,
  });

  final String id;
  final String name;
  final NodeCategory category;
  final String tagline;

  /// Canonical English Wikipedia article title, verified at build time.
  ///
  /// Prose is not bundled: the detail screen fetches the lead section from
  /// this article at runtime, which keeps the shipped asset public domain.
  final String wikipediaTitle;

  final List<NodeFact> facts;

  factory GraphNode.fromJson(Map<String, dynamic> json) => GraphNode(
        id: json['id'] as String,
        name: json['name'] as String,
        category: NodeCategory.fromId(json['category'] as String),
        tagline: json['tagline'] as String,
        wikipediaTitle: json['wikipedia'] as String,
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
    this.distinctness = 0,
  });

  final GraphNode node;

  /// Reads correctly with the current centre as the subject.
  final String relation;

  final double weight;

  /// How far outside the centre's own neighbourhood this node sits, 0..1.
  ///
  /// One minus the Jaccard overlap of the two nodes' neighbourhoods. A
  /// neighbour that shares most of the centre's connections scores near zero
  /// and leads nowhere new; a neighbour that shares almost none scores near
  /// one and is a bridge out of the current subject.
  final double distinctness;
}
