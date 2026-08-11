class AppConfig {
  static const String googleMapsApiKey = String.fromEnvironment('MAPS_API_KEY');

  // The deployed web app's URL — share links always point here regardless
  // of which platform (web or Android) the share was created from, since
  // a link only makes sense opened in a browser (Uri.base on Android
  // resolves to something app-internal, not a usable web address).
  static const String webBaseUrl = 'https://steffenkastian.github.io/boat_routes/';
}

// Tuning for how strictly LiveLocationController rejects bad GPS fixes
// (e.g. a jump right after the screen unlocks and the position stream
// resumes suspended state). All three checks apply independently — a fix
// only needs to fail one to be dropped. Adjust these directly; there's no
// runtime settings UI for them.
class GpsFilterConfig {
  // A fix whose own reported horizontal accuracy (its uncertainty radius,
  // in meters — every GPS fix carries one) is worse than this is dropped
  // outright, before any comparison to previous fixes. In practice a poor-
  // accuracy fix is very often the actual *source* of an apparent "jump",
  // not real boat movement, so this alone catches a lot of outliers early.
  static const double maxHorizontalAccuracyMeters = 30.0;

  // A fix implying a speed above this (distance from the last accepted fix
  // divided by the time between them), in meters per second, is rejected.
  // 20 m/s ≈ 39 knots — comfortably above even fast/foiling sailing boats
  // (which can briefly exceed 25-30 knots) while still well below the
  // speeds a real GPS jump tends to imply.
  static const double maxPlausibleSpeedMps = 20.0;

  // A fix implying a *change* in speed since the last accepted fix (i.e.
  // acceleration) above this, in meters per second squared, is rejected —
  // catches a fix whose implied speed alone might look plausible, but
  // reaching it that quickly from the previous fix isn't. Set loosely
  // enough to allow a real gust accelerating a boat several knots within a
  // couple of seconds; a genuine GPS jump/teleport implies acceleration
  // far beyond this.
  static const double maxPlausibleAccelerationMps2 = 4.0;

  // Below this many seconds since the last accepted fix, the acceleration
  // check above is skipped entirely rather than applied. Two consecutive
  // fixes close together in time (e.g. a fast boat hitting the 3m
  // distanceFilter every ~0.2s) already carry normal GPS speed-estimate
  // noise of a meter or two per second — dividing that by a very small
  // elapsed time inflates it into an apparent acceleration spike that has
  // nothing to do with the boat's real motion, so the check needs a
  // wider time base to be a meaningful signal.
  static const double minSecondsForAccelerationCheck = 1.0;
}