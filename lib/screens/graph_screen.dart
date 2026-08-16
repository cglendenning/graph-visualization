import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/graph_node.dart';
import '../models/node_category.dart';
import '../models/rosette_layout.dart';
import '../painters/edge_filament_painter.dart';
import '../painters/instrument_painter.dart';
import '../services/graph_repository.dart';
import '../services/traversal_session.dart';
import '../services/wikipedia_service.dart';
import '../theme/hud_palette.dart';
import '../widgets/hud_readout.dart';
import '../widgets/node_circle.dart';
import 'node_detail_screen.dart';

/// Where a node sits on screen at a given instant of the transition.
class _Slot {
  const _Slot({
    required this.position,
    required this.radius,
    required this.isCenter,
    required this.neighbor,
  });

  final Offset position;
  final double radius;
  final bool isCenter;

  /// Null for the centre node, which has no relation to itself.
  final Neighbor? neighbor;
}

class _Placement {
  const _Placement({
    required this.node,
    required this.position,
    required this.radius,
    required this.opacity,
    required this.isCenter,
    required this.neighbor,
  });

  final GraphNode node;
  final Offset position;
  final double radius;
  final double opacity;
  final bool isCenter;
  final Neighbor? neighbor;
}

class GraphScreen extends StatefulWidget {
  const GraphScreen({
    super.key,
    required this.repository,
    required this.wikipediaService,
  });

  final GraphRepository repository;

  /// Held for the session so revisiting a node does not refetch its extract.
  final WikipediaService wikipediaService;

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _transition = Duration(milliseconds: 560);
  static const double _centerRadius = 64;
  static const double _satelliteRadius = 30;
  static const double _satelliteBlockWidth = 108;

  late final TraversalSession _session;
  late final AnimationController _controller;

  /// The rosette being left behind. Null when nothing is in flight.
  RosetteState? _from;
  late RosetteState _to;

  bool _hintVisible = true;

  @override
  void initState() {
    super.initState();
    _session = TraversalSession(
      repository: widget.repository,
      startId: widget.repository.randomNodeId(Random()),
    );
    _to = _session.rosette;
    _controller = AnimationController(vsync: this, duration: _transition)
      ..addListener(_onTick)
      ..addStatusListener(_onStatus);
    _controller.forward();
  }

  void _onTick() => setState(() {});

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _from != null) {
      setState(() => _from = null);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _inFlight => _controller.isAnimating;

  void _recenterOn(String nodeId) {
    if (_inFlight) return;
    HapticFeedback.lightImpact();
    setState(() {
      _from = _to;
      _session.jumpTo(nodeId);
      _to = _session.rosette;
      _hintVisible = false;
    });
    _controller.forward(from: 0);
  }

  void _stepBack() {
    if (_inFlight || !_session.canGoBack) return;
    HapticFeedback.lightImpact();
    setState(() {
      _from = _to;
      _session.goBack();
      _to = _session.rosette;
    });
    _controller.forward(from: 0);
  }

  void _openDetail() {
    if (_inFlight) return;
    Navigator.of(context).push(
      NodeDetailScreen.route(
        node: _to.center,
        degree: _to.degree,
        neighbors: widget.repository.neighborsOf(_to.center.id),
        wikipediaService: widget.wikipediaService,
        nodeCount: widget.repository.nodeCount,
      ),
    );
  }

  _Slot? _slotIn(RosetteState? state, String id, Offset center, double orbit) {
    if (state == null) return null;
    if (state.center.id == id) {
      return _Slot(
        position: center,
        radius: _centerRadius,
        isCenter: true,
        neighbor: null,
      );
    }
    final seat = state.seatOf(id);
    if (seat == null) return null;
    return _Slot(
      position: RosetteLayout.positionForSeat(seat, center, orbit),
      radius: _satelliteRadius,
      isCenter: false,
      neighbor: state.seats[seat],
    );
  }

  /// Arriving nodes hold back until the movement is mostly resolved, so the
  /// eye follows the re-centring instead of a general shimmer.
  double _arriveOpacity(double t) =>
      Curves.easeOut.transform(((t - 0.38) / 0.62).clamp(0.0, 1.0));

  double _departOpacity(double t) =>
      1.0 - Curves.easeIn.transform((t / 0.42).clamp(0.0, 1.0));

  List<_Placement> _placements(Offset center, double orbit, double t) {
    final ids = <String>{
      _to.center.id,
      ..._to.occupied.map((n) => n.node.id),
      if (_from != null) _from!.center.id,
      if (_from != null) ..._from!.occupied.map((n) => n.node.id),
    };

    final placements = <_Placement>[];
    for (final id in ids) {
      final a = _slotIn(_from, id, center, orbit);
      final b = _slotIn(_to, id, center, orbit);

      if (a != null && b != null) {
        placements.add(_Placement(
          node: _nodeFor(id),
          position: Offset.lerp(a.position, b.position, t)!,
          radius: lerpDouble(a.radius, b.radius, t),
          opacity: 1,
          isCenter: t < 0.5 ? a.isCenter : b.isCenter,
          neighbor: b.neighbor ?? a.neighbor,
        ));
      } else if (b != null) {
        placements.add(_Placement(
          node: _nodeFor(id),
          position: b.position,
          radius: b.radius,
          opacity: _arriveOpacity(t),
          isCenter: b.isCenter,
          neighbor: b.neighbor,
        ));
      } else if (a != null) {
        placements.add(_Placement(
          node: _nodeFor(id),
          position: a.position,
          radius: a.radius,
          opacity: _departOpacity(t),
          isCenter: a.isCenter,
          neighbor: a.neighbor,
        ));
      }
    }

    // Centre last so it sits above the filaments and its neighbours.
    placements.sort((x, y) {
      if (x.isCenter == y.isCenter) return 0;
      return x.isCenter ? 1 : -1;
    });
    return placements;
  }

  GraphNode _nodeFor(String id) => widget.repository.node(id);

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;

  List<EdgeFilament> _filaments(
    RosetteState state,
    Map<String, _Placement> byId,
    double opacity,
  ) {
    final hub = byId[state.center.id];
    if (hub == null || opacity <= 0.01) return const [];
    return [
      for (final n in state.occupied)
        if (byId[n.node.id] case final target?)
          EdgeFilament(
            hub: hub.position,
            hubRadius: hub.radius,
            target: target.position,
            targetRadius: target.radius,
            hue: n.node.category.color,
            weight: n.weight,
            opacity: opacity * target.opacity,
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final hue = _to.center.category.color;

    return Scaffold(
      backgroundColor: HudPalette.voidBlack,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: HudPalette.field(hue)),
        child: SafeArea(
          child: Column(
            children: [
              _TopBar(
                previousName: _session.canGoBack
                    ? widget.repository.node(_session.history.last).name
                    : null,
                onBack: _stepBack,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = constraints.biggest;
                    final center = Offset(size.width / 2, size.height * 0.47);
                    final orbit = min(
                      size.width / 2 - _satelliteRadius - 22,
                      size.height * 0.40,
                    );
                    return _buildCanvas(center, orbit, size);
                  },
                ),
              ),
              _Footer(
                depth: _session.depth,
                degree: _to.degree,
                category: _to.center.category,
                hintVisible: _hintVisible && _session.depth == 0,
                bottomInset: media.padding.bottom,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCanvas(Offset center, double orbit, Size size) {
    final t = Curves.easeInOutCubic.transform(_controller.value);
    final placements = _placements(center, orbit, t);
    final byId = {for (final p in placements) p.node.id: p};

    final incoming = _filaments(_to, byId, _arriveOpacity(t));
    final outgoing =
        _from == null ? <EdgeFilament>[] : _filaments(_from!, byId, _departOpacity(t));

    final toHub = byId[_to.center.id];
    final fromHub = _from == null ? null : byId[_from!.center.id];

    return IgnorePointer(
      ignoring: _inFlight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (fromHub != null)
            Positioned.fill(
              child: CustomPaint(
                painter: InstrumentPainter(
                  center: fromHub.position,
                  orbitRadius: orbit,
                  centerRadius: fromHub.radius,
                  degree: _from!.degree,
                  maxDegree: widget.repository.maxDegree,
                  depth: _from!.depth,
                  hue: _from!.center.category.color,
                  opacity: _departOpacity(t),
                ),
              ),
            ),
          if (toHub != null)
            Positioned.fill(
              child: CustomPaint(
                painter: InstrumentPainter(
                  center: toHub.position,
                  orbitRadius: orbit,
                  centerRadius: toHub.radius,
                  degree: _to.degree,
                  maxDegree: widget.repository.maxDegree,
                  depth: _session.depth,
                  hue: _to.center.category.color,
                  opacity: _arriveOpacity(t),
                ),
              ),
            ),
          Positioned.fill(
            child: CustomPaint(
              painter: EdgeFilamentPainter([...outgoing, ...incoming]),
            ),
          ),
          for (final p in placements) _buildNode(p),
        ],
      ),
    );
  }

  Widget _buildNode(_Placement p) {
    if (p.isCenter) {
      return Positioned(
        left: p.position.dx - p.radius,
        top: p.position.dy - p.radius,
        child: Opacity(
          opacity: p.opacity,
          child: GestureDetector(
            onTap: _openDetail,
            child: Hero(
              tag: 'node-${p.node.id}',
              // The backdrop blur is dropped mid-flight; blurring a moving
              // layer costs frames and reads no differently in transit.
              flightShuttleBuilder: (
                flightContext,
                animation,
                direction,
                fromContext,
                toContext,
              ) =>
                  NodeCircle(
                radius: p.radius,
                hue: p.node.category.color,
                child: _CenterLabel(name: p.node.name),
              ),
              child: NodeCircle(
                radius: p.radius,
                hue: p.node.category.color,
                frosted: true,
                child: _CenterLabel(name: p.node.name),
              ),
            ),
          ),
        ),
      );
    }

    return Positioned(
      left: p.position.dx - _satelliteBlockWidth / 2,
      top: p.position.dy - p.radius,
      width: _satelliteBlockWidth,
      child: Opacity(
        opacity: p.opacity,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _recenterOn(p.node.id),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NodeCircle(
                radius: p.radius,
                hue: p.node.category.color,
                emphasis: 0.85,
              ),
              const SizedBox(height: 7),
              Text(
                p.node.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: HudPalette.satelliteName,
              ),
              if (p.neighbor != null) ...[
                const SizedBox(height: 3),
                Text(
                  p.neighbor!.relation.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: HudPalette.relation,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CenterLabel extends StatelessWidget {
  const _CenterLabel({required this.name});

  final String name;

  /// Long titles step down rather than clipping; the circle is the frame and
  /// the name has to live inside it.
  double get _fontSize {
    if (name.length <= 12) return 18;
    if (name.length <= 20) return 16;
    if (name.length <= 30) return 14;
    return 12;
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      name,
      textAlign: TextAlign.center,
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      style: HudPalette.nodeName.copyWith(fontSize: _fontSize),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.previousName, required this.onBack});

  final String? previousName;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: previousName == null
          ? null
          : Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onBack,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.chevron_left,
                        size: 18,
                        color: HudPalette.aquaDim,
                      ),
                      const SizedBox(width: 2),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 190),
                        child: Text(
                          previousName!.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: HudPalette.telemetry,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.depth,
    required this.degree,
    required this.category,
    required this.hintVisible,
    required this.bottomInset,
  });

  final int depth;
  final int degree;
  final NodeCategory category;
  final bool hintVisible;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset > 0 ? 8 : 22, top: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          HudReadout(
            depth: depth,
            degree: degree,
            categoryLabel: category.label,
            hue: category.color,
          ),
          SizedBox(
            height: 22,
            child: AnimatedOpacity(
              opacity: hintVisible ? 1 : 0,
              duration: const Duration(milliseconds: 400),
              child: Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Text(
                  'TAP A SATELLITE TO TRAVEL  ·  TAP THE CENTRE FOR DETAIL',
                  style: HudPalette.telemetry.copyWith(
                    fontSize: 8.5,
                    color: HudPalette.aquaDim,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
