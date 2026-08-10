import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
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
    _ensureBoatIcon(0); // pre-warm north, the default heading
  }

  final LocationService _locationService;

  // GPS jitter while stationary would otherwise show a constantly
  // flickering heading, so a fix only updates the course once the boat has
  // moved at least this far.
  static const _minMovementForHeadingMeters = 3.0;

  // A single bad fix (observed occasionally after the screen was locked and
  // the browser suspended/resumed the position stream) can imply an
  // impossible speed — e.g. "500m in 1s". Reject anything faster than a very
  // generous upper bound for a boat instead of recording the jump.
  static const _maxPlausibleSpeedMps = 30.0; // ~58 knots

  StreamSubscription<geo.Position>? _positionSub;
  // google_maps_flutter_web's Marker.rotation is silently ignored for
  // raster icons (only vector Symbol icons rotate on the classic
  // google.maps.Marker it wraps) — the heading has to be baked into the
  // bitmap itself. Cached per 15°-rounded bucket rather than per exact
  // degree, so this stays a handful of icons instead of one per fix.
  final Map<int, BitmapDescriptor> _boatIconsByHeading = {};
  final Set<int> _pendingBoatIconBuckets = {};
  LatLng? _lastFixForHeading;
  DateTime? _lastFixTime;

  Timer? _fixTimeoutTimer;

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

  int _headingBucket(double degrees) {
    final normalized = ((degrees % 360) + 360) % 360;
    return ((normalized / 15).round() * 15) % 360;
  }

  Future<void> _ensureBoatIcon(int bucket) async {
    if (_boatIconsByHeading.containsKey(bucket) ||
        _pendingBoatIconBuckets.contains(bucket)) {
      return;
    }
    _pendingBoatIconBuckets.add(bucket);
    final icon = await buildBoatArrowIcon(rotationDegrees: bucket.toDouble());
    _boatIconsByHeading[bucket] = icon;
    _pendingBoatIconBuckets.remove(bucket);
    notifyListeners();
  }

  Marker? get boatMarker {
    final position = currentPosition;
    if (position == null) return null;

    final bucket = _headingBucket(displayedHeading ?? 0);
    final icon = _boatIconsByHeading[bucket];
    if (icon == null) {
      _ensureBoatIcon(bucket);
      return null;
    }

    return Marker(
      markerId: const MarkerId('boat'),
      position: LatLng(position.latitude, position.longitude),
      icon: icon,
      anchor: const Offset(0.5, 0.5),
      flat: false,
    );
  }

  // Android-only (no-op elsewhere): requests the separate "always" location
  // tier needed to keep receiving fixes while the screen is locked. Call
  // only after start() has already granted foreground access.
  Future<bool> ensureBackgroundPermission() =>
      _locationService.ensureBackgroundPermission();

  // Android-only (no-op elsewhere): requests permission to actually show
  // notifications, needed on Android 13+ for both the foreground-service
  // notification and the separate live-distance one in tours_screen.dart.
  Future<bool> ensureNotificationPermission() =>
      _locationService.ensureNotificationPermission();

  // Called both automatically on startup and from a manual tap on the
  // location button. The manual tap matters on mobile browsers, which
  // often only show the location permission prompt when triggered
  // directly from a user gesture — an automatic call on page load can
  // otherwise hang without ever showing the prompt.
  //
  // Both the permission query and the first fix are wrapped with a
  // timeout/try-catch: some mobile browsers don't support the Permissions
  // API for geolocation at all, which can leave the underlying call hanging
  // indefinitely instead of resolving or throwing — without this, that
  // shows up as "GPS wird gesucht…" forever with no way to tell what went
  // wrong.
  Future<void> start({bool isRetry = false}) async {
    await _positionSub?.cancel();
    _fixTimeoutTimer?.cancel();
    streamError = null;
    notifyListeners();

    final LocationAccessStatus result;
    try {
      result = await _locationService
          .ensurePermission()
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      streamError =
          'Standortabfrage antwortet nicht – Standortberechtigung für diese Seite in den Browser-Einstellungen prüfen.';
      notifyListeners();
      return;
    } on MissingPluginException {
      // The web plugin implementation can occasionally not be registered
      // yet on a cold start — retry once after a short delay instead of
      // surfacing a permanent-looking error immediately.
      if (isRetry) {
        // Temporary diagnostic: reveal which GeolocatorPlatform
        // implementation is actually active, to see whether the web
        // implementation ever got registered at all.
        streamError =
            'Standort-Plugin konnte nicht geladen werden (aktiv: ${geo.GeolocatorPlatform.instance.runtimeType})';
        notifyListeners();
        return;
      }
      await Future.delayed(const Duration(milliseconds: 800));
      return start(isRetry: true);
    } catch (e) {
      // Temporarily surfacing the raw error text (instead of a generic
      // message) to diagnose an unexpected failure on some mobile browsers.
      streamError = 'Standortfehler: $e';
      notifyListeners();
      return;
    }

    status = result;
    notifyListeners();
    if (result != LocationAccessStatus.granted) return;

    _fixTimeoutTimer = Timer(const Duration(seconds: 10), () {
      if (currentPosition == null) {
        streamError =
            'Keine GPS-Daten empfangen – Standortdienste am Gerät prüfen.';
        notifyListeners();
      }
    });

    try {
      _positionSub = _locationService.positionStream().listen(
        (position) {
          _fixTimeoutTimer?.cancel();
          final fix = LatLng(position.latitude, position.longitude);

          final lastFix = _lastFixForHeading;
          final lastTime = _lastFixTime;
          if (lastFix != null && lastTime != null) {
            final elapsedSeconds =
                position.timestamp.difference(lastTime).inMilliseconds / 1000;
            if (elapsedSeconds > 0 &&
                distanceMeters(lastFix, fix) / elapsedSeconds >
                    _maxPlausibleSpeedMps) {
              // Outlier (e.g. a jump right after the screen was locked and
              // the position stream resumed) — drop it and wait for the
              // next fix rather than recording/showing an impossible jump.
              return;
            }
          }

          currentPosition = position;
          streamError = null;
          if (lastFix != null &&
              distanceMeters(lastFix, fix) >= _minMovementForHeadingMeters) {
            displayedHeading = bearing(lastFix, fix);
          }
          _lastFixForHeading = fix;
          _lastFixTime = position.timestamp;
          if (isRecording) track.add(fix);
          notifyListeners();
        },
        onError: (Object error) {
          streamError = 'Standort nicht verfügbar';
          notifyListeners();
        },
      );
    } catch (_) {
      streamError = 'Standort-Stream konnte nicht gestartet werden';
      notifyListeners();
    }
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
    _fixTimeoutTimer?.cancel();
    super.dispose();
  }
}
