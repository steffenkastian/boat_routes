import 'package:flutter/material.dart';

import '../models/regatta.dart';
import 'profile_screen.dart';
import 'regatta_screen.dart';
import 'route_planner_screen.dart';
import 'tours_screen.dart';

// Bottom-nav shell hosting the app's top-level pages. Uses IndexedStack so
// switching tabs doesn't tear down RoutePlannerScreen's/ToursScreen's state
// (drawn points, active GPS subscription) — each page is only built once.
// Passing new widget instances with each MainShell rebuild is safe here:
// Flutter's IndexedStack reconciles children by type+position, not instance
// identity, so their State objects survive (only didUpdateWidget fires).
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  Regatta? _selectedRegatta;

  void _onRegattaSelected(Regatta regatta) {
    setState(() {
      _selectedRegatta = regatta;
      _selectedIndex = 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const RoutePlannerScreen(),
      RegattaScreen(onRegattaSelected: _onRegattaSelected),
      ToursScreen(regatta: _selectedRegatta),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: pages),
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
