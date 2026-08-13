import 'dart:math';

// A locally-generated id, good enough for a single user creating routes/
// Törns from their own devices (no coordination/collision-checking with a
// server needed) — avoids pulling in a UUID package or Firestore itself
// just for this. Timestamp keeps it roughly sortable; the random suffix
// covers same-microsecond collisions.
String generateLocalId() {
  // Not `1 << 32` (or any expression built from it): on the web compile
  // target, that shift evaluates to 0 rather than 4294967296 — confirmed
  // by Random.nextInt(1 << 32) throwing "max ... was 0", and
  // Random.nextInt((1 << 32) - 1) throwing "max ... was -1" right after.
  // A plain literal sidesteps whatever web-specific 32-bit truncation
  // causes that, on any compile target.
  final random = Random().nextInt(4294967295).toRadixString(36);
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}$random';
}
