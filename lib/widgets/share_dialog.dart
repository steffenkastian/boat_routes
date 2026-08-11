import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';

enum _ShareMode { link, email }

// Offers to share something either as a public link (anyone who has it can
// view, no login needed) or to one specific signed-in email address.
// [createShare] does the actual Firestore write (see ShareService) and
// returns the new share's id, used to build the link shown afterwards.
Future<void> showShareDialog(
  BuildContext context, {
  required Future<String> Function({String? email}) createShare,
}) async {
  final emailController = TextEditingController();
  var mode = _ShareMode.link;

  final choice = await showDialog<({_ShareMode mode, String? email})>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Teilen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioListTile<_ShareMode>(
              contentPadding: EdgeInsets.zero,
              title: const Text('Öffentlicher Link'),
              subtitle: const Text('Jeder mit dem Link kann es ansehen'),
              value: _ShareMode.link,
              groupValue: mode,
              onChanged: (value) => setDialogState(() => mode = value!),
            ),
            RadioListTile<_ShareMode>(
              contentPadding: EdgeInsets.zero,
              title: const Text('An eine E-Mail-Adresse'),
              subtitle: const Text('Nur dieses Konto kann es sehen'),
              value: _ShareMode.email,
              groupValue: mode,
              onChanged: (value) => setDialogState(() => mode = value!),
            ),
            if (mode == _ShareMode.email)
              TextField(
                controller: emailController,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-Mail-Adresse',
                  hintText: 'name@beispiel.de',
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              final email = emailController.text.trim();
              if (mode == _ShareMode.email && email.isEmpty) return;
              Navigator.pop(
                context,
                (mode: mode, email: mode == _ShareMode.email ? email : null),
              );
            },
            child: const Text('Teilen'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  final shareId = await createShare(email: choice.email);
  if (!context.mounted) return;

  if (choice.mode == _ShareMode.link) {
    final link = '${AppConfig.webBaseUrl}?share=$shareId';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Link erstellt'),
        content: SelectableText(link),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Kopieren'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fertig'),
          ),
        ],
      ),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Geteilt mit ${choice.email}.')),
    );
  }
}
