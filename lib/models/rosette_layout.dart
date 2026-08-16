import 'dart:math';

import 'package:flutter/painting.dart' show Offset;

/// Geometry of the six satellite seats around the centre.
///
/// Seat 0 is at the top and seats advance clockwise, so a seat index is a
/// stable spatial position rather than just a list slot.
class RosetteLayout {
  const RosetteLayout._();

  static const int seatCount = 6;

  static const double _topAngle = -pi / 2;
  static const double _step = 2 * pi / seatCount;

  static double angleForSeat(int seat) {
    assert(seat >= 0 && seat < seatCount);
    return _topAngle + seat * _step;
  }

  static Offset positionForSeat(int seat, Offset center, double radius) {
    final angle = angleForSeat(seat);
    return Offset(
      center.dx + radius * cos(angle),
      center.dy + radius * sin(angle),
    );
  }

  /// The seat directly across the rosette.
  ///
  /// When the user moves toward a satellite, the node they left is placed
  /// here — behind them, where the eye expects the way back to be.
  static int oppositeSeat(int seat) {
    assert(seat >= 0 && seat < seatCount);
    return (seat + seatCount ~/ 2) % seatCount;
  }

  /// Seats in fill order starting just after [from], wrapping around.
  static List<int> seatsAfter(int from) => List<int>.generate(
        seatCount - 1,
        (i) => (from + 1 + i) % seatCount,
      );
}
