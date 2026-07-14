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

// Draws a small rounded text badge (e.g. "123°", optionally with a smaller
// second line such as a distance) and bakes it into a BitmapDescriptor, for
// labelling route segments directly on the map.
Future<BitmapDescriptor> buildLabelIcon(
  String text, {
  String? secondaryText,
  Color background = const Color(0xCC1A1A1A),
  Color textColor = Colors.white,
  double fontSize = 13,
  double secondaryFontSize = 10,
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

  final secondaryPainter = secondaryText == null
      ? null
      : (TextPainter(
          text: TextSpan(
            text: secondaryText,
            style: TextStyle(color: textColor, fontSize: secondaryFontSize),
          ),
          textDirection: TextDirection.ltr,
        )..layout());

  final contentWidth = secondaryPainter == null
      ? textPainter.width
      : (textPainter.width > secondaryPainter.width
          ? textPainter.width
          : secondaryPainter.width);
  final contentHeight = textPainter.height + (secondaryPainter?.height ?? 0);

  final width = contentWidth + padding.horizontal;
  final height = contentHeight + padding.vertical;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

  final rrect = RRect.fromRectAndRadius(
    Rect.fromLTWH(0, 0, width, height),
    Radius.circular(height / 2),
  );
  canvas.drawRRect(rrect, Paint()..color = background);
  textPainter.paint(
    canvas,
    Offset(padding.left + (contentWidth - textPainter.width) / 2, padding.top),
  );
  secondaryPainter?.paint(
    canvas,
    Offset(
      padding.left + (contentWidth - secondaryPainter.width) / 2,
      padding.top + textPainter.height,
    ),
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(width.ceil(), height.ceil());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

  return BitmapDescriptor.bytes(
    bytes!.buffer.asUint8List(),
    width: width,
    height: height,
  );
}

// Draws a filled red dot with the route point's number in it, so the point
// order is visible directly on the map instead of only on tap.
Future<BitmapDescriptor> buildNumberedDotIcon(
  int number, {
  double size = 32,
  Color color = Colors.red,
  Color textColor = Colors.white,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

  final center = Offset(size / 2, size / 2);
  final radius = size / 2 - 2;

  canvas.drawCircle(center, radius, Paint()..color = color);
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );

  final textPainter = TextPainter(
    text: TextSpan(
      text: '$number',
      style: TextStyle(
        color: textColor,
        fontSize: size * 0.5,
        fontWeight: FontWeight.bold,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  textPainter.paint(
    canvas,
    Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

  return BitmapDescriptor.bytes(
    bytes!.buffer.asUint8List(),
    width: size,
    height: size,
  );
}
