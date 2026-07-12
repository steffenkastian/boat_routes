import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Draws a boat-heading arrow pointing "up" (north) and bakes it into a
// BitmapDescriptor. Rotation to match actual heading is done via the
// Marker's own `rotation` field, not by re-drawing this bitmap.
Future<BitmapDescriptor> buildBoatArrowIcon({
  double size = 64,
  Color color = Colors.blueAccent,
  Color borderColor = Colors.white,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

  final center = size / 2;
  final path = Path()
    ..moveTo(center, size * 0.05) // tip
    ..lineTo(size * 0.85, size * 0.85) // right base
    ..lineTo(center, size * 0.65) // notch
    ..lineTo(size * 0.15, size * 0.85) // left base
    ..close();

  final fillPaint = Paint()
    ..color = color
    ..style = PaintingStyle.fill;
  final strokePaint = Paint()
    ..color = borderColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = size * 0.05;

  canvas.drawPath(path, fillPaint);
  canvas.drawPath(path, strokePaint);

  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

  return BitmapDescriptor.bytes(
    bytes!.buffer.asUint8List(),
    width: size,
    height: size,
  );
}
