import '../models/rosette_layout.dart';
import '../models/wikidata_node.dart';
import 'wikidata_service.dart';

/// One rendered rosette: a centre and its six seated satellites.
class RosetteState {
  const RosetteState({
    required this.center,
    required this.seats,
    required this.depth,
    required this.degree,
  });

  final WikidataNode center;

  /// Length six, indexed by seat. Entries are null when Wikidata had fewer
  /// usable statements than there are seats.
  final List<WikidataNeighbor?> seats;

  /// Jumps made since launch. Drives the sweep arc.
  final int depth;

  /// How many distinct properties join this item to others. Stands in for
  /// how connected the topic is, and drives the centre tick ring.
  final int degree;

  int? seatOf(String qid) {
    for (var i = 0; i < seats.length; i++) {
      if (seats[i]?.node.qid == qid) return i;
    }
    return null;
  }

  Iterable<WikidataNeighbor> get occupied =>
      seats.whereType<WikidataNeighbor>();
}

/// Holds the current position in Wikidata and the path taken to reach it.
///
/// Every rosette is a fresh random draw, so the session cannot rebuild a
/// previous screen from memory — it keeps only the trail of item ids and
/// re-draws when the user steps back.
class TraversalSession {
  // ignore: prefer_initializing_formals — named parameters cannot be private.
  TraversalSession({required WikidataService service}) : _service = service;

  final WikidataService _service;
  final List<String> _history = <String>[];

  RosetteState? _rosette;

  RosetteState? get rosette => _rosette;

  String? get currentQid => _rosette?.center.qid;

  List<String> get history => List<String>.unmodifiable(_history);

  int get depth => _history.length;

  bool get canGoBack => _history.isNotEmpty;

  String? get previousQid => _history.isEmpty ? null : _history.last;

  /// Lands on a random topic drawn from the whole of Wikipedia.
  Future<void> start() async {
    final qid = await _service.randomStartQid();
    _history.clear();
    _rosette = await _build(qid, arrivedFrom: null);
  }

  /// Re-centres on a satellite, keeping a way back to where the user was.
  Future<void> jumpTo(String qid) async {
    final leaving = _rosette;
    if (leaving == null) return;
    final seat = leaving.seatOf(qid);
    if (seat == null) {
      throw ArgumentError('$qid is not currently on screen');
    }
    final back = _returnLink(leaving, seat);
    _history.add(leaving.center.qid);
    _rosette = await _build(
      qid,
      arrivedFrom: back,
      returnSeat: RosetteLayout.oppositeSeat(seat),
    );
  }

  /// Steps back one jump. The rosette is drawn again, so it will not be the
  /// same six satellites as before — that is the cost of a live random draw.
  Future<void> goBack() async {
    if (_history.isEmpty) return;
    final target = _history.removeLast();
    _rosette = await _build(target, arrivedFrom: null);
  }

  /// The edge that leads back, phrased from the new centre's point of view.
  WikidataNeighbor _returnLink(RosetteState leaving, int seat) {
    final taken = leaving.seats[seat]!;
    return WikidataNeighbor(
      node: leaving.center,
      relation: taken.relation,
      incoming: !taken.incoming,
    );
  }

  Future<RosetteState> _build(
    String qid, {
    required WikidataNeighbor? arrivedFrom,
    int? returnSeat,
  }) async {
    final center = await _service.node(qid);
    final drawn = await _service.sampleNeighbors(qid);
    final properties = await _service.propertiesFor(qid);

    final seats = List<WikidataNeighbor?>.filled(RosetteLayout.seatCount, null);
    final queue = drawn
        .where((n) => n.node.qid != arrivedFrom?.node.qid)
        .toList(growable: true);

    var fillOrder = List<int>.generate(RosetteLayout.seatCount, (i) => i);

    // The way back is guaranteed a seat, opposite the direction of travel,
    // because a random draw will usually not surface it on its own.
    if (arrivedFrom != null && returnSeat != null) {
      seats[returnSeat] = arrivedFrom;
      fillOrder = RosetteLayout.seatsAfter(returnSeat);
    }

    for (final seat in fillOrder) {
      if (queue.isEmpty) break;
      if (seats[seat] != null) continue;
      seats[seat] = queue.removeAt(0);
    }

    return RosetteState(
      center: center,
      seats: List<WikidataNeighbor?>.unmodifiable(seats),
      depth: _history.length,
      degree: properties.length,
    );
  }
}
