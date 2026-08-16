/// A directed relationship between two nodes.
///
/// The asset stores each relationship once. [GraphRepository] mirrors every
/// edge so that both endpoints can be traversed, using [inverseRelation] as
/// the label on the mirrored copy.
class GraphEdge {
  const GraphEdge({
    required this.from,
    required this.to,
    required this.relation,
    required this.inverseRelation,
    required this.weight,
  });

  final String from;
  final String to;

  /// How the relationship reads when [from] is the centre node.
  final String relation;

  /// How the relationship reads when [to] is the centre node.
  final String inverseRelation;

  /// Relationship strength, 0..1. Drives both neighbour selection and the
  /// tick density drawn along the connecting filament.
  final double weight;

  factory GraphEdge.fromJson(String from, Map<String, dynamic> json) {
    final relation = json['relation'] as String;
    return GraphEdge(
      from: from,
      to: json['to'] as String,
      relation: relation,
      inverseRelation: json['inverse'] as String? ?? relation,
      weight: (json['weight'] as num).toDouble(),
    );
  }

  /// The same relationship viewed from the other endpoint.
  GraphEdge get mirrored => GraphEdge(
        from: to,
        to: from,
        relation: inverseRelation,
        inverseRelation: relation,
        weight: weight,
      );
}
