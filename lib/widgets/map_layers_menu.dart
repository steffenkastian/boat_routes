import 'package:flutter/material.dart';

// Returns the same Future showModalBottomSheet does, so callers can guard
// against the closing tap (dismissing the sheet by tapping outside it) also
// reaching the map underneath — on Flutter web the GoogleMap platform view
// can receive a tap directly, bypassing the sheet's own modal barrier.
Future<void> showMapLayersMenu(
  BuildContext context, {
  required bool showSeaMarks,
  required ValueChanged<bool> onSeaMarksChanged,
  required bool showDepth,
  required ValueChanged<bool> onDepthChanged,
  required bool showCourseAndDistance,
  required ValueChanged<bool> onCourseAndDistanceChanged,
}) {
  // Local, mutable copies: the switches need something they can actually
  // update via setSheetState. Binding `value` directly to the (immutable)
  // showSeaMarks/showDepth parameters looked right but never visibly
  // flipped, since those parameters are fixed at the moment this function
  // was called and StatefulBuilder's rebuild doesn't change them.
  var localSeaMarks = showSeaMarks;
  var localDepth = showDepth;
  var localCourseAndDistance = showCourseAndDistance;

  return showModalBottomSheet(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.anchor),
              title: const Text('OpenSeaMap Seezeichen'),
              value: localSeaMarks,
              onChanged: (value) {
                onSeaMarksChanged(value);
                setSheetState(() => localSeaMarks = value);
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.waves),
              title: const Text('Tiefenkarte (EMODnet)'),
              value: localDepth,
              onChanged: (value) {
                onDepthChanged(value);
                setSheetState(() => localDepth = value);
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.straighten),
              title: const Text('Kurs & Distanz auf der Karte'),
              value: localCourseAndDistance,
              onChanged: (value) {
                onCourseAndDistanceChanged(value);
                setSheetState(() => localCourseAndDistance = value);
              },
            ),
          ],
        ),
      ),
    ),
  );
}
