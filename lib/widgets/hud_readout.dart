import 'package:flutter/material.dart';

import '../theme/hud_palette.dart';

/// The footer telemetry line: how far the user has travelled, how connected
/// the current node is, and what kind of thing it is.
class HudReadout extends StatelessWidget {
  const HudReadout({
    super.key,
    required this.depth,
    required this.degree,
    required this.categoryLabel,
    required this.hue,
  });

  final int depth;
  final int degree;
  final String categoryLabel;
  final Color hue;

  static String _pad(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: HudPalette.telemetry,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('DEPTH ${_pad(depth)}'),
          _dot(),
          Text('DEG ${_pad(degree)}'),
          _dot(),
          Text(categoryLabel, style: HudPalette.telemetry.copyWith(color: hue)),
        ],
      ),
    );
  }

  Widget _dot() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Container(
          width: 2,
          height: 2,
          decoration: const BoxDecoration(
            color: HudPalette.aquaDim,
            shape: BoxShape.circle,
          ),
        ),
      );
}
