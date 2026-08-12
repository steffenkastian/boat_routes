import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../utils/geo_utils.dart';
import '../utils/marker_icon_factory.dart';

// Builds the map annotations for a reference course (a loaded regatta or the
// route just planned): a direction arrow + course/distance label on every
// segment, plus Start/Finish markers at the endpoints. Icons are baked into
// bitmaps once and cached — only `buildMarkers` needs to run per rebuild.
class RouteAnnotationsController extends ChangeNotifier {
  RouteAnnotationsController() {
    _init();
  }

  final Map<String, BitmapDescriptor> _courseLabelIcons = {};
  // google_maps_flutter_web's Marker.rotation is silently ignored for
  // raster icons (only vector Symbol icons rotate on the classic
  // google.maps.Marker it wraps), so each direction arrow's heading has to
  // be baked into its own bitmap — cached per 15°-rounded bucket rather
  // than per exact bearing.
  final Map<int, BitmapDescriptor> _arrowIconsByHeading = {};
  BitmapDescriptor? _startIcon;
  BitmapDescriptor? _finishIcon;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _init() async {
    final results = await Future.wait([
      buildLabelIcon('Start', background: const Color(0xCC2E7D32)),
      buildLabelIcon('Finish', background: const Color(0xCCC62828)),
    ]);
    // The icon-baking above can still be in flight when a screen holding
    // this controller is popped quickly (e.g. opening then immediately
    // leaving a tour's detail view) — notifying after dispose() throws.
    if (_disposed) return;
    _startIcon = results[0];
    _finishIcon = results[1];
    notifyListeners();
  }

  int _headingBucket(double degrees) {
    final normalized = ((degrees % 360) + 360) % 360;
    return ((normalized / 15).round() * 15) % 360;
  }

  String _courseLabelKey(LatLng from, LatLng to) =>
      '${bearing(from, to).round()}°|${distanceNm(from, to).toStringAsFixed(1)} sm';

  Future<void> ensureIconsFor(List<LatLng> points) async {
    final neededLabels = <String>{};
    final neededHeadings = <int>{};
    for (var i = 1; i < points.length; i++) {
      neededLabels.add(_courseLabelKey(points[i - 1], points[i]));
      neededHeadings.add(_headingBucket(bearing(points[i - 1], points[i])));
    }

    final missingLabels = neededLabels.difference(_courseLabelIcons.keys.toSet());
    final missingHeadings =
        neededHeadings.difference(_arrowIconsByHeading.keys.toSet());
    if (missingLabels.isEmpty && missingHeadings.isEmpty) return;

    for (final key in missingLabels) {
      final parts = key.split('|');
      _courseLabelIcons[key] =
          await buildLabelIcon(parts[0], secondaryText: parts[1]);
    }
    for (final heading in missingHeadings) {
      _arrowIconsByHeading[heading] = await buildBoatArrowIcon(
        size: 22,
        color: Colors.deepOrange,
        rotationDegrees: heading.toDouble(),
      );
    }
    if (_disposed) return;
    notifyListeners();
  }

  LatLng _lerp(LatLng from, LatLng to, double t) => LatLng(
        from.latitude + (to.latitude - from.latitude) * t,
        from.longitude + (to.longitude - from.longitude) * t,
      );

  Set<Marker> buildMarkers(
    List<LatLng> points, {
    required String idPrefix,
    bool showCourseLabels = true,
    bool showArrows = true,
  }) {
    final markers = <Marker>{};
    for (var i = 1; i < points.length; i++) {
      final from = points[i - 1];
      final to = points[i];

      final arrowIcon = _arrowIconsByHeading[_headingBucket(bearing(from, to))];
      if (showArrows && arrowIcon != null) {
        markers.add(Marker(
          markerId: MarkerId('${idPrefix}_arrow_$i'),
          position: _lerp(from, to, 0.5),
          icon: arrowIcon,
          anchor: const Offset(0.5, 0.5),
          consumeTapEvents: true,
        ));
      }

      if (showCourseLabels) {
        final labelIcon = _courseLabelIcons[_courseLabelKey(from, to)];
        if (labelIcon != null) {
          markers.add(Marker(
            markerId: MarkerId('${idPrefix}_course_$i'),
            position: _lerp(from, to, 0.75),
            icon: labelIcon,
            anchor: const Offset(0.5, 0.5),
            consumeTapEvents: true,
          ));
        }
      }
    }

    if (points.isNotEmpty) {
      final startIcon = _startIcon;
      if (startIcon != null) {
        markers.add(Marker(
          markerId: MarkerId('${idPrefix}_start'),
          position: points.first,
          icon: startIcon,
          anchor: const Offset(0.5, 0.5),
          consumeTapEvents: true,
        ));
      }
      final finishIcon = _finishIcon;
      if (points.length > 1 && finishIcon != null) {
        markers.add(Marker(
          markerId: MarkerId('${idPrefix}_finish'),
          position: points.last,
          icon: finishIcon,
          anchor: const Offset(0.5, 0.5),
          consumeTapEvents: true,
        ));
      }
    }

    return markers;
  }
}
