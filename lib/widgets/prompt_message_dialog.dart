import 'package:flutter/material.dart';

// Same shell as prompt_name_dialog.dart's promptForName, but multiline —
// used for feedback wishes/replies, which are prose rather than a short
// name.
Future<String?> promptForMessage(
  BuildContext context, {
  required String title,
  String hint = '',
  String confirmLabel = 'Senden',
}) async {
  final controller = TextEditingController();

  final sent = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 4,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          child: const Text('Abbrechen'),
          onPressed: () => Navigator.pop(context, false),
        ),
        ElevatedButton(
          child: Text(confirmLabel),
          onPressed: () {
            if (controller.text.trim().isEmpty) return;
            Navigator.pop(context, true);
          },
        ),
      ],
    ),
  );

  if (sent != true) return null;
  final message = controller.text.trim();
  return message.isEmpty ? null : message;
}
