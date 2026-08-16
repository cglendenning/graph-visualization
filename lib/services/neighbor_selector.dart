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

    // Hold the last seat for a way out of the current subject — but only
    // when there is more on offer than fits, or the rosette would simply
    // lose a node to reserve a seat nothing can fill.
    final reserveBridge = ordered.length > seatCount;
    final mainSeats = reserveBridge ? seatCount - 1 : seatCount;

    // Pass one: best remaining edge from each category not yet represented.
    for (final n in ordered) {
      if (chosen.length == mainSeats) break;
      if (takenIds.contains(n.node.id)) continue;
      if (takenCategories.contains(n.node.category.id)) continue;
      take(n);
    }

    // Pass two: fill what is left by raw strength.
    for (final n in ordered) {
      if (chosen.length == mainSeats) break;
      if (takenIds.contains(n.node.id)) continue;
      take(n);
    }

    // The bridge seat. Strength has already had five chances; this one goes
    // to whichever remaining neighbour shares least with the centre, which
    // is the edge most likely to lead somewhere the traversal has not been.
    if (reserveBridge && chosen.length < seatCount) {
      Neighbor? bridge;
      for (final n in ordered) {
        if (takenIds.contains(n.node.id)) continue;
        if (bridge == null || _moreDistinct(n, bridge)) bridge = n;
      }
      if (bridge != null) take(bridge);
    }

    return List<Neighbor>.unmodifiable(chosen);
  }

  /// Most distinct wins; ties fall back to strength, then id, so the bridge
  /// is as stable between runs as the rest of the rosette.
  static bool _moreDistinct(Neighbor a, Neighbor b) {
    if (a.distinctness != b.distinctness) {
      return a.distinctness > b.distinctness;
    }
    if (a.weight != b.weight) return a.weight > b.weight;
    return a.node.id.compareTo(b.node.id) < 0;
  }

  /// Strongest first; ties broken by id so the layout never reshuffles
  /// between two runs over the same data.
  static int _byStrength(Neighbor a, Neighbor b) {
    final byWeight = b.weight.compareTo(a.weight);
    return byWeight != 0 ? byWeight : a.node.id.compareTo(b.node.id);
  }
}
