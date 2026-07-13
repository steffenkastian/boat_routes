import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/location_service.dart';
import '../utils/geo_utils.dart';
import '../utils/marker_icon_factory.dart';

// Owns GPS permission/subscription handling, the computed course-over-ground,
// and the boat arrow marker — shared by any screen that needs to show the
// live position (route planning, tour tracking, and future regatta view).
// Optionally records every fix into `track` for tour logging.
class LiveLocationController extends ChangeNotifier {
  LiveLocationController(this._locationService) {
    buildBoatArrowIcon().then((icon) {
      _boatIcon = icon;
      notifyListeners();
    });
  }

  final LocationService _locationService;

  // GPS jitter while stationary would otherwise show a constantly
  // flickering heading, so a fix only updates the course once the boat has
  // moved at least this far.
  static const _minMovementForHeadingMeters = 3.0;

  StreamSubscription<geo.Position>? _positionSub;
  BitmapDescriptor? _boatIcon;
  LatLng? _lastFixForHeading;

  geo.Position? currentPosition;
  double? displayedHeading;
  LocationAccessStatus? status;
  String? streamError;

  bool isRecording = false;
  final List<LatLng> track = [];

  double? get speedKnots =>
      currentPosition != null ? metersPerSecondToKnots(currentPosition!.speed) : null;

  String? get statusMessage {
    if (currentPosition == null && streamError != null) return streamError;
    switch (status) {
      case null:
      case LocationAccessStatus.granted:
        return currentPosition == null ? 'GPS wird gesucht…' : null;
      case LocationAccessStatus.serviceDisabled:
        return 'Standortdienste sind deaktiviert';
      case LocationAccessStatus.permissionDenied:
      case LocationAccessStatus.permissionDeniedForever:
        return 'Standortzugriff verweigert';
    }
  }

  Marker? get boatMarker {
    final position = currentPosition;
    if (position == null || _boatIcon == null) return null;

    return Marker(
      markerId: const MarkerId('boat'),
      position: LatLng(position.latitude, position.longitude),
      icon: _boatIcon!,
      rotation: displayedHeading ?? 0,
      anchor: const Offset(0.5, 0.5),
      flat: false,
    );
  }

  // Called both automatically on startup and from a manual tap on the
  // location button. The manual tap matters on mobile browsers, which
  // often only show the location permission prompt when triggered
  // directly from a user gesture — an automatic call on page load can
  // otherwise hang without ever showing the prompt.
  Future<void> start() async {
    await _positionSub?.cancel();
    streamError = null;
    notifyListeners();

    final result = await _locationService.ensurePermission();
    status = result;
    notifyListeners();
    if (result != LocationAccessStatus.granted) return;

    _positionSub = _locationService.positionStream().listen(
      (position) {
        final fix = LatLng(position.latitude, position.longitude);
        currentPosition = position;
        streamError = null;
        final lastFix = _lastFixForHeading;
        if (lastFix != null &&
            distanceMeters(lastFix, fix) >= _minMovementForHeadingMeters) {
          displayedHeading = bearing(lastFix, fix);
        }
        _lastFixForHeading = fix;
        if (isRecording) track.add(fix);
        notifyListeners();
      },
      onError: (Object error) {
        streamError = 'Standort nicht verfügbar';
        notifyListeners();
      },
    );
  }

  void startRecording() {
    track.clear();
    isRecording = true;
    final position = currentPosition;
    if (position != null) {
      track.add(LatLng(position.latitude, position.longitude));
    }
    notifyListeners();
  }

  List<LatLng> stopRecording() {
    isRecording = false;
    final result = List<LatLng>.of(track);
    notifyListeners();
    return result;
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }
}
