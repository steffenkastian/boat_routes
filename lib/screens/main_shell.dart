import 'package:flutter/material.dart';

import 'profile_screen.dart';
import 'regatta_screen.dart';
import 'route_planner_screen.dart';
import 'tours_screen.dart';

// Bottom-nav shell hosting the app's top-level pages. Uses IndexedStack so
// switching tabs doesn't tear down RoutePlannerScreen's state (drawn
// points, active GPS subscription) — each page is only built once.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  static const _pages = [
    RoutePlannerScreen(),
    RegattaScreen(),
    ToursScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.route), label: 'Route planen'),
          NavigationDestination(icon: Icon(Icons.flag), label: 'Regatta'),
          NavigationDestination(
            icon: Icon(Icons.directions_boat),
            label: 'Törns',
          ),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}
