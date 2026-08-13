import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config.dart';
import '../controllers/auth_controller.dart';
import '../controllers/route_annotations_controller.dart';
import '../models/tour.dart';
import '../services/auth_service.dart';
import '../services/tour_storage_service.dart';
import '../services/user_library_service.dart';
import '../utils/geo_utils.dart';
import '../utils/track_simplifier.dart';
import '../widgets/map_layers_menu.dart';
import '../widgets/route_map_view.dart';

// Read-only view of a previously recorded Törn: the track with the same
// direction-arrow/course/distance/Start-Finish annotations used for a
// regatta reference route, so a past Törn reads the same way. Also lets an
// already-saved Törn (recorded before track simplification existed, or
// just to try it against a real track) be simplified after the fact — as a
// live preview (dashed orange overlay + an adjustable tolerance) rather
// than committing immediately, with an explicit choice to keep the
// simplified version or the original.
class TourDetailScreen extends StatefulWidget {
  const TourDetailScreen({required this.tour, super.key});

  final Tour tour;

  @override
  State<TourDetailScreen> createState() => _TourDetailScreenState();
}

class _TourDetailScreenState extends State<TourDetailScreen> {
  final _annotations = RouteAnnotationsController();
  final _tourStorage = TourStorageService();
  final _userLibrary = UserLibraryService();
  final _auth = AuthController(AuthService());

  late Tour _tour;
  bool _showSeaMarks = true;
  bool _showDepth = false;
  bool _showCourseAndDistance = true;
  bool _showArrows = true;

  // Non-null while previewing a simplification — the original track stays
  // untouched (and displayed) until the user explicitly keeps this.
  double _previewTolerance = TrackSimplificationConfig.toleranceMeters;
  List<LatLng>? _previewPoints;
  bool get _isPreviewing => _previewPoints != null;

  @override
  void initState() {
    super.initState();
    _tour = widget.tour;
    _annotations.addListener(_onAnnotationsChanged);
    _annotations.ensureIconsFor(_tour.points);
  }

  @override
  void dispose() {
    _annotations.removeListener(_onAnnotationsChanged);
    _annotations.dispose();
    _auth.dispose();
    super.dispose();
  }

  void _onAnnotationsChanged() => setState(() {});

  void _startPreview() {
    setState(() {
      _previewTolerance = TrackSimplificationConfig.toleranceMeters;
      _previewPoints =
          simplifyTrack(_tour.points, toleranceMeters: _previewTolerance);
    });
  }

  void _updatePreviewTolerance(double value) {
    setState(() {
      _previewTolerance = value;
      _previewPoints = simplifyTrack(_tour.points, toleranceMeters: value);
    });
  }

  void _discardPreview() {
    setState(() => _previewPoints = null);
  }

  Future<void> _keepSimplified() async {
    final simplified = _previewPoints;
    if (simplified == null) return;

    final updated = Tour(
      id: _tour.id,
      name: _tour.name,
      points: simplified,
      startedAt: _tour.startedAt,
      endedAt: _tour.endedAt,
    );
    await _tourStorage.upsertTour(updated);

    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        await _userLibrary.addTour(uid, updated);
      } catch (_) {}
    }

    if (!mounted) return;
    final beforeCount = _tour.points.length;
    setState(() {
      _tour = updated;
      _previewPoints = null;
      _annotations.ensureIconsFor(updated.points);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('Strecke vereinfacht gespeichert: $beforeCount → ${updated.points.length} Punkte.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final points = _tour.points;
    final previewPoints = _previewPoints;
    final initialCamera = CameraPosition(
      target: points.isNotEmpty ? points.first : const LatLng(54.382440, 11.145867),
      zoom: 12,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_tour.name),
        actions: [
          if (!_isPreviewing)
            IconButton(
              tooltip: 'Strecke vereinfachen (${points.length} Punkte)',
              icon: const Icon(Icons.auto_fix_high),
              onPressed: _startPreview,
            ),
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
      body: Column(
        children: [
          Expanded(
            child: RouteMapView(
              initialCamera: initialCamera,
              points: points,
              // Dashed orange overlay of the simplified candidate, drawn
              // over the original (solid blue) — same visual language as
              // a loaded reference route elsewhere in the app.
              referenceRoute: previewPoints,
              showPointMarkers: false,
              showSeaMarks: _showSeaMarks,
              showDepth: _showDepth,
              onTap: (_) {},
              onMapCreated: (_) {},
              extraMarkers: _annotations.buildMarkers(
                points,
                idPrefix: 'tour',
                showCourseLabels: _showCourseAndDistance,
                showArrows: _showArrows,
              ),
            ),
          ),
          if (_isPreviewing && previewPoints != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${points.length} → ${previewPoints.length} Punkte  •  '
                      '${totalDistanceNm(points).toStringAsFixed(2)} sm → '
                      '${totalDistanceNm(previewPoints).toStringAsFixed(2)} sm',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Row(
                      children: [
                        const Text('Toleranz'),
                        Expanded(
                          child: Slider(
                            min: 1,
                            max: 30,
                            divisions: 29,
                            value: _previewTolerance,
                            label: '${_previewTolerance.round()} m',
                            onChanged: _updatePreviewTolerance,
                          ),
                        ),
                        Text('${_previewTolerance.round()} m'),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _discardPreview,
                            child: const Text('Original behalten'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: _keepSimplified,
                            child: const Text('Vereinfachte Version speichern'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
