import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:perihelion/models/rosette_layout.dart';

void main() {
  group('RosetteLayout', () {
    test('seat 0 sits directly above the center', () {
      const center = Offset(100, 100);
      final p = RosetteLayout.positionForSeat(0, center, 50);
      expect(p.dx, closeTo(100, 0.001));
      expect(p.dy, closeTo(50, 0.001));
    });

    test('seats advance clockwise in even sixths', () {
      for (var seat = 0; seat < RosetteLayout.seatCount; seat++) {
        final expected = -pi / 2 + seat * (2 * pi / 6);
        expect(RosetteLayout.angleForSeat(seat), closeTo(expected, 1e-9));
      }
    });

    test('every seat sits on the radius', () {
      const center = Offset(0, 0);
      for (var seat = 0; seat < RosetteLayout.seatCount; seat++) {
        final p = RosetteLayout.positionForSeat(seat, center, 120);
        expect(p.distance, closeTo(120, 0.001));
      }
    });

    test('opposite seat is three away and is its own inverse', () {
      expect(RosetteLayout.oppositeSeat(0), 3);
      expect(RosetteLayout.oppositeSeat(4), 1);
      for (var seat = 0; seat < RosetteLayout.seatCount; seat++) {
        expect(
          RosetteLayout.oppositeSeat(RosetteLayout.oppositeSeat(seat)),
          seat,
        );
      }
    });

    test('seatsAfter returns the other five seats, wrapping', () {
      expect(RosetteLayout.seatsAfter(4), [5, 0, 1, 2, 3]);
      expect(RosetteLayout.seatsAfter(0), [1, 2, 3, 4, 5]);
      for (var seat = 0; seat < RosetteLayout.seatCount; seat++) {
        final after = RosetteLayout.seatsAfter(seat);
        expect(after, hasLength(5));
        expect(after.toSet(), isNot(contains(seat)));
      }
    });
  });
}
