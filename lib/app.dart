import 'package:flutter/material.dart';

import 'screens/main_shell.dart';

class BoatRoutesApp extends StatelessWidget {
  const BoatRoutesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Boat Routes – Planner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0B6EF3),
        useMaterial3: true,
      ),
      home: const MainShell(),
    );
  }
}
