import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../utils/geo_utils.dart';

// Tracks progress along a planned route's waypoints ("Tonnen"): once the
// live position comes within the rounding radius of the current target
// waypoint, it's considered rounded and the next one becomes the target.
// Exposes distance/course from a live position to the current target for a
// simple regatta-style navigation readout.
class MarkRoundingController extends ChangeNotifier {
  MarkRoundingController(this.marks);

  final List<LatLng> marks;

  static const _roundingRadiusMeters = 30.0;

  int currentTargetIndex = 0;

  LatLng? get currentTarget =>
      currentTargetIndex < marks.length ? marks[currentTargetIndex] : null;

  bool get isFinished => marks.isEmpty || currentTargetIndex >= marks.length;

  void updateWithPosition(LatLng position) {
    final target = currentTarget;
    if (target == null) return;

    if (distanceMeters(position, target) <= _roundingRadiusMeters) {
      currentTargetIndex++;
      notifyListeners();
    }
  }

  // Manually advances to the next mark regardless of position — e.g. the
  // crew decides to skip a Tonne that isn't going to be rounded this Törn.
  // A no-op once every mark is already rounded.
  void skipCurrentTarget() {
    if (isFinished) return;
    currentTargetIndex++;
    notifyListeners();
  }

  double? distanceToTargetNm(LatLng position) {
    final target = currentTarget;
    return target == null ? null : distanceNm(position, target);
  }

  // Distance from a live position to the current target plus every
  // remaining leg after it — the full remaining length of the route, not
  // just the next mark.
  double? remainingDistanceNm(LatLng position) {
    final target = currentTarget;
    if (target == null) return null;
    final remaining = marks.sublist(currentTargetIndex);
    return distanceNm(position, target) + totalDistanceNm(remaining);
  }

  double? bearingToTarget(LatLng position) {
    final target = currentTarget;
    return target == null ? null : bearing(position, target);
  }
}
