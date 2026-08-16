import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// One connection drawn from the centre out to a satellite.
class EdgeFilament {
  const EdgeFilament({
    required this.hub,
    required this.hubRadius,
    required this.target,
    required this.targetRadius,
    required this.hue,
    required this.weight,
    required this.opacity,
  });

  final Offset hub;
  final double hubRadius;
  final Offset target;
  final double targetRadius;
  final Color hue;

  /// Relationship strength, 0..1. Sets both how bright the filament burns
  /// and how many cross ticks it carries.
  final double weight;

  final double opacity;
}

/// Draws the luminous filaments between centre and satellites.
///
/// Tick density along a filament is the edge weight made visible: a strong
/// relationship is rendered as a more heavily graduated line.
class EdgeFilamentPainter extends CustomPainter {
  const EdgeFilamentPainter(this.filaments);

  final List<EdgeFilament> filaments;

  static const int _minTicks = 2;
  static const int _maxTicks = 8;

  @override
  void paint(Canvas canvas, Size size) {
    for (final f in filaments) {
      if (f.opacity <= 0.01) continue;

      final delta = f.target - f.hub;
      final distance = delta.distance;
      if (distance <= f.hubRadius + f.targetRadius) continue;

      final unit = delta / distance;
      final start = f.hub + unit * f.hubRadius;
      final end = f.target - unit * f.targetRadius;

      final near = f.hue.withValues(alpha: (0.30 + 0.45 * f.weight) * f.opacity);
      final far = f.hue.withValues(alpha: 0.06 * f.opacity);

      final line = Paint()
        ..blendMode = BlendMode.plus
        ..strokeWidth = 0.8 + f.weight * 0.9
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(start, end, [near, far]);
      canvas.drawLine(start, end, line);

      _paintTicks(canvas, f, start, end, unit);
    }
  }

  void _paintTicks(
    Canvas canvas,
    EdgeFilament f,
    Offset start,
    Offset end,
    Offset unit,
  ) {
    final count = (f.weight * _maxTicks).round().clamp(_minTicks, _maxTicks);
    final normal = Offset(-unit.dy, unit.dx);
    final span = end - start;

    final paint = Paint()
      ..blendMode = BlendMode.plus
      ..strokeWidth = 0.7
      ..strokeCap = StrokeCap.round;

    for (var i = 1; i <= count; i++) {
      final t = i / (count + 1);
      final at = start + span * t;
      // Ticks shorten and dim as they travel away from the centre.
      final falloff = 1.0 - t * 0.65;
      final half = (1.4 + 1.8 * f.weight) * falloff;
      paint.color = f.hue.withValues(alpha: 0.42 * falloff * f.opacity);
      canvas.drawLine(at - normal * half, at + normal * half, paint);
    }
  }

  @override
  bool shouldRepaint(EdgeFilamentPainter oldDelegate) =>
      !identical(oldDelegate.filaments, filaments);
}

/// Shared helper so the instrument ring and the filaments agree on where
/// "the top" is.
const double kTopAngle = -pi / 2;
