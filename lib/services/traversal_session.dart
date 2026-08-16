import '../models/graph_node.dart';
import '../models/rosette_layout.dart';
import 'graph_repository.dart';
import 'neighbor_selector.dart';

/// One rendered rosette: a centre and its six seated satellites.
class RosetteState {
  const RosetteState({
    required this.center,
    required this.seats,
    required this.depth,
    required this.degree,
  });

  final GraphNode center;

  /// Length six, indexed by seat. An entry is null only if the graph gave
  /// the centre fewer than six neighbours.
  final List<Neighbor?> seats;

  /// Jumps made since launch. Drives the sweep arc.
  final int depth;

  /// Total neighbours of [center] in the whole graph, not just the six
  /// shown. Drives the centre tick ring.
  final int degree;

  int? seatOf(String nodeId) {
    for (var i = 0; i < seats.length; i++) {
      if (seats[i]?.node.id == nodeId) return i;
    }
    return null;
  }

  Iterable<Neighbor> get occupied => seats.whereType<Neighbor>();
}

/// Holds the current position in the graph and the path taken to reach it.
///
/// The session owns seat placement so that the node just left keeps a
/// predictable position instead of being reshuffled on every jump.
class TraversalSession {
  TraversalSession({
    required GraphRepository repository,
    required String startId,
    NeighborSelector selector = const NeighborSelector(),
    // Named parameters cannot be private, so these cannot become
    // initializing formals despite what the linter suggests.
    // ignore: prefer_initializing_formals
  })  : _repository = repository,
        // ignore: prefer_initializing_formals
        _selector = selector,
        _currentId = startId {
    _rosette = _build(centerId: startId, pinnedId: null, pinnedSeat: null);
  }

  final GraphRepository _repository;
  final NeighborSelector _selector;

  final List<String> _history = <String>[];
  String _currentId;
  late RosetteState _rosette;

  String get currentId => _currentId;

  RosetteState get rosette => _rosette;

  /// Ids visited before the current one, oldest first.
  List<String> get history => List<String>.unmodifiable(_history);

  int get depth => _history.length;

  bool get canGoBack => _history.isNotEmpty;

  /// Moves the tapped satellite to the centre.
  ///
  /// The outgoing centre is guaranteed a seat in the new rosette, placed
  /// opposite the direction of travel.
  void jumpTo(String nodeId) {
    final seat = _rosette.seatOf(nodeId);
    if (seat == null) {
      throw ArgumentError('$nodeId is not currently on screen');
    }
    final leaving = _currentId;
    _history.add(leaving);
    _currentId = nodeId;
    _rosette = _build(
      centerId: nodeId,
      pinnedId: leaving,
      pinnedSeat: RosetteLayout.oppositeSeat(seat),
    );
  }

  /// Returns to the previous centre, dropping the jump from the history.
  void goBack() {
    if (_history.isEmpty) return;
    final target = _history.removeLast();
    final leaving = _currentId;
    _currentId = target;
    // The node being left keeps the seat it originally occupied, if the
    // selector still surfaces it, so stepping back reverses cleanly.
    _rosette = _build(centerId: target, pinnedId: leaving, pinnedSeat: null);
  }

  RosetteState _build({
    required String centerId,
    required String? pinnedId,
    required int? pinnedSeat,
  }) {
    final chosen = _selector.select(
      _repository.neighborsOf(centerId),
      pinnedId: pinnedId,
    );

    final seats = List<Neighbor?>.filled(RosetteLayout.seatCount, null);
    final queue = List<Neighbor>.of(chosen);

    var fillOrder = List<int>.generate(RosetteLayout.seatCount, (i) => i);

    if (pinnedId != null && pinnedSeat != null) {
      final pinnedIndex = queue.indexWhere((n) => n.node.id == pinnedId);
      if (pinnedIndex >= 0) {
        seats[pinnedSeat] = queue.removeAt(pinnedIndex);
        fillOrder = RosetteLayout.seatsAfter(pinnedSeat);
      }
    }

    for (final seat in fillOrder) {
      if (queue.isEmpty) break;
      if (seats[seat] != null) continue;
      seats[seat] = queue.removeAt(0);
    }

    return RosetteState(
      center: _repository.node(centerId),
      seats: List<Neighbor?>.unmodifiable(seats),
      depth: _history.length,
      degree: _repository.degreeOf(centerId),
    );
  }
}
