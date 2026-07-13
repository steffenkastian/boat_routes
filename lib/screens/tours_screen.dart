import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../controllers/live_location_controller.dart';
import '../models/tour.dart';
import '../services/location_service.dart';
import '../services/tour_storage_service.dart';
import '../utils/geo_utils.dart';
import '../widgets/hud_overlay.dart';
import '../widgets/prompt_name_dialog.dart';
import '../widgets/route_map_view.dart';

class ToursScreen extends StatefulWidget {
  const ToursScreen({super.key});

  @override
  State<ToursScreen> createState() => _ToursScreenState();
}

class _ToursScreenState extends State<ToursScreen> {
  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(54.382440, 11.145867),
    zoom: 11,
  );

  final _tourStorage = TourStorageService();
  final _location = LiveLocationController(LocationService());

  GoogleMapController? _mapController;
  List<Tour> _savedTours = [];
  bool _isTracking = false;
  DateTime? _startedAt;

  @override
  void initState() {
    super.initState();
    _loadTours();
    _location.addListener(_onLocationChanged);
  }

  @override
  void dispose() {
    _location.removeListener(_onLocationChanged);
    _location.dispose();
    super.dispose();
  }

  void _onLocationChanged() => setState(() {});

  Future<void> _loadTours() async {
    final tours = await _tourStorage.loadTours();
    setState(() => _savedTours = tours);
  }

  Future<void> _startTour() async {
    setState(() {
      _isTracking = true;
      _startedAt = DateTime.now();
    });
    _location.startRecording();
    await _location.start();
  }

  Future<void> _endTour() async {
    final points = _location.stopRecording();
    final startedAt = _startedAt;
    setState(() => _isTracking = false);
    if (points.isEmpty || startedAt == null) return;

    final name = await promptForName(
      context,
      title: 'Törnname eingeben',
      hint: 'z.B. Wochenendtörn',
    );
    if (name == null) return;

    final tour = Tour(
      name: name,
      points: points,
      startedAt: startedAt,
      endedAt: DateTime.now(),
    );
    await _tourStorage.addTour(tour);
    setState(() => _savedTours.add(tour));
  }

  String _tourSubtitle(Tour tour) {
    final date = tour.startedAt;
    final dateText =
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    final distance = totalDistanceNm(tour.points);
    return '$dateText  •  ${distance.toStringAsFixed(2)} sm';
  }

  @override
  Widget build(BuildContext context) {
    if (_isTracking) {
      return Scaffold(
        appBar: AppBar(title: const Text('Törn läuft')),
        body: Stack(
          children: [
            RouteMapView(
              initialCamera: _initialCamera,
              points: _location.track,
              addingEnabled: false,
              showPointMarkers: false,
              onTap: (_) {},
              onMapCreated: (controller) => _mapController = controller,
              extraMarkers: {
                if (_location.boatMarker case final marker?) marker,
              },
            ),
            HudOverlay(
              speedKnots: _location.speedKnots,
              headingDegrees: _location.displayedHeading,
              statusMessage: _location.statusMessage,
              onTap: () {
                final position = _location.currentPosition;
                if (position == null) return;
                _mapController?.animateCamera(
                  CameraUpdate.newLatLngZoom(
                    LatLng(position.latitude, position.longitude),
                    15,
                  ),
                );
              },
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: ElevatedButton(
                onPressed: _endTour,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Törn beenden'),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Törns ansehen')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _startTour,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Törn starten'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _savedTours.isEmpty
                  ? const Center(child: Text('Noch keine Törns gespeichert'))
                  : ListView.builder(
                      itemCount: _savedTours.length,
                      itemBuilder: (context, index) {
                        final tour = _savedTours[index];
                        return ListTile(
                          leading: const Icon(Icons.directions_boat),
                          title: Text(tour.name),
                          subtitle: Text(_tourSubtitle(tour)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
