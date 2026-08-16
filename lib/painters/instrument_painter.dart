import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/hud_palette.dart';

/// The rings around the centre node. Every mark here reports something:
///
///  * the orbit ring is the exact radius the satellites sit on
///  * the tick ring carries one tick per connection the centre node has,
///    so a well-connected node is visibly denser
///  * the sweep arc fills clockwise as the traversal gets deeper
class InstrumentPainter extends CustomPainter {
  const InstrumentPainter({
    required this.center,
    required this.orbitRadius,
    required this.centerRadius,
    required this.degree,
    required this.maxDegree,
    required this.depth,
    required this.hue,
    required this.opacity,
  });

  final Offset center;
  final double orbitRadius;
  final double centerRadius;
  final int degree;
  final int maxDegree;
  final int depth;
  final Color hue;
  final double opacity;

  /// Jumps per full revolution of the sweep arc. The exact count is in the
  /// footer readout; the arc is for glanceable progress.
  static const int sweepPeriod = 18;

  static const double _topAngle = -pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.01) return;
    _paintOrbit(canvas);
    _paintDegreeTicks(canvas);
    _paintSweep(canvas);
  }

  void _paintOrbit(Canvas canvas) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = HudPalette.aqua.withValues(alpha: 0.07 * opacity);
    canvas.drawCircle(center, orbitRadius, paint);
  }

  void _paintDegreeTicks(Canvas canvas) {
    if (degree <= 0) return;
    final radius = centerRadius + 11;
    final step = 2 * pi / degree;

    // Longer ticks for a more connected node, so density and length agree.
    final emphasis = maxDegree <= 0 ? 0.0 : (degree / maxDegree).clamp(0.0, 1.0);
    final length = 3.0 + emphasis * 3.0;

    final paint = Paint()
      ..blendMode = BlendMode.plus
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..color = hue.withValues(alpha: 0.55 * opacity);

    for (var i = 0; i < degree; i++) {
      final angle = _topAngle + i * step;
      final dir = Offset(cos(angle), sin(angle));
      canvas.drawLine(
        center + dir * radius,
        center + dir * (radius + length),
        paint,
      );
    }
  }

  void _paintSweep(Canvas canvas) {
    final radius = centerRadius + 20;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = HudPalette.aqua.withValues(alpha: 0.08 * opacity);
    canvas.drawCircle(center, radius, track);

    if (depth <= 0) return;

    // Wraps, so a long traversal keeps producing motion rather than pinning.
    final progress = (depth % sweepPeriod) / sweepPeriod;
    final swept = progress == 0 ? 2 * pi : progress * 2 * pi;

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..blendMode = BlendMode.plus
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = HudPalette.aqua.withValues(alpha: 0.75 * opacity);
    canvas.drawArc(rect, _topAngle, swept, false, arc);

    // A brighter head on the leading edge of the sweep.
    final headAngle = _topAngle + swept;
    final head = center + Offset(cos(headAngle), sin(headAngle)) * radius;
    canvas.drawCircle(
      head,
      1.8,
      Paint()
        ..blendMode = BlendMode.plus
        ..color = HudPalette.aqua.withValues(alpha: 0.9 * opacity),
    );
  }

  @override
  bool shouldRepaint(InstrumentPainter old) =>
      old.center != center ||
      old.degree != degree ||
      old.depth != depth ||
      old.hue != hue ||
      old.opacity != opacity ||
      old.centerRadius != centerRadius ||
      old.orbitRadius != orbitRadius;
}
