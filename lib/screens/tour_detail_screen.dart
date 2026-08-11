import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../controllers/route_annotations_controller.dart';
import '../models/tour.dart';
import '../widgets/map_layers_menu.dart';
import '../widgets/route_map_view.dart';

// Read-only view of a previously recorded Törn: the track with the same
// direction-arrow/course/distance/Start-Finish annotations used for a
// regatta reference route, so a past Törn reads the same way.
class TourDetailScreen extends StatefulWidget {
  const TourDetailScreen({required this.tour, super.key});

  final Tour tour;

  @override
  State<TourDetailScreen> createState() => _TourDetailScreenState();
}

class _TourDetailScreenState extends State<TourDetailScreen> {
  final _annotations = RouteAnnotationsController();
  bool _showSeaMarks = true;
  bool _showDepth = false;
  bool _showCourseAndDistance = true;

  @override
  void initState() {
    super.initState();
    _annotations.addListener(_onAnnotationsChanged);
    _annotations.ensureIconsFor(widget.tour.points);
  }

  @override
  void dispose() {
    _annotations.removeListener(_onAnnotationsChanged);
    _annotations.dispose();
    super.dispose();
  }

  void _onAnnotationsChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final points = widget.tour.points;
    final initialCamera = CameraPosition(
      target: points.isNotEmpty ? points.first : const LatLng(54.382440, 11.145867),
      zoom: 12,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tour.name),
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
            ),
          ),
        ],
      ),
      body: RouteMapView(
        initialCamera: initialCamera,
        points: points,
        showPointMarkers: false,
        showSeaMarks: _showSeaMarks,
        showDepth: _showDepth,
        onTap: (_) {},
        onMapCreated: (_) {},
        extraMarkers: _annotations.buildMarkers(
          points,
          idPrefix: 'tour',
          showCourseLabels: _showCourseAndDistance,
        ),
      ),
    );
  }
}
