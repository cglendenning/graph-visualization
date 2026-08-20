import 'dart:ui';

import 'package:flutter/material.dart';

/// A luminous glass disc.
///
/// Only the center node frosts what is behind it — running a backdrop blur
/// on all seven circles costs more than it shows at satellite size, and the
/// transition animates twelve of them at once.
class NodeCircle extends StatelessWidget {
  const NodeCircle({
    super.key,
    required this.radius,
    required this.hue,
    this.frosted = false,
    this.emphasis = 1.0,
    this.child,
  });

  final double radius;
  final Color hue;
  final bool frosted;

  /// Scales the ring brightness and bloom. The center runs at 1.0 and the
  /// satellites sit back at a lower value so the hierarchy is unambiguous.
  final double emphasis;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final disc = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 1.05,
          colors: [
            hue.withValues(alpha: 0.26 * emphasis),
            hue.withValues(alpha: 0.10 * emphasis),
            hue.withValues(alpha: 0.03),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        border: Border.fromBorderSide(
          BorderSide(
            color: hue.withValues(alpha: 0.55 * emphasis),
            width: frosted ? 1.5 : 1.1,
          ),
        ),
      ),
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: child == null
            ? null
            : Padding(
                padding: EdgeInsets.all(radius * 0.16),
                child: Center(child: child),
              ),
      ),
    );

    final lit = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: hue.withValues(alpha: 0.30 * emphasis),
            blurRadius: radius * 0.75,
          ),
          BoxShadow(
            color: hue.withValues(alpha: 0.14 * emphasis),
            blurRadius: radius * 1.8,
          ),
        ],
      ),
      child: frosted
          ? ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: disc,
              ),
            )
          : disc,
    );

    return SizedBox(width: radius * 2, height: radius * 2, child: lit);
  }
}
