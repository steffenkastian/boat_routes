import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../controllers/auth_controller.dart';
import '../controllers/live_location_controller.dart';
import '../controllers/route_annotations_controller.dart';
import '../models/regatta.dart';
import '../models/tour.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/regatta_storage_service.dart';
import '../services/tour_storage_service.dart';
import '../services/user_library_service.dart';
import '../utils/geo_utils.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/hud_overlay.dart';
import '../widgets/map_layers_menu.dart';
import '../widgets/prompt_name_dialog.dart';
import '../widgets/route_map_view.dart';
import '../widgets/save_options_dialog.dart';
import 'tour_detail_screen.dart';

class ToursScreen extends StatefulWidget {
  const ToursScreen({this.referenceRoute, this.referenceRouteLabel, super.key});

  // Points to show as a reference course while tracking — either a loaded
  // regatta or the currently drawn route from "Route planen".
  final List<LatLng>? referenceRoute;
  final String? referenceRouteLabel;

  @override
  State<ToursScreen> createState() => _ToursScreenState();
}

class _ToursScreenState extends State<ToursScreen> {
  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(54.382440, 11.145867),
    zoom: 11,
  );

  final _tourStorage = TourStorageService();
  final _regattaStorage = RegattaStorageService();
  final _userLibrary = UserLibraryService();
  final _location = LiveLocationController(LocationService());
  final _auth = AuthController(AuthService());
  final _referenceAnnotations = RouteAnnotationsController();

  GoogleMapController? _mapController;
  List<Tour> _savedTours = [];
  bool _isTracking = false;
  DateTime? _startedAt;
  bool _showSeaMarks = false;
  bool _showDepth = false;
  String? _syncedForUid;

  @override
  void initState() {
    super.initState();
    _loadTours();
    _location.addListener(_onLocationChanged);
    _auth.addListener(_onAuthChanged);
    _referenceAnnotations.addListener(_onAnnotationsChanged);
    _referenceAnnotations.ensureIconsFor(widget.referenceRoute ?? const []);
  }

  @override
  void didUpdateWidget(covariant ToursScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.referenceRoute != oldWidget.referenceRoute) {
      _referenceAnnotations.ensureIconsFor(widget.referenceRoute ?? const []);
    }
  }

  @override
  void dispose() {
    _location.removeListener(_onLocationChanged);
    _location.dispose();
    _auth.removeListener(_onAuthChanged);
    _auth.dispose();
    _referenceAnnotations.removeListener(_onAnnotationsChanged);
    _referenceAnnotations.dispose();
    super.dispose();
  }

  void _onLocationChanged() => setState(() {});
  void _onAnnotationsChanged() => setState(() {});

  void _onAuthChanged() {
    final uid = _auth.currentUser?.uid;
    if (uid != null && uid != _syncedForUid) {
      _syncedForUid = uid;
      _mergeCloudTours(uid);
    } else if (uid == null) {
      _syncedForUid = null;
    }
    setState(() {});
  }

  // Merges in Törns saved to this account from any device — local storage
  // stays authoritative for offline/logged-out use, this just adds what
  // isn't already present (matched by start time, which is unique per Törn).
  Future<void> _mergeCloudTours(String uid) async {
    final cloudTours = await _userLibrary.loadTours(uid);
    if (!mounted) return;
    setState(() {
      for (final tour in cloudTours) {
        final alreadyPresent =
            _savedTours.any((t) => t.startedAt == tour.startedAt);
        if (!alreadyPresent) _savedTours.add(tour);
      }
    });
  }

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

    final options = await promptForSaveOptions(
      context,
      title: 'Törnname eingeben',
      hint: 'z.B. Wochenendtörn',
      canPublishAsRegatta: _auth.isAdmin,
    );
    if (options == null) return;

    final tour = Tour(
      name: options.name,
      points: points,
      startedAt: startedAt,
      endedAt: DateTime.now(),
    );
    await _tourStorage.addTour(tour);
    setState(() => _savedTours.add(tour));

    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      await _userLibrary.addTour(uid, tour);
    }

    if (options.publishAsRegatta) {
      await _regattaStorage.addRegatta(Regatta(
        name: options.name,
        plz: options.plz!,
        points: points,
        createdAt: DateTime.now(),
      ));
    }
  }

  Future<void> _deleteTour(int index) async {
    final tour = _savedTours[index];
    final confirmed = await confirmDialog(
      context,
      title: 'Törn löschen?',
      message: '"${tour.name}" wirklich löschen?',
    );
    if (!confirmed) return;

    await _tourStorage.deleteTourAt(index);
    setState(() => _savedTours.removeAt(index));
  }

  Future<void> _renameTour(int index) async {
    final tour = _savedTours[index];
    final newName = await promptForName(
      context,
      title: 'Törn umbenennen',
      hint: tour.name,
    );
    if (newName == null) return;

    await _tourStorage.renameTourAt(index, newName);
    setState(() {
      _savedTours[index] = Tour(
        name: newName,
        points: tour.points,
        startedAt: tour.startedAt,
        endedAt: tour.endedAt,
      );
    });
  }

  void _viewTour(Tour tour) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => TourDetailScreen(tour: tour)),
    );
  }

  String _tourSubtitle(Tour tour) {
    final date = tour.startedAt;
    final dateText =
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    final distance = totalDistanceNm(tour.points);
    final duration = tour.endedAt.difference(tour.startedAt);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final durationText = hours > 0 ? '${hours}h ${minutes}min' : '${minutes}min';
    return '$dateText  •  ${distance.toStringAsFixed(2)} sm  •  $durationText';
  }

  @override
  Widget build(BuildContext context) {
    if (_isTracking) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Törn läuft'),
          actions: [
            IconButton(
              tooltip: 'Kartenebenen',
              icon: const Icon(Icons.layers),
              onPressed: () => showMapLayersMenu(
                context,
                showSeaMarks: _showSeaMarks,
                onSeaMarksChanged: (value) =>
                    setState(() => _showSeaMarks = value),
                showDepth: _showDepth,
                onDepthChanged: (value) => setState(() => _showDepth = value),
              ),
            ),
          ],
        ),
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
                ..._referenceAnnotations.buildMarkers(
                  widget.referenceRoute ?? const [],
                  idPrefix: 'reference',
                ),
              },
              referenceRoute: widget.referenceRoute,
              showSeaMarks: _showSeaMarks,
              showDepth: _showDepth,
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
            if (widget.referenceRoute != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.flag),
                  title: Text(
                    widget.referenceRouteLabel != null
                        ? 'Geladen: ${widget.referenceRouteLabel}'
                        : 'Route geladen',
                  ),
                ),
              ),
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
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Route ansehen',
                                icon: const Icon(Icons.map),
                                onPressed: () => _viewTour(tour),
                              ),
                              IconButton(
                                tooltip: 'Umbenennen',
                                icon: const Icon(Icons.edit),
                                onPressed: () => _renameTour(index),
                              ),
                              IconButton(
                                tooltip: 'Löschen',
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteTour(index),
                              ),
                            ],
                          ),
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
