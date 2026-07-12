import 'dart:math';

import 'package:google_maps_flutter/google_maps_flutter.dart';

double _deg2rad(double deg) => deg * pi / 180;

double distanceNm(LatLng p1, LatLng p2) {
  const earthRadius = 6371000; // Meter
  final dLat = _deg2rad(p2.latitude - p1.latitude);
  final dLon = _deg2rad(p2.longitude - p1.longitude);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_deg2rad(p1.latitude)) *
          cos(_deg2rad(p2.latitude)) *
          sin(dLon / 2) *
          sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  final distanceMeters = earthRadius * c;
  return distanceMeters / 1852;
}

double distanceMeters(LatLng p1, LatLng p2) => distanceNm(p1, p2) * 1852;

double metersPerSecondToKnots(double mps) => mps * 1.94384;

// True course over ground, computed from two consecutive GPS fixes rather
// than the browser/device-reported Position.heading — that field is
// unreliable across platforms (commonly stuck at 0.0 on desktop browsers,
// which have no compass), while this works anywhere a boat is actually
// moving. Also the natural home for the future distance/bearing-to-mark
// calculation.
double bearing(LatLng from, LatLng to) {
  final lat1 = _deg2rad(from.latitude);
  final lat2 = _deg2rad(to.latitude);
  final dLon = _deg2rad(to.longitude - from.longitude);
  final y = sin(dLon) * cos(lat2);
  final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
  final theta = atan2(y, x);
  return (theta * 180 / pi + 360) % 360;
}
