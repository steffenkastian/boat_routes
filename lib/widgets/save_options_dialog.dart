import 'package:flutter/material.dart';

class SaveOptions {
  const SaveOptions({
    required this.name,
    required this.publishAsRegatta,
    this.plz,
  });

  final String name;
  final bool publishAsRegatta;
  final String? plz;
}

Future<SaveOptions?> promptForSaveOptions(
  BuildContext context, {
  required String title,
  required String hint,
  required bool canPublishAsRegatta,
}) async {
  final nameController = TextEditingController();
  final plzController = TextEditingController();
  var publishAsRegatta = false;

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(hintText: hint),
            ),
            if (canPublishAsRegatta) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Als Regatta veröffentlichen'),
                subtitle: const Text('Öffentlich sichtbar, über PLZ suchbar'),
                value: publishAsRegatta,
                onChanged: (value) =>
                    setDialogState(() => publishAsRegatta = value),
              ),
              if (publishAsRegatta)
                TextField(
                  controller: plzController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: 'PLZ, z.B. 24148'),
                ),
            ],
          ],
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
              if (publishAsRegatta && plzController.text.trim().isEmpty) return;
              Navigator.pop(context, true);
            },
          ),
        ],
      ),
    ),
  );

  if (saved != true) return null;
  final name = nameController.text.trim();
  if (name.isEmpty) return null;

  return SaveOptions(
    name: name,
    publishAsRegatta: publishAsRegatta,
    plz: publishAsRegatta ? plzController.text.trim() : null,
  );
}
