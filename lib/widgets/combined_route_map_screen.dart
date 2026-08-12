import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../controllers/route_annotations_controller.dart';
import 'map_layers_menu.dart';
import 'route_map_view.dart';

// Read-only map of a combined track/route — used both for a folder's "show
// everything at once" view and, since it needs nothing folder-specific
// beyond a title and a flat point list, for viewing a single leg too.
class CombinedRouteMapScreen extends StatefulWidget {
  const CombinedRouteMapScreen({
    required this.title,
    required this.points,
    super.key,
  });

  final String title;
  final List<LatLng> points;

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

  @override
  void initState() {
    super.initState();
    _annotations.addListener(_onChanged);
    _annotations.ensureIconsFor(widget.points);
  }

  @override
  void dispose() {
    _annotations.removeListener(_onChanged);
    _annotations.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
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
        initialCamera: CameraPosition(target: points.first, zoom: 11),
        points: points,
        showPointMarkers: false,
        showSeaMarks: _showSeaMarks,
        showDepth: _showDepth,
        onTap: (_) {},
        onMapCreated: (_) {},
        extraMarkers: _annotations.buildMarkers(
          points,
          idPrefix: 'combined',
          showCourseLabels: _showCourseAndDistance,
          showArrows: _showArrows,
        ),
      ),
    );
  }
}
