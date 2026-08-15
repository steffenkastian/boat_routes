import 'package:geolocator/geolocator.dart' as geo;
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config.dart';
import 'geo_utils.dart';

// Pure, stateful accept/reject filter for raw GPS fixes — extracted out of
// LiveLocationController so BackgroundTrackingService can apply the exact
// same rejection logic from inside its own isolate. Isolates don't share
// object instances, only code, so each side owns its own instance with its
// own independent state; the logic itself has to be identical or the "what
// got recorded" and "what got shown live" tracks would silently diverge.
class GpsFixFilter {
  GpsFixFilter() : _streamStartTime = DateTime.now();

  LatLng? _lastFix;
  DateTime? _lastFixTime;
  double? _lastSpeedMps;
  bool _lastFixWasForced = false;
  final DateTime _streamStartTime;

  // The fix this filter most recently accepted, or null if none yet —
  // exposed so a caller can compute something derived from the *previous*
  // fix (e.g. heading) before calling evaluate() again advances it.
  LatLng? get lastAcceptedFix => _lastFix;

  // Returns the fix's LatLng if accepted, or null if rejected.
  LatLng? evaluate(geo.Position position) {
    final fix = LatLng(position.latitude, position.longitude);
    final lastFix = _lastFix;
    final lastTime = _lastFixTime;
    final elapsedSeconds = lastTime == null
        ? null
        : position.timestamp.difference(lastTime).inMilliseconds / 1000;

    final gapForced = elapsedSeconds != null
        ? elapsedSeconds >= GpsFilterConfig.maxGapSeconds
        : position.timestamp.difference(_streamStartTime).inSeconds >=
            GpsFilterConfig.maxGapSeconds;
    final forceAccept = gapForced || _lastFixWasForced;

    if (!forceAccept &&
        position.accuracy > GpsFilterConfig.maxHorizontalAccuracyMeters) {
      return null;
    }
    if (position.accuracy > GpsFilterConfig.maxHorizontalAccuracyMetersForced) {
      return null;
    }

    double? currentSpeedMps;
    if (lastFix != null && elapsedSeconds != null && elapsedSeconds > 0) {
      currentSpeedMps = distanceMeters(lastFix, fix) / elapsedSeconds;
      if (!forceAccept && currentSpeedMps > GpsFilterConfig.maxPlausibleSpeedMps) {
        return null;
      }
      final lastSpeed = _lastSpeedMps;
      if (!forceAccept &&
          lastSpeed != null &&
          elapsedSeconds >= GpsFilterConfig.minSecondsForAccelerationCheck) {
        final acceleration = (currentSpeedMps - lastSpeed).abs() / elapsedSeconds;
        if (acceleration > GpsFilterConfig.maxPlausibleAccelerationMps2) {
          return null;
        }
      }
    }

    _lastFix = fix;
    _lastFixTime = position.timestamp;
    _lastSpeedMps = forceAccept ? null : (currentSpeedMps ?? _lastSpeedMps);
    _lastFixWasForced = gapForced;
    return fix;
  }
}
