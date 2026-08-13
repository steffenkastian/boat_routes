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
import '../widgets/confirm_dialog.dart';
import '../widgets/map_layers_menu.dart';
import '../widgets/route_map_view.dart';

// Read-only view of a previously recorded Törn: the track with the same
// direction-arrow/course/distance/Start-Finish annotations used for a
// regatta reference route, so a past Törn reads the same way. Also lets an
// already-saved Törn (recorded before track simplification existed, or
// just to test it against a real track) be simplified after the fact and
// overwritten in place.
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

  Future<void> _simplifyTrack() async {
    final simplified = simplifyTrack(
      _tour.points,
      toleranceMeters: TrackSimplificationConfig.toleranceMeters,
    );
    if (simplified.length == _tour.points.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Strecke ist bereits vereinfacht — keine Punkte entfernbar.'),
        ),
      );
      return;
    }

    final beforeCount = _tour.points.length;
    final afterCount = simplified.length;
    final beforeNm = totalDistanceNm(_tour.points);
    final afterNm = totalDistanceNm(simplified);
    final reductionPercent = (100 - (afterCount / beforeCount * 100)).round();

    final confirmed = await confirmDialog(
      context,
      title: 'Strecke vereinfachen?',
      message: '$beforeCount → $afterCount Punkte (-$reductionPercent %)\n'
          '${beforeNm.toStringAsFixed(2)} sm → ${afterNm.toStringAsFixed(2)} sm\n\n'
          'Ersetzt die gespeicherte Strecke dieses Törns.',
      confirmLabel: 'Vereinfachen',
    );
    if (!confirmed || !mounted) return;

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
    setState(() {
      _tour = updated;
      _annotations.ensureIconsFor(updated.points);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Strecke vereinfacht: $beforeCount → $afterCount Punkte.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final points = _tour.points;
    final initialCamera = CameraPosition(
      target: points.isNotEmpty ? points.first : const LatLng(54.382440, 11.145867),
      zoom: 12,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_tour.name),
        actions: [
          IconButton(
            tooltip: 'Strecke vereinfachen (${points.length} Punkte)',
            icon: const Icon(Icons.auto_fix_high),
            onPressed: _simplifyTrack,
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
          showArrows: _showArrows,
        ),
      ),
    );
  }
}
