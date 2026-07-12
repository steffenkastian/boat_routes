import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class RouteMapView extends StatelessWidget {
  const RouteMapView({
    required this.initialCamera,
    required this.points,
    required this.addingEnabled,
    required this.onTap,
    required this.onMapCreated,
    this.boatMarker,
    super.key,
  });

  final CameraPosition initialCamera;
  final List<LatLng> points;
  final bool addingEnabled;
  final ValueChanged<LatLng> onTap;
  final ValueChanged<GoogleMapController> onMapCreated;
  final Marker? boatMarker;

  @override
  Widget build(BuildContext context) {
    final markers = points.asMap().entries.map((entry) {
      final idx = entry.key;
      final pos = entry.value;
      return Marker(
        markerId: MarkerId('point_$idx'),
        position: pos,
        infoWindow: InfoWindow(title: 'Punkt ${idx + 1}'),
      );
    }).toSet();

    if (boatMarker != null) {
      markers.add(boatMarker!);
    }

    final polyline = Polyline(
      polylineId: const PolylineId('route'),
      color: Colors.blue,
      width: 4,
      points: points,
    );

    return GoogleMap(
      initialCameraPosition: initialCamera,
      onMapCreated: onMapCreated,
      onTap: (pos) {
        if (addingEnabled) onTap(pos);
      },
      markers: markers,
      polylines: {polyline},
      zoomControlsEnabled: true,
      compassEnabled: true,
    );
  }
}
