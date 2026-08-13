import 'dart:math';

// A locally-generated id, good enough for a single user creating routes/
// Törns from their own devices (no coordination/collision-checking with a
// server needed) — avoids pulling in a UUID package or Firestore itself
// just for this. Timestamp keeps it roughly sortable; the random suffix
// covers same-microsecond collisions.
String generateLocalId() {
  // Not `1 << 32`: on the web compile target, Random.nextInt(1 << 32)
  // throws "RangeError: max must be in range 0 < max ≤ 2^32, was 0" —
  // the shift evaluates to 0 there instead of 4294967296. Staying one
  // below the boundary avoids whatever web-specific bit-masking bug that
  // triggers, while giving up only a single value's worth of entropy.
  final random = Random().nextInt((1 << 32) - 1).toRadixString(36);
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}$random';
}
