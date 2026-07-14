import 'package:flutter/material.dart';

void showMapLayersMenu(
  BuildContext context, {
  required bool showSeaMarks,
  required ValueChanged<bool> onSeaMarksChanged,
  required bool showDepth,
  required ValueChanged<bool> onDepthChanged,
}) {
  showModalBottomSheet(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.anchor),
              title: const Text('OpenSeaMap Seezeichen'),
              value: showSeaMarks,
              onChanged: (value) {
                onSeaMarksChanged(value);
                setSheetState(() {});
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.waves),
              title: const Text('Tiefenlinien (Beta)'),
              subtitle: const Text('Deckung je nach Region lückenhaft'),
              value: showDepth,
              onChanged: (value) {
                onDepthChanged(value);
                setSheetState(() {});
              },
            ),
          ],
        ),
      ),
    ),
  );
}
