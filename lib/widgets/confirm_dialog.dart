import 'package:flutter/material.dart';

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Löschen',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          child: const Text('Abbrechen'),
          onPressed: () => Navigator.pop(context, false),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: Text(confirmLabel),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
