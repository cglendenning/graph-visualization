import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/graph_node.dart';
import '../services/wikipedia_service.dart';
import '../theme/hud_palette.dart';
import '../widgets/node_circle.dart';
import '../widgets/wikipedia_section.dart';

/// Everything the graph knows about one node.
///
/// Pushed with a Cupertino route so the edge swipe back works without any
/// extra handling — getting out is meant to be effortless.
class NodeDetailScreen extends StatelessWidget {
  const NodeDetailScreen({
    super.key,
    required this.node,
    required this.degree,
    required this.neighbors,
    required this.wikipediaService,
  });

  final GraphNode node;
  final int degree;
  final List<Neighbor> neighbors;
  final WikipediaService wikipediaService;

  static Route<void> route({
    required GraphNode node,
    required int degree,
    required List<Neighbor> neighbors,
    required WikipediaService wikipediaService,
  }) =>
      CupertinoPageRoute<void>(
        builder: (_) => NodeDetailScreen(
          node: node,
          degree: degree,
          neighbors: neighbors,
          wikipediaService: wikipediaService,
        ),
      );

  static const double _heroRadius = 52;

  @override
  Widget build(BuildContext context) {
    final hue = node.category.color;

    return Scaffold(
      backgroundColor: HudPalette.voidBlack,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: HudPalette.field(hue)),
        child: SafeArea(
          child: Column(
            children: [
              _CloseBar(onClose: () => Navigator.of(context).pop()),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 48),
                  children: [
                    Center(
                      child: Hero(
                        tag: 'node-${node.id}',
                        child: NodeCircle(
                          radius: _heroRadius,
                          hue: hue,
                          frosted: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Text(
                      node.name,
                      textAlign: TextAlign.center,
                      style: HudPalette.nodeName.copyWith(
                        fontSize: 27,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(child: _CategoryChip(node: node, degree: degree)),
                    const SizedBox(height: 20),
                    Text(
                      node.tagline,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.4,
                        color: hue.withValues(alpha: 0.85),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _Rule(hue: hue),
                    const SizedBox(height: 24),
                    WikipediaSection(
                      service: wikipediaService,
                      title: node.wikipediaTitle,
                      hue: hue,
                    ),
                    const SizedBox(height: 30),
                    _SectionLabel('RECORD'),
                    const SizedBox(height: 14),
                    for (final fact in node.facts) _FactRow(fact: fact),
                    const SizedBox(height: 26),
                    _SectionLabel(
                      'CONNECTIONS  ·  ${neighbors.length.toString().padLeft(2, '0')}',
                    ),
                    const SizedBox(height: 14),
                    for (final n in neighbors) _ConnectionRow(neighbor: n),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloseBar extends StatelessWidget {
  const _CloseBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onClose,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.chevron_left,
                  size: 16,
                  color: HudPalette.aquaDim,
                ),
                SizedBox(width: 5),
                Text('GRAPH', style: HudPalette.telemetry),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.node, required this.degree});

  final GraphNode node;
  final int degree;

  @override
  Widget build(BuildContext context) {
    final hue = node.category.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: hue.withValues(alpha: 0.32)),
        color: hue.withValues(alpha: 0.07),
      ),
      child: Text(
        '${node.category.label}  ·  DEG ${degree.toString().padLeft(2, '0')}',
        style: HudPalette.telemetry.copyWith(color: hue),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.hue});

  final Color hue;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            hue.withValues(alpha: 0),
            hue.withValues(alpha: 0.35),
            hue.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: HudPalette.telemetry.copyWith(letterSpacing: 2.2));
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.fact});

  final NodeFact fact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              fact.label,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: Color(0xFF6E8794),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              fact.value,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: Color(0xFFCFDFE9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({required this.neighbor});

  final Neighbor neighbor;

  @override
  Widget build(BuildContext context) {
    final hue = neighbor.node.category.color;
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hue.withValues(alpha: 0.85),
                boxShadow: [
                  BoxShadow(color: hue.withValues(alpha: 0.5), blurRadius: 6),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  neighbor.node.name,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.3,
                    color: Color(0xFFCFDFE9),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  neighbor.relation.toUpperCase(),
                  style: HudPalette.relation.copyWith(fontSize: 9),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
