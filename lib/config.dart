class AppConfig {
  static const String googleMapsApiKey = String.fromEnvironment('MAPS_API_KEY');

  // The deployed web app's URL — share links always point here regardless
  // of which platform (web or Android) the share was created from, since
  // a link only makes sense opened in a browser (Uri.base on Android
  // resolves to something app-internal, not a usable web address).
  static const String webBaseUrl = 'https://steffenkastian.github.io/boat_routes/app/';
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
  //
  // 100m rather than something tighter: a phone tracking in the background
  // (in a pocket, below deck, screen locked) routinely reports temporarily
  // degraded accuracy — a stricter threshold here doesn't just reject
  // outliers, it silently drops *all* real fixes for however long accuracy
  // stays degraded, which showed up as multi-minute gaps in a recorded
  // track. maxGapSeconds below is the backstop for whatever this still
  // doesn't cover.
  static const double maxHorizontalAccuracyMeters = 100.0;

  // Applies even when maxGapSeconds forces a fix through — a gap should
  // never end with genuinely nonsensical data (e.g. a coarse cell-tower-
  // only fallback fix off by kilometers) getting baked into the track just
  // because enough time has passed. Deliberately far looser than the
  // normal 100m bound above; this is a last-resort sanity check, not a
  // quality bar.
  static const double maxHorizontalAccuracyMetersForced = 1000.0;

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

  // Backstop against an unbounded gap: if it's been at least this long
  // since the last *accepted* fix, the next candidate fix is accepted
  // regardless of the checks above, rather than being rejected yet again
  // and extending the gap indefinitely. Every individual check exists to
  // reject one bad-looking fix and wait for the next one — none of them
  // are designed to cope with conditions (e.g. degraded accuracy) that
  // persist for minutes at a time, which a fixed threshold alone can't
  // fully rule out no matter how it's tuned.
  static const double maxGapSeconds = 60.0;
}

// Tuning for simplifyTrack (see track_simplifier.dart), applied once when a
// Törn is saved to cut down how many points a long recorded track ends up
// stored/synced/redrawn with.
class TrackSimplificationConfig {
  // A point is dropped if it's within this many meters of the straight
  // line its neighbors would otherwise form. 5m keeps real course changes
  // (e.g. tacking) intact while cutting GPS noise and near-straight
  // stretches down to far fewer points.
  static const double toleranceMeters = 5.0;

  // How often LiveLocationController re-simplifies the track *while still
  // recording* (see startRecording), not just once at the end — keeps a
  // long Törn's in-memory point count from growing unbounded for its whole
  // duration. The most recent fixes (since the last run) are always left
  // untouched between runs, so this never affects the live position/
  // heading/outlier-filter logic, which only ever looks at the latest fix.
  static const Duration liveSimplificationInterval = Duration(minutes: 10);
}