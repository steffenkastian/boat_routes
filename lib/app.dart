import 'package:flutter/material.dart';

import 'screens/main_shell.dart';
import 'screens/shared_item_screen.dart';

class BoatRoutesApp extends StatelessWidget {
  const BoatRoutesApp({super.key});

  @override
  Widget build(BuildContext context) {
    // A share link (see share_dialog.dart) looks like
    // "<webBaseUrl>?share=<id>" — read once at startup, since this is only
    // ever a fresh page load (a share link is never navigated to from
    // inside a running instance of the app). Uri.base resolves to
    // something app-internal (not a real URL) on Android, so this is a
    // web-only path in practice; queryParameters is just empty there.
    final shareId = Uri.base.queryParameters['share'];
    return MaterialApp(
      title: 'Boat Routes – Planner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0B6EF3),
        useMaterial3: true,
      ),
      home: shareId != null
          ? SharedItemScreen(shareId: shareId, isAppRoot: true)
          : const MainShell(),
    );
  }
}
