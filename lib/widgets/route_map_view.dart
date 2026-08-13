import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../utils/openseamap_tile_provider.dart';

class RouteMapView extends StatelessWidget {
  const RouteMapView({
    required this.initialCamera,
    required this.points,
    required this.onTap,
    required this.onMapCreated,
    this.extraMarkers = const {},
    this.showPointMarkers = true,
    this.showSeaMarks = false,
    this.showDepth = false,
    this.pointIcons = const {},
    this.referenceRoute,
    this.polylineSegments,
    super.key,
  });

  final CameraPosition initialCamera;
  final List<LatLng> points;
  // Always fires on a map tap — callers that only sometimes want to act on
  // it (e.g. Route planen only adding a point while editing is enabled)
  // decide that themselves rather than this widget gating it.
  final ValueChanged<LatLng> onTap;
  final ValueChanged<GoogleMapController> onMapCreated;
  final Set<Marker> extraMarkers;
  final bool showPointMarkers;
  final bool showSeaMarks;
  final bool showDepth;
  // Keyed by 1-based point number, falls back to the default red pin while
  // the numbered icon hasn't finished generating yet.
  final Map<int, BitmapDescriptor> pointIcons;
  // An optional planned/regatta course drawn distinctly from `points`
  // (which represents the tapped waypoints or the live GPS track).
  final List<LatLng>? referenceRoute;
  // When set, draws one polyline per segment instead of a single continuous
  // one through all of `points` — used by CombinedRouteMapScreen so
  // unrelated legs aren't visually joined by a straight line between the
  // last point of one and the first point of the next.
  final List<List<LatLng>>? polylineSegments;

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{};
    if (showPointMarkers) {
      markers.addAll(points.asMap().entries.map((entry) {
        final idx = entry.key;
        final pos = entry.value;
        final icon = pointIcons[idx + 1];
        return Marker(
          markerId: MarkerId('point_$idx'),
          position: pos,
          infoWindow: InfoWindow(title: 'Punkt ${idx + 1}'),
          icon: icon ?? BitmapDescriptor.defaultMarker,
          anchor: icon != null ? const Offset(0.5, 0.5) : const Offset(0.5, 1.0),
          // Without this, a tap on the marker (or on the map to close its
          // info window) can also reach the map's own onTap underneath and
          // add a new point right on top of the one just tapped.
          consumeTapEvents: true,
        );
      }));
    }

    markers.addAll(extraMarkers);

    final polylines = <Polyline>{};
    final segments = polylineSegments;
    if (segments != null) {
      for (var i = 0; i < segments.length; i++) {
        polylines.add(Polyline(
          polylineId: PolylineId('route_$i'),
          color: Colors.blue,
          width: 4,
          points: segments[i],
        ));
      }
    } else {
      polylines.add(Polyline(
        polylineId: const PolylineId('route'),
        color: Colors.blue,
        width: 4,
        points: points,
      ));
    }
    final reference = referenceRoute;
    if (reference != null && reference.isNotEmpty) {
      polylines.add(Polyline(
        polylineId: const PolylineId('reference_route'),
        color: Colors.orange,
        width: 4,
        patterns: [PatternItem.dash(20), PatternItem.gap(10)],
        points: reference,
      ));
    }

    return GoogleMap(
      initialCameraPosition: initialCamera,
      onMapCreated: onMapCreated,
      onTap: onTap,
      markers: markers,
      polylines: polylines,
      tileOverlays: {
        if (showDepth) depthOverlay,
        if (showSeaMarks) openSeaMapOverlay,
      },
      zoomControlsEnabled: true,
      compassEnabled: true,
    );
  }
}
