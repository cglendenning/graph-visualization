import 'node_category.dart';

/// One Wikidata item, as much of it as the rosette needs.
class WikidataNode {
  const WikidataNode({
    required this.qid,
    required this.label,
    required this.description,
    required this.category,
  });

  /// Wikidata item id, e.g. `Q1741`.
  final String qid;

  final String label;

  /// Wikidata's own one-line description. CC0, and the closest thing the
  /// live graph has to the hand-written taglines it replaced.
  final String description;

  final NodeCategory category;

  /// The English Wikipedia article title, which for a linked item is the
  /// label. Used to fetch the detail-screen extract.
  String get wikipediaTitle => label;
}

/// A neighbor reached from the current center by one Wikidata statement.
class WikidataNeighbor {
  const WikidataNeighbor({
    required this.node,
    required this.relation,
    required this.incoming,
  });

  final WikidataNode node;

  /// The property label, e.g. "place of birth".
  final String relation;

  /// True when the statement lives on the neighbor and points at the
  /// center, which is how most of the interesting edges are stored.
  final bool incoming;


  /// Reads with the center as the subject.
  String get phrasing => incoming ? '$relation of' : relation;

}

/// A property that has at least one statement in the given direction.
class PropertyLink {
  const PropertyLink({required this.pid, required this.incoming});

  /// Property id without prefix, e.g. `P19`.
  final String pid;

  final bool incoming;

  @override
  bool operator ==(Object other) =>
      other is PropertyLink && other.pid == pid && other.incoming == incoming;

  @override
  int get hashCode => Object.hash(pid, incoming);
}

/// Thrown when Wikidata cannot be reached or returns nothing usable.
class WikidataUnavailable implements Exception {
  const WikidataUnavailable(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'WikidataUnavailable: $message${cause == null ? '' : ' ($cause)'}';
}
