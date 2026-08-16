import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/node_category.dart';
import '../models/rosette_layout.dart';
import '../models/wikidata_node.dart';
import '../painters/edge_filament_painter.dart';
import '../painters/instrument_painter.dart';
import '../services/traversal_session.dart';
import '../services/wikidata_service.dart';
import '../services/wikipedia_service.dart';
import '../theme/hud_palette.dart';
import '../widgets/hud_readout.dart';
import '../widgets/keyword_filter_sheet.dart';
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
  final WikidataNeighbor? neighbor;
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

  final WikidataNode node;
  final Offset position;
  final double radius;
  final double opacity;
  final bool isCenter;
  final WikidataNeighbor? neighbor;
}

class GraphScreen extends StatefulWidget {
  const GraphScreen({
    super.key,
    required this.wikidata,
    required this.wikipediaService,
  });

  final WikidataService wikidata;
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

  RosetteState? _from;
  RosetteState? _to;

  bool _busy = true;
  String? _error;
  bool _hintVisible = true;

  @override
  void initState() {
    super.initState();
    _session = TraversalSession(service: widget.wikidata);
    _controller = AnimationController(vsync: this, duration: _transition)
      ..addListener(_onTick)
      ..addStatusListener(_onStatus);
    _load(() => _session.start());
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

  /// Runs one navigation step, holding the outgoing rosette on screen until
  /// the new one has arrived so the canvas never blanks out mid-jump.
  Future<void> _load(Future<void> Function() step) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final outgoing = _to;
      await step();
      if (!mounted) return;
      setState(() {
        _from = outgoing;
        _to = _session.rosette;
        _busy = false;
      });
      _controller.forward(from: 0);

      // Draw the next rosette for each satellite while the reader is looking
      // at this one. Whichever they tap is then already in hand.
      final arrived = _session.rosette;
      if (arrived != null) {
        widget.wikidata
          ..cancelPendingPrefetch()
          ..prefetch(arrived.occupied.map((n) => n.node.qid))
          ..prefetchRandomTopics();
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error is WikidataUnavailable
            ? error.message
            : 'Could not reach Wikidata. Check your connection.';
      });
    }
  }

  void _recenterOn(String qid) {
    if (_inFlight || _busy) return;
    HapticFeedback.lightImpact();
    _hintVisible = false;
    _load(() => _session.jumpTo(qid));
  }

  void _stepBack() {
    if (_inFlight || _busy || !_session.canGoBack) return;
    HapticFeedback.lightImpact();
    _load(() => _session.goBack());
  }

  void _reroll() {
    if (_inFlight || _busy) return;
    HapticFeedback.lightImpact();
    _load(() => _session.start());
  }

  Future<void> _openFilter() async {
    if (_inFlight || _busy) return;
    final result = await KeywordFilterSheet.show(
      context,
      initial: widget.wikidata.keywords.join(' '),
    );
    if (result == null || !mounted) return;
    widget.wikidata.setKeywords(result.terms);
    // Redraw where we stand, so the constraint takes effect without losing
    // the reader's place in the graph.
    await _load(() => _session.refresh());
    // Unless nothing here matches at all — then stranding the reader on a
    // dead end is worse than moving them somewhere the constraint applies.
    if (!mounted) return;
    if (widget.wikidata.isFiltered && (_to?.occupied.isEmpty ?? false)) {
      await _load(() => _session.start());
    }
  }

  void _openDetail() {
    final current = _to;
    if (_inFlight || _busy || current == null) return;
    Navigator.of(context).push(
      NodeDetailScreen.route(
        node: current.center,
        degree: current.degree,
        neighbors: current.occupied.toList(growable: false),
        wikipediaService: widget.wikipediaService,
      ),
    );
  }

  _Slot? _slotIn(RosetteState? state, String qid, Offset center, double orbit) {
    if (state == null) return null;
    if (state.center.qid == qid) {
      return _Slot(
        position: center,
        radius: _centerRadius,
        isCenter: true,
        neighbor: null,
      );
    }
    final seat = state.seatOf(qid);
    if (seat == null) return null;
    return _Slot(
      position: RosetteLayout.positionForSeat(seat, center, orbit),
      radius: _satelliteRadius,
      isCenter: false,
      neighbor: state.seats[seat],
    );
  }

  double _arriveOpacity(double t) =>
      Curves.easeOut.transform(((t - 0.38) / 0.62).clamp(0.0, 1.0));

  double _departOpacity(double t) =>
      1.0 - Curves.easeIn.transform((t / 0.42).clamp(0.0, 1.0));

  WikidataNode? _nodeFor(String qid) {
    for (final state in [_to, _from]) {
      if (state == null) continue;
      if (state.center.qid == qid) return state.center;
      for (final n in state.occupied) {
        if (n.node.qid == qid) return n.node;
      }
    }
    return null;
  }

  List<_Placement> _placements(Offset center, double orbit, double t) {
    final ids = <String>{
      if (_to != null) _to!.center.qid,
      if (_to != null) ..._to!.occupied.map((n) => n.node.qid),
      if (_from != null) _from!.center.qid,
      if (_from != null) ..._from!.occupied.map((n) => n.node.qid),
    };

    final placements = <_Placement>[];
    for (final qid in ids) {
      final node = _nodeFor(qid);
      if (node == null) continue;
      final a = _slotIn(_from, qid, center, orbit);
      final b = _slotIn(_to, qid, center, orbit);

      if (a != null && b != null) {
        placements.add(_Placement(
          node: node,
          position: Offset.lerp(a.position, b.position, t)!,
          radius: _lerp(a.radius, b.radius, t),
          opacity: 1,
          isCenter: t < 0.5 ? a.isCenter : b.isCenter,
          neighbor: b.neighbor ?? a.neighbor,
        ));
      } else if (b != null) {
        placements.add(_Placement(
          node: node,
          position: b.position,
          radius: b.radius,
          opacity: _arriveOpacity(t),
          isCenter: b.isCenter,
          neighbor: b.neighbor,
        ));
      } else if (a != null) {
        placements.add(_Placement(
          node: node,
          position: a.position,
          radius: a.radius,
          opacity: _departOpacity(t),
          isCenter: a.isCenter,
          neighbor: a.neighbor,
        ));
      }
    }

    placements.sort((x, y) {
      if (x.isCenter == y.isCenter) return 0;
      return x.isCenter ? 1 : -1;
    });
    return placements;
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  List<EdgeFilament> _filaments(
    RosetteState state,
    Map<String, _Placement> byId,
    double opacity,
  ) {
    final hub = byId[state.center.qid];
    if (hub == null || opacity <= 0.01) return const [];
    return [
      for (final n in state.occupied)
        if (byId[n.node.qid] case final target?)
          EdgeFilament(
            hub: hub.position,
            hubRadius: hub.radius,
            target: target.position,
            targetRadius: target.radius,
            hue: n.node.category.color,
            // Live statements carry no strength, so every filament is drawn
            // the same. Nothing here should imply a ranking that Wikidata
            // does not actually provide.
            weight: 0.62,
            opacity: opacity * target.opacity,
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final current = _to;
    final hue = current?.center.category.color ?? HudPalette.aqua;

    return Scaffold(
      backgroundColor: HudPalette.voidBlack,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: HudPalette.field(hue)),
        child: SafeArea(
          child: Column(
            children: [
              _TopBar(
                canGoBack: _session.canGoBack && !_busy,
                onBack: _stepBack,
                onReroll: _busy ? null : _reroll,
                onFilter: _busy ? null : _openFilter,
                keywords: widget.wikidata.keywords,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (_error != null) {
                      return _Failure(message: _error!, onRetry: _reroll);
                    }
                    if (current == null) {
                      return const _Booting();
                    }
                    final size = constraints.biggest;
                    final center = Offset(size.width / 2, size.height * 0.47);
                    final orbit = min(
                      size.width / 2 - _satelliteRadius - 22,
                      size.height * 0.40,
                    );
                    return _buildCanvas(center, orbit);
                  },
                ),
              ),
              _Footer(
                depth: _session.depth,
                degree: current?.degree ?? 0,
                category: current?.center.category ?? NodeCategory.concept,
                busy: _busy,
                hintVisible: _hintVisible && _session.depth == 0 && !_busy,
                bottomInset: media.padding.bottom,
                filtered: widget.wikidata.isFiltered,
                matched: current?.occupied.length ?? 0,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCanvas(Offset center, double orbit) {
    final t = Curves.easeInOutCubic.transform(_controller.value);
    final placements = _placements(center, orbit, t);
    final byId = {for (final p in placements) p.node.qid: p};

    final incoming = _to == null
        ? <EdgeFilament>[]
        : _filaments(_to!, byId, _arriveOpacity(t));
    final outgoing = _from == null
        ? <EdgeFilament>[]
        : _filaments(_from!, byId, _departOpacity(t));

    final toHub = _to == null ? null : byId[_to!.center.qid];

    return IgnorePointer(
      ignoring: _inFlight || _busy,
      child: Opacity(
        opacity: _busy ? 0.45 : 1,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (toHub != null)
              Positioned.fill(
                child: CustomPaint(
                  painter: InstrumentPainter(
                    center: toHub.position,
                    orbitRadius: orbit,
                    centerRadius: toHub.radius,
                    degree: _to!.degree,
                    maxDegree: 140,
                    depth: _session.depth,
                    hue: _to!.center.category.color,
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
            child: NodeCircle(
              radius: p.radius,
              hue: p.node.category.color,
              frosted: true,
              child: _CenterLabel(name: p.node.label),
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
          onTap: () => _recenterOn(p.node.qid),
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
                p.node.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: HudPalette.satelliteName,
              ),
              if (p.neighbor != null) ...[
                const SizedBox(height: 3),
                Text(
                  p.neighbor!.phrasing.toUpperCase(),
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

class _Booting extends StatelessWidget {
  const _Booting();

  @override
  Widget build(BuildContext context) => Center(
        child: Text('FINDING A TOPIC', style: HudPalette.telemetry),
      );
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.55,
                color: Color(0xFF7E97A4),
              ),
            ),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border:
                      Border.all(color: HudPalette.aqua.withValues(alpha: 0.35)),
                ),
                child: Text(
                  'TRY ANOTHER TOPIC',
                  style: HudPalette.telemetry.copyWith(color: HudPalette.aqua),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.canGoBack,
    required this.onBack,
    required this.onReroll,
    required this.onFilter,
    required this.keywords,
  });

  final bool canGoBack;
  final VoidCallback onBack;
  final VoidCallback? onReroll;
  final VoidCallback? onFilter;
  final List<String> keywords;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Row(
        // Stretch, so each control is as tall as the bar and comfortably
        // tappable rather than a hairline of text.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canGoBack)
            _BarButton(
              onTap: onBack,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chevron_left, size: 18, color: HudPalette.aquaDim),
                  SizedBox(width: 2),
                  Text('BACK', style: HudPalette.telemetry),
                ],
              ),
            ),
          const Spacer(),
          _BarButton(
            onTap: onFilter,
            child: keywords.isEmpty
                ? Text(
                    'FILTER',
                    style: HudPalette.telemetry.copyWith(
                      color: onFilter == null
                          ? HudPalette.aquaDim.withValues(alpha: 0.4)
                          : HudPalette.aquaDim,
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: HudPalette.aqua.withValues(alpha: 0.45),
                      ),
                      color: HudPalette.aqua.withValues(alpha: 0.10),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 128),
                      child: Text(
                        keywords.join(' ').toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HudPalette.telemetry
                            .copyWith(color: HudPalette.aqua),
                      ),
                    ),
                  ),
          ),
          const Spacer(),
          _BarButton(
            onTap: onReroll,
            child: Text(
              'NEW TOPIC',
              style: HudPalette.telemetry.copyWith(
                color: onReroll == null
                    ? HudPalette.aquaDim.withValues(alpha: 0.4)
                    : HudPalette.aquaDim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A control in the top bar.
///
/// Fills the bar's full height on purpose: laid out by its label alone, a
/// line of 10px telemetry type gives a hit area about ten pixels tall, which
/// reads to the user as a button that does not work.
class _BarButton extends StatelessWidget {
  const _BarButton({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Center(widthFactor: 1, child: child),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.depth,
    required this.degree,
    required this.category,
    required this.busy,
    required this.hintVisible,
    required this.bottomInset,
    required this.filtered,
    required this.matched,
  });

  final int depth;
  final int degree;
  final NodeCategory category;
  final bool busy;
  final bool hintVisible;
  final double bottomInset;
  final bool filtered;
  final int matched;

  /// A filtered rosette is often partly empty on purpose, so it says so
  /// rather than leaving the reader wondering what went wrong.
  String get _hint {
    if (busy) return 'DRAWING FROM WIKIDATA';
    if (filtered) {
      return matched == 0
          ? 'NOTHING HERE MATCHES  ·  TRY FEWER WORDS OR CLEAR THE FILTER'
          : 'MATCHING ${matched.toString().padLeft(2, '0')} OF 06';
    }
    return 'TAP A SATELLITE TO TRAVEL  ·  TAP THE CENTRE FOR DETAIL';
  }

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
              opacity: busy || hintVisible || filtered ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Text(
                  _hint,
                  textAlign: TextAlign.center,
                  style: HudPalette.telemetry.copyWith(
                    fontSize: 8.5,
                    color: busy
                        ? HudPalette.aqua
                        : (filtered && matched == 0)
                            ? HudPalette.amber
                            : HudPalette.aquaDim,
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
