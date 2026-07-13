import 'package:flutter/material.dart';

Future<String?> promptForName(
  BuildContext context, {
  required String title,
  String hint = '',
}) async {
  final nameController = TextEditingController();

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: nameController,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          child: const Text('Abbrechen'),
          onPressed: () => Navigator.pop(context, false),
        ),
        ElevatedButton(
          child: const Text('Speichern'),
          onPressed: () {
            if (nameController.text.trim().isEmpty) return;
            Navigator.pop(context, true);
          },
        ),
      ],
    ),
  );

  if (saved != true) return null;
  final name = nameController.text.trim();
  return name.isEmpty ? null : name;
}
