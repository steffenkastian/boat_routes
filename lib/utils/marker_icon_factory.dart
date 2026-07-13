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

// Draws a small rounded text badge (e.g. "123°") and bakes it into a
// BitmapDescriptor, for labelling route segments directly on the map.
Future<BitmapDescriptor> buildLabelIcon(
  String text, {
  Color background = const Color(0xCC1A1A1A),
  Color textColor = Colors.white,
  double fontSize = 13,
  EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
}) async {
  final textPainter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: textColor,
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  final width = textPainter.width + padding.horizontal;
  final height = textPainter.height + padding.vertical;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

  final rrect = RRect.fromRectAndRadius(
    Rect.fromLTWH(0, 0, width, height),
    Radius.circular(height / 2),
  );
  canvas.drawRRect(rrect, Paint()..color = background);
  textPainter.paint(canvas, Offset(padding.left, padding.top));

  final picture = recorder.endRecording();
  final image = await picture.toImage(width.ceil(), height.ceil());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

  return BitmapDescriptor.bytes(
    bytes!.buffer.asUint8List(),
    width: width,
    height: height,
  );
}
