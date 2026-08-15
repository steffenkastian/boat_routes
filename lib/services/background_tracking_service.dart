import 'dart:async';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/gps_fix_filter.dart';
import 'location_service.dart';

// flutter_background_service has no web implementation at all (unlike
// geolocator/permission_handler, which no-op gracefully) — calling
// configure()/startService() on web throws MissingPluginException. Every
// public method below guards on this first.

// Records a Törn's GPS track from inside a genuinely independent Android
// foreground Service — its own isolate/engine, not tied to the main
// Activity — instead of relying on geolocator_android's
// foregroundNotificationConfig, which its own docs say does *not* run the
// service in the background and does *not* prevent Android from killing the
// activity. See https://pub.dev/packages/flutter_background_service.
//
// Points are written straight to SharedPreferences as they're accepted, not
// relayed live to the UI isolate: that keeps this service's only job simple
// (fetch fix, filter, persist) and makes the recorded track durable even if
// the whole app process is killed mid-Törn, since SharedPreferences is
// OS-level storage readable by either isolate. ToursScreen's own
// LiveLocationController keeps running separately, unchanged, purely for the
// cosmetic live HUD/marker while the app is actually in the foreground — the
// points *saved* for a Törn always come from here, read back in stop().
const _pointsKey = 'active_tour_points';
const _notificationChannelId = 'toern_tracking';
const _notificationId = 4242;

class BackgroundTrackingService {
  static final BackgroundTrackingService _instance =
      BackgroundTrackingService._();
  factory BackgroundTrackingService() => _instance;
  BackgroundTrackingService._();

  final _service = FlutterBackgroundService();

  // Called once from main(), before runApp().
  Future<void> initialize() async {
    if (!isAndroidPlatform) return;
    const channel = AndroidNotificationChannel(
      _notificationChannelId,
      'Törn-Aufzeichnung',
      description:
          'Zeigt an, dass ein Törn im Hintergrund aufgezeichnet wird.',
      importance: Importance.low,
    );
    final notifications = FlutterLocalNotificationsPlugin();
    await notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: _notificationChannelId,
        initialNotificationTitle: 'Törn läuft',
        initialNotificationContent: 'Standort wird aufgezeichnet',
        foregroundServiceNotificationId: _notificationId,
      ),
      iosConfiguration: IosConfiguration(),
    );
  }

  // Clears any points left over from a previous Törn that didn't end
  // cleanly (e.g. the app was killed before _endTour() ran) before starting
  // a new recording.
  Future<void> start() async {
    if (!isAndroidPlatform) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pointsKey);
    await _service.startService();
  }

  // Stops the service and returns everything it persisted — the
  // authoritative recorded track, since the service (not
  // LiveLocationController) is the sole writer of _pointsKey.
  Future<List<LatLng>> stop() async {
    if (!isAndroidPlatform) return [];
    _service.invoke('stop');
    final points = await loadPoints();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pointsKey);
    return points;
  }

  // Safe to call at any time from the UI isolate — e.g. to recover an
  // in-progress Törn's points after the app process was killed and
  // relaunched mid-recording.
  static Future<List<LatLng>> loadPoints() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodePoints(prefs.getStringList(_pointsKey) ?? const []);
  }
}

List<LatLng> _decodePoints(List<String> raw) {
  return raw.map((entry) {
    final parts = entry.split(',');
    return LatLng(double.parse(parts[0]), double.parse(parts[1]));
  }).toList();
}

Future<void> _appendPoint(LatLng fix) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getStringList(_pointsKey) ?? [];
  raw.add('${fix.latitude},${fix.longitude}');
  await prefs.setStringList(_pointsKey, raw);
}

// Top-level function + @pragma('vm:entry-point') are both required — the
// former because isolate entry points can't be class methods/closures, the
// latter because release-mode builds tree-shake this away otherwise (per
// the package's own FAQ: "Service not running in Release Mode").
@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final filter = GpsFixFilter();
  final locationService = LocationService();

  final sub = locationService.positionStream().listen((geo.Position position) {
    final fix = filter.evaluate(position);
    if (fix != null) {
      _appendPoint(fix);
    }
  });

  service.on('stop').listen((event) {
    sub.cancel();
    service.stopSelf();
  });
}
