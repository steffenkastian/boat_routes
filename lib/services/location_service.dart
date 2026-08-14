import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

// kIsWeb/defaultTargetPlatform (not dart:io's Platform, which fails to
// compile at all for the web target) — the standard cross-platform-safe way
// to branch on platform in code shared between the web and Android builds.
bool get isAndroidPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

enum LocationAccessStatus {
  granted,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
}

class LocationService {
  Future<LocationAccessStatus> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccessStatus.serviceDisabled;
    }

    LocationPermission permission;
    try {
      permission = await Geolocator.checkPermission();
    } catch (_) {
      // Some mobile browsers don't reliably support the Permissions API
      // query for geolocation and throw here instead of returning a status.
      // Treat that the same as "unknown" and fall through to requesting
      // directly, which triggers the browser's native prompt via
      // getCurrentPosition instead of relying on the Permissions API.
      permission = LocationPermission.denied;
    }

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    switch (permission) {
      case LocationPermission.denied:
        return LocationAccessStatus.permissionDenied;
      case LocationPermission.deniedForever:
        return LocationAccessStatus.permissionDeniedForever;
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        return LocationAccessStatus.granted;
      case LocationPermission.unableToDetermine:
        return LocationAccessStatus.permissionDenied;
    }
  }

  // Android splits "while in use" and "always" (background) location into
  // two separate OS prompts — the second only requestable after the first
  // is granted. Only meaningful (and only called) when starting a Törn on
  // Android; a no-op everywhere else, including web, where there's no such
  // tier and no background execution to grant it for anyway.
  Future<bool> ensureBackgroundPermission() async {
    if (!isAndroidPlatform) return true;
    final status = await ph.Permission.locationAlways.request();
    return status.isGranted;
  }

  // Android 13+ requires this granted at runtime before any notification —
  // including the foreground-service one above and the live distance one in
  // tours_screen.dart — is actually shown; without it the service still
  // runs, it just does so invisibly. No-op (and no such requirement)
  // everywhere else.
  Future<bool> ensureNotificationPermission() async {
    if (!isAndroidPlatform) return true;
    final status = await ph.Permission.notification.request();
    return status.isGranted;
  }

  // [background] switches Android to a real foreground service (exempt from
  // Doze/battery suspension, but only justified — and only shows its
  // persistent notification — while a Törn is actually being recorded).
  // Plain "show my current position" use (Route planen, and the Törns
  // screen before a Törn is started) stays in normal mode: no service, no
  // notification, since nothing needs to survive a screen lock there.
  Stream<Position> positionStream({
    LocationSettings? settings,
    bool background = false,
  }) {
    return Geolocator.getPositionStream(
      locationSettings: settings ?? _defaultSettings(background: background),
    );
  }

  LocationSettings _defaultSettings({bool background = false}) {
    if (isAndroidPlatform && background) {
      // A foregroundNotificationConfig makes geolocator_android run a real
      // foreground service, which is what actually sustains these updates
      // through a screen lock (Android exempts foreground services from
      // Doze/battery suspension) — the same fine-grained distanceFilter
      // keeps working in the background instead of needing a coarser
      // interval-based fallback.
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Törn läuft',
          notificationText: 'Standort wird aufgezeichnet',
          enableWakeLock: true,
        ),
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 3,
    );
  }
}
