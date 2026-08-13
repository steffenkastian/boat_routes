import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../controllers/route_annotations_controller.dart';
import 'map_layers_menu.dart';
import 'route_map_view.dart';

// Read-only map of one or several combined tracks/routes — used both for a
// folder's "show everything at once" view (one leg per entry) and for
// viewing a single leg (a list with one entry). Each leg gets its own
// polyline + annotations, so unrelated legs aren't visually joined by a
// straight line between the last point of one and the first point of the
// next.
class CombinedRouteMapScreen extends StatefulWidget {
  const CombinedRouteMapScreen({
    required this.title,
    required this.legs,
    super.key,
  });

  final String title;
  final List<List<LatLng>> legs;

  @override
  State<CombinedRouteMapScreen> createState() =>
      _CombinedRouteMapScreenState();
}

class _CombinedRouteMapScreenState extends State<CombinedRouteMapScreen> {
  final _annotations = RouteAnnotationsController();
  bool _showSeaMarks = true;
  bool _showDepth = false;
  bool _showCourseAndDistance = true;
  bool _showArrows = true;

  List<LatLng> get _allPoints => widget.legs.expand((leg) => leg).toList();

  @override
  void initState() {
    super.initState();
    _annotations.addListener(_onChanged);
    for (final leg in widget.legs) {
      _annotations.ensureIconsFor(leg);
    }
  }

  @override
  void dispose() {
    _annotations.removeListener(_onChanged);
    _annotations.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  Set<Marker> _buildAnnotationMarkers() {
    final markers = <Marker>{};
    for (var i = 0; i < widget.legs.length; i++) {
      markers.addAll(_annotations.buildMarkers(
        widget.legs[i],
        idPrefix: 'combined_$i',
        showCourseLabels: _showCourseAndDistance,
        showArrows: _showArrows,
      ));
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final allPoints = _allPoints;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Kartenebenen',
            icon: const Icon(Icons.layers),
            onPressed: () => showMapLayersMenu(
              context,
              showSeaMarks: _showSeaMarks,
              onSeaMarksChanged: (value) => setState(() => _showSeaMarks = value),
              showDepth: _showDepth,
              onDepthChanged: (value) => setState(() => _showDepth = value),
              showCourseAndDistance: _showCourseAndDistance,
              onCourseAndDistanceChanged: (value) =>
                  setState(() => _showCourseAndDistance = value),
              showArrows: _showArrows,
              onArrowsChanged: (value) => setState(() => _showArrows = value),
            ),
          ),
        ],
      ),
      body: RouteMapView(
        initialCamera: CameraPosition(target: allPoints.first, zoom: 11),
        points: allPoints,
        polylineSegments: widget.legs,
        showPointMarkers: false,
        showSeaMarks: _showSeaMarks,
        showDepth: _showDepth,
        onTap: (_) {},
        onMapCreated: (_) {},
        extraMarkers: _buildAnnotationMarkers(),
      ),
    );
  }
}
