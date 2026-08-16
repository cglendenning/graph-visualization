import 'package:flutter/material.dart';

/// The instrument palette: aqua-on-near-black, with everything luminous
/// drawn additively so overlapping glows brighten rather than muddy.
class HudPalette {
  const HudPalette._();

  static const Color voidBlack = Color(0xFF05070C);
  static const Color deepField = Color(0xFF0A121C);

  static const Color aqua = Color(0xFF56E8FF);
  static const Color aquaDim = Color(0xFF2E7F94);
  static const Color ice = Color(0xFFDCE9F5);

  /// Telemetry text: hairline, wide-tracked, tabular so digits do not jitter
  /// as the depth counter climbs.
  static const TextStyle telemetry = TextStyle(
    fontFamily: 'Menlo',
    fontFamilyFallback: ['Courier', 'monospace'],
    fontSize: 10,
    height: 1.0,
    letterSpacing: 1.6,
    fontWeight: FontWeight.w400,
    color: Color(0xFF7FB8C9),
  );

  static const TextStyle nodeName = TextStyle(
    fontSize: 19,
    height: 1.15,
    letterSpacing: -0.2,
    fontWeight: FontWeight.w600,
    color: ice,
  );

  static const TextStyle satelliteName = TextStyle(
    fontSize: 11.5,
    height: 1.2,
    letterSpacing: -0.05,
    fontWeight: FontWeight.w500,
    color: ice,
  );

  static const TextStyle relation = TextStyle(
    fontFamily: 'Menlo',
    fontFamilyFallback: ['Courier', 'monospace'],
    fontSize: 8.5,
    height: 1.25,
    letterSpacing: 0.4,
    fontWeight: FontWeight.w400,
    color: Color(0xFF6E93A3),
  );

  /// Background wash, warmed very slightly toward the centre node's hue.
  static RadialGradient field(Color hue) => RadialGradient(
        center: const Alignment(0, -0.12),
        radius: 0.95,
        colors: [
          Color.lerp(deepField, hue, 0.07)!,
          voidBlack,
          voidBlack,
        ],
        stops: const [0.0, 0.62, 1.0],
      );
}
