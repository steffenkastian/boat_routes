import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../controllers/live_location_controller.dart';
import '../models/boat_route.dart';
import '../services/location_service.dart';
import '../services/route_storage_service.dart';
import '../utils/geo_utils.dart';
import '../utils/marker_icon_factory.dart';
import '../widgets/hud_overlay.dart';
import '../widgets/prompt_name_dialog.dart';
import '../widgets/route_map_view.dart';
import '../widgets/route_points_panel.dart';
import '../widgets/saved_routes_panel.dart';

class RoutePlannerScreen extends StatefulWidget {
  const RoutePlannerScreen({super.key});

  @override
  State<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends State<RoutePlannerScreen> {
  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(54.382440, 11.145867),
    zoom: 11,
  );

  final _routeStorage = RouteStorageService();
  final _location = LiveLocationController(LocationService());

  final List<LatLng> _points = [];
  GoogleMapController? _mapController;
  List<BoatRoute> _savedRoutes = [];
  bool _addingEnabled = true;
  bool _hasAutoCenteredOnLocation = false;
  bool _hudTapGuard = false;

  final Map<String, BitmapDescriptor> _courseLabelIcons = {};

  @override
  void initState() {
    super.initState();
    _loadRoutes();
    _location.addListener(_onLocationChanged);
    _location.start();
  }

  @override
  void dispose() {
    _location.removeListener(_onLocationChanged);
    _location.dispose();
    super.dispose();
  }

  void _onLocationChanged() {
    if (!_hasAutoCenteredOnLocation && _location.currentPosition != null) {
      _centerOnPosition(_location.currentPosition!.latitude,
          _location.currentPosition!.longitude,
          animate: false);
    }
    setState(() {});
  }

  void _centerOnPosition(double lat, double lng, {bool animate = true}) {
    final controller = _mapController;
    if (controller == null) return;

    _hasAutoCenteredOnLocation = true;
    final target = CameraPosition(target: LatLng(lat, lng), zoom: 15);
    if (animate) {
      controller.animateCamera(CameraUpdate.newCameraPosition(target));
    } else {
      controller.moveCamera(CameraUpdate.newCameraPosition(target));
    }
  }

  void _jumpToCurrentLocation() {
    // On Flutter web the GoogleMap platform view can receive a tap directly
    // (it isn't routed through Flutter's own widget hit-testing), so a tap
    // meant for the HUD button can also reach the map underneath and add a
    // route point. Guard the next map tap for a brief window rather than
    // trying to geometrically detect the overlap, which proved unreliable.
    _hudTapGuard = true;
    Future.delayed(const Duration(milliseconds: 400), () {
      _hudTapGuard = false;
    });

    final position = _location.currentPosition;
    if (position == null) {
      // No fix yet (or permission was never granted) — retry from here,
      // inside a real user gesture, so the browser reliably shows its
      // location permission prompt.
      _location.start();
      return;
    }
    _centerOnPosition(position.latitude, position.longitude);
  }

  void _addPoint(LatLng position) {
    if (_hudTapGuard) return;
    setState(() {
      _points.add(position);
    });
    _ensureCourseLabelIcons();
  }

  void _removePoint(int index) {
    setState(() {
      _points.removeAt(index);
    });
    _ensureCourseLabelIcons();
  }

  // Route segment course labels ("123°") are drawn as map markers, which on
  // google_maps_flutter requires baking each distinct label into a bitmap
  // ahead of time. Generated lazily and cached by text so repeated courses
  // (e.g. a beat back and forth) reuse the same icon.
  Future<void> _ensureCourseLabelIcons() async {
    final needed = <String>{
      for (var i = 1; i < _points.length; i++)
        '${bearing(_points[i - 1], _points[i]).round()}°',
    };
    final missing = needed.difference(_courseLabelIcons.keys.toSet());
    if (missing.isEmpty) return;

    for (final text in missing) {
      _courseLabelIcons[text] = await buildLabelIcon(text);
    }
    if (mounted) setState(() {});
  }

  Set<Marker> _buildCourseLabelMarkers() {
    final markers = <Marker>{};
    for (var i = 1; i < _points.length; i++) {
      final from = _points[i - 1];
      final to = _points[i];
      final text = '${bearing(from, to).round()}°';
      final icon = _courseLabelIcons[text];
      if (icon == null) continue;

      markers.add(Marker(
        markerId: MarkerId('course_$i'),
        position: LatLng(
          (from.latitude + to.latitude) / 2,
          (from.longitude + to.longitude) / 2,
        ),
        icon: icon,
        anchor: const Offset(0.5, 0.5),
        consumeTapEvents: true,
      ));
    }
    return markers;
  }

  Future<void> _loadRoutes() async {
    final routes = await _routeStorage.loadRoutes();
    setState(() {
      _savedRoutes = routes;
    });
  }

  void _loadRoute(BoatRoute route) {
    setState(() {
      _points
        ..clear()
        ..addAll(route.points);
    });
    _ensureCourseLabelIcons();
  }

  Future<void> _deleteRoute(int index) async {
    await _routeStorage.deleteRouteAt(index);
    setState(() {
      _savedRoutes.removeAt(index);
    });
  }

  Future<void> _saveRoute() async {
    if (_points.isEmpty) return;

    setState(() => _addingEnabled = false);
    final name = await promptForName(
      context,
      title: 'Routenname eingeben',
      hint: 'z.B. Ostseetörn',
    );
    setState(() => _addingEnabled = true);

    if (name == null) return;

    final newRoute = BoatRoute(name: name, points: List.of(_points));
    await _routeStorage.addRoute(newRoute);
    setState(() {
      _savedRoutes.add(newRoute);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Routenplaner mit Standort'),
        actions: [
          IconButton(
            tooltip: 'Neue Route',
            icon: const Icon(Icons.add),
            onPressed: () {
              setState(() {
                _points.clear();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveRoute,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Stack(
                    children: [
                      RouteMapView(
                        initialCamera: _initialCamera,
                        points: _points,
                        addingEnabled: _addingEnabled,
                        onTap: _addPoint,
                        onMapCreated: (controller) {
                          _mapController = controller;
                          final position = _location.currentPosition;
                          if (position != null && !_hasAutoCenteredOnLocation) {
                            _centerOnPosition(
                              position.latitude,
                              position.longitude,
                              animate: false,
                            );
                          }
                        },
                        extraMarkers: {
                          ..._buildCourseLabelMarkers(),
                          if (_location.boatMarker case final marker?) marker,
                        },
                      ),
                      HudOverlay(
                        speedKnots: _location.speedKnots,
                        headingDegrees: _location.displayedHeading,
                        statusMessage: _location.statusMessage,
                        onTap: _jumpToCurrentLocation,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: RoutePointsPanel(
                    points: _points,
                    onRemovePoint: _removePoint,
                    onAddPoint: _addPoint,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: SavedRoutesPanel(
              routes: _savedRoutes,
              onLoad: _loadRoute,
              onDelete: _deleteRoute,
            ),
          ),
        ],
      ),
    );
  }
}
