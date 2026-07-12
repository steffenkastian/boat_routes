import 'package:flutter/material.dart';

Future<String?> promptForRouteName(BuildContext context) async {
  final nameController = TextEditingController();

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Routenname eingeben'),
      content: TextField(
        controller: nameController,
        decoration: const InputDecoration(hintText: 'z.B. Ostseetörn'),
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
