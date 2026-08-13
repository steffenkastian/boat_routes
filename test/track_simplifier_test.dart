import 'package:boat_routes_web/utils/track_simplifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  test('collapses a near-straight line to its endpoints', () {
    // Longitude wiggle of 0.00001deg is ~0.65m at this latitude — well
    // under the 5m tolerance below.
    final straight = <LatLng>[
      const LatLng(54.0000, 11.0000),
      const LatLng(54.0010, 11.00001),
      const LatLng(54.0020, 11.0000),
      const LatLng(54.0030, 11.00001),
      const LatLng(54.0040, 11.0000),
    ];
    final result = simplifyTrack(straight, toleranceMeters: 5);
    expect(result.length, 2);
    expect(result.first, straight.first);
    expect(result.last, straight.last);
  });

  test('keeps a real corner (tack)', () {
    final turn = <LatLng>[
      const LatLng(54.0000, 11.0000),
      const LatLng(54.0010, 11.0000),
      const LatLng(54.0020, 11.0000),
      const LatLng(54.0020, 11.0010),
      const LatLng(54.0020, 11.0020),
    ];
    final result = simplifyTrack(turn, toleranceMeters: 5);
    expect(result.length, 3);
    expect(result[1].latitude, closeTo(54.0020, 1e-9));
    expect(result[1].longitude, closeTo(11.0000, 1e-9));
  });

  test('passes short tracks through unchanged', () {
    final short = <LatLng>[const LatLng(54, 11), const LatLng(54.001, 11.001)];
    expect(simplifyTrack(short).length, 2);
    expect(simplifyTrack(const []), isEmpty);
  });
}
