import 'dart:math';

import 'package:google_maps_flutter/google_maps_flutter.dart';

// Reduces a recorded GPS track to fewer points while preserving its shape,
// via the Ramer–Douglas–Peucker algorithm: within a run of points, only the
// one farthest from the straight line connecting its ends is kept (and
// recursed into) if that distance exceeds [toleranceMeters] — everything
// else on a (near-)straight stretch is dropped. Applied once at save time
// (see ToursScreen._endTour) rather than live during recording, since a
// multi-hour track can otherwise accumulate thousands of points that get
// stored three times over (locally, in the cloud, in every share) and
// redrawn on every map render.
List<LatLng> simplifyTrack(List<LatLng> points, {double toleranceMeters = 5}) {
  if (points.length < 3) return points;

  final keep = List<bool>.filled(points.length, false);
  keep[0] = true;
  keep[points.length - 1] = true;
  _simplifySegment(points, 0, points.length - 1, toleranceMeters, keep);

  return [
    for (var i = 0; i < points.length; i++)
      if (keep[i]) points[i],
  ];
}

void _simplifySegment(
  List<LatLng> points,
  int startIndex,
  int endIndex,
  double toleranceMeters,
  List<bool> keep,
) {
  if (endIndex <= startIndex + 1) return;

  var maxDistance = 0.0;
  var maxIndex = -1;
  for (var i = startIndex + 1; i < endIndex; i++) {
    final distance = _perpendicularDistanceMeters(
      points[i],
      points[startIndex],
      points[endIndex],
    );
    if (distance > maxDistance) {
      maxDistance = distance;
      maxIndex = i;
    }
  }

  if (maxIndex != -1 && maxDistance > toleranceMeters) {
    keep[maxIndex] = true;
    _simplifySegment(points, startIndex, maxIndex, toleranceMeters, keep);
    _simplifySegment(points, maxIndex, endIndex, toleranceMeters, keep);
  }
}

// Perpendicular distance from `point` to the line through `lineStart` and
// `lineEnd`, in meters. Uses a local flat-earth (equirectangular)
// approximation around lineStart rather than full great-circle geometry —
// accurate enough at the sub-kilometer scale this runs at, and far simpler
// than the alternative.
double _perpendicularDistanceMeters(
  LatLng point,
  LatLng lineStart,
  LatLng lineEnd,
) {
  const metersPerDegreeLat = 111320.0;
  final metersPerDegreeLng =
      metersPerDegreeLat * cos(lineStart.latitude * pi / 180);

  double toX(LatLng p) =>
      (p.longitude - lineStart.longitude) * metersPerDegreeLng;
  double toY(LatLng p) => (p.latitude - lineStart.latitude) * metersPerDegreeLat;

  final x1 = toX(lineStart);
  final y1 = toY(lineStart);
  final x2 = toX(lineEnd);
  final y2 = toY(lineEnd);
  final x0 = toX(point);
  final y0 = toY(point);

  final dx = x2 - x1;
  final dy = y2 - y1;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared == 0) {
    return sqrt((x0 - x1) * (x0 - x1) + (y0 - y1) * (y0 - y1));
  }

  final numerator = (dy * x0 - dx * y0 + x2 * y1 - y2 * x1).abs();
  return numerator / sqrt(lengthSquared);
}
