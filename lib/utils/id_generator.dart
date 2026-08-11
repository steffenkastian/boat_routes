import 'dart:math';

// A locally-generated id, good enough for a single user creating routes/
// Törns from their own devices (no coordination/collision-checking with a
// server needed) — avoids pulling in a UUID package or Firestore itself
// just for this. Timestamp keeps it roughly sortable; the random suffix
// covers same-microsecond collisions.
String generateLocalId() {
  final random = Random().nextInt(1 << 32).toRadixString(36);
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}$random';
}
