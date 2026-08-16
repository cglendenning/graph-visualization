import '../models/graph_node.dart';

/// Chooses which six neighbours surround the centre.
///
/// The rule is "diverse but not rigid": take the strongest edge from each
/// distinct category first, then fill any remaining seats with the strongest
/// edges left over regardless of type. Most centres end up varied; a node
/// whose connections genuinely cluster in one category is allowed to show
/// that rather than have a weak edge promoted to fake variety.
class NeighborSelector {
  const NeighborSelector();

  static const int seatCount = 6;

  /// [pinnedId], when given, is always included — it is the node the user
  /// just came from, which must remain reachable so a traversal can be undone.
  List<Neighbor> select(List<Neighbor> candidates, {String? pinnedId}) {
    final ordered = List<Neighbor>.of(candidates)..sort(_byStrength);

    final chosen = <Neighbor>[];
    final takenIds = <String>{};
    final takenCategories = <String>{};

    void take(Neighbor n) {
      chosen.add(n);
      takenIds.add(n.node.id);
      takenCategories.add(n.node.category.id);
    }

    if (pinnedId != null) {
      for (final n in ordered) {
        if (n.node.id == pinnedId) {
          take(n);
          break;
        }
      }
    }

    // Pass one: best remaining edge from each category not yet represented.
    for (final n in ordered) {
      if (chosen.length == seatCount) break;
      if (takenIds.contains(n.node.id)) continue;
      if (takenCategories.contains(n.node.category.id)) continue;
      take(n);
    }

    // Pass two: fill what is left by raw strength.
    for (final n in ordered) {
      if (chosen.length == seatCount) break;
      if (takenIds.contains(n.node.id)) continue;
      take(n);
    }

    return List<Neighbor>.unmodifiable(chosen);
  }

  /// Strongest first; ties broken by id so the layout never reshuffles
  /// between two runs over the same data.
  static int _byStrength(Neighbor a, Neighbor b) {
    final byWeight = b.weight.compareTo(a.weight);
    return byWeight != 0 ? byWeight : a.node.id.compareTo(b.node.id);
  }
}
