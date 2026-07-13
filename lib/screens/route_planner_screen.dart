import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/boat_route.dart';
import '../services/location_service.dart';
import '../services/route_storage_service.dart';
import '../utils/geo_utils.dart';
import '../utils/marker_icon_factory.dart';
import '../widgets/hud_overlay.dart';
import '../widgets/route_map_view.dart';
import '../widgets/route_points_panel.dart';
import '../widgets/save_route_dialog.dart';
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
  final _locationService = LocationService();

  final List<LatLng> _points = [];
  GoogleMapController? _mapController;
  List<BoatRoute> _savedRoutes = [];
  bool _addingEnabled = true;

  StreamSubscription<geo.Position>? _positionSub;
  geo.Position? _currentPosition;
  LatLng? _lastFixForHeading;
  double? _displayedHeading;
  BitmapDescriptor? _boatIcon;
  LocationAccessStatus? _locationStatus;
  String? _positionStreamError;
  bool _hasAutoCenteredOnLocation = false;

  // Minimum movement between fixes before we trust a newly computed course
  // over ground — GPS jitter while stationary would otherwise show a
  // constantly flickering heading.
  static const _minMovementForHeadingMeters = 3.0;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
    _initLocation();
    buildBoatArrowIcon().then((icon) {
      if (mounted) setState(() => _boatIcon = icon);
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  // Called both automatically on startup and from a manual tap on the
  // location button. The manual tap matters on mobile browsers, which
  // often only show the location permission prompt when triggered
  // directly from a user gesture — an automatic call on page load can
  // otherwise hang without ever showing the prompt.
  Future<void> _initLocation() async {
    await _positionSub?.cancel();
    setState(() => _positionStreamError = null);

    final status = await _locationService.ensurePermission();
    if (!mounted) return;
    setState(() => _locationStatus = status);
    if (status != LocationAccessStatus.granted) return;

    _positionSub = _locationService.positionStream().listen(
      (position) {
        final fix = LatLng(position.latitude, position.longitude);
        setState(() {
          _currentPosition = position;
          _positionStreamError = null;
          final lastFix = _lastFixForHeading;
          if (lastFix != null &&
              distanceMeters(lastFix, fix) >= _minMovementForHeadingMeters) {
            _displayedHeading = bearing(lastFix, fix);
          }
          _lastFixForHeading = fix;
        });
        if (!_hasAutoCenteredOnLocation) {
          _centerOnPosition(position, animate: false);
        }
      },
      onError: (Object error) {
        setState(() => _positionStreamError = 'Standort nicht verfügbar');
      },
    );
  }

  void _centerOnPosition(geo.Position position, {bool animate = true}) {
    final controller = _mapController;
    if (controller == null) return;

    _hasAutoCenteredOnLocation = true;
    final target = CameraPosition(
      target: LatLng(position.latitude, position.longitude),
      zoom: 15,
    );
    if (animate) {
      controller.animateCamera(CameraUpdate.newCameraPosition(target));
    } else {
      controller.moveCamera(CameraUpdate.newCameraPosition(target));
    }
  }

  void _jumpToCurrentLocation() {
    final position = _currentPosition;
    if (position == null) {
      // No fix yet (or permission was never granted) — retry from here,
      // inside a real user gesture, so the browser reliably shows its
      // location permission prompt.
      _initLocation();
      return;
    }
    _centerOnPosition(position);
  }

  void _addPoint(LatLng position) {
    setState(() {
      _points.add(position);
    });
  }

  void _removePoint(int index) {
    setState(() {
      _points.removeAt(index);
    });
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
    final name = await promptForRouteName(context);
    setState(() => _addingEnabled = true);

    if (name == null) return;

    final newRoute = BoatRoute(name: name, points: List.of(_points));
    await _routeStorage.addRoute(newRoute);
    setState(() {
      _savedRoutes.add(newRoute);
    });
  }

  String? _locationStatusMessage() {
    if (_currentPosition == null && _positionStreamError != null) {
      return _positionStreamError;
    }
    switch (_locationStatus) {
      case null:
      case LocationAccessStatus.granted:
        return _currentPosition == null ? 'GPS wird gesucht…' : null;
      case LocationAccessStatus.serviceDisabled:
        return 'Standortdienste sind deaktiviert';
      case LocationAccessStatus.permissionDenied:
      case LocationAccessStatus.permissionDeniedForever:
        return 'Standortzugriff verweigert';
    }
  }

  Marker? _buildBoatMarker() {
    final position = _currentPosition;
    if (position == null || _boatIcon == null) return null;

    return Marker(
      markerId: const MarkerId('boat'),
      position: LatLng(position.latitude, position.longitude),
      icon: _boatIcon!,
      rotation: _displayedHeading ?? 0,
      anchor: const Offset(0.5, 0.5),
      flat: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final speedKnots = _currentPosition != null
        ? metersPerSecondToKnots(_currentPosition!.speed)
        : null;

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
                          final position = _currentPosition;
                          if (position != null && !_hasAutoCenteredOnLocation) {
                            _centerOnPosition(position, animate: false);
                          }
                        },
                        boatMarker: _buildBoatMarker(),
                      ),
                      HudOverlay(
                        speedKnots: speedKnots,
                        headingDegrees: _displayedHeading,
                        statusMessage: _locationStatusMessage(),
                        onJumpToLocation: _jumpToCurrentLocation,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: RoutePointsPanel(
                    points: _points,
                    onRemovePoint: _removePoint,
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
