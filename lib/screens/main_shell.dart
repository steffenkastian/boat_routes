import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/regatta.dart';
import '../models/tour.dart';
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
  List<LatLng>? _referenceRoute;
  String? _referenceRouteLabel;
  // Set by ToursScreen's "Route bearbeiten" action (while a Törn with a
  // loaded reference route is being tracked) to hand that route's points
  // to RoutePlannerScreen for editing. Tapping "Törn starten" there again
  // flows back through _onStartTour, which — since ToursScreen is still
  // mid-Törn — updates the ongoing tracking's reference route instead of
  // starting a new one (see ToursScreen.didUpdateWidget).
  List<LatLng>? _routeToEdit;
  // See RoutePlannerScreen.externalRouteRequestId — a second "Route
  // bearbeiten" tap for the same (unchanged) route still needs to reload
  // the canvas, which comparing _routeToEdit by reference alone wouldn't
  // catch.
  int _editRouteRequestId = 0;
  // Set by TourFolderDetailScreen's "Törn bearbeiten" action — distinct
  // from _routeToEdit above (a plain point list for the live-tracking
  // reference route) since RoutePlannerScreen needs the whole Tour here to
  // offer overwriting it in place once edited.
  Tour? _tourToEdit;
  int _editTourRequestId = 0;
  // Bumped after RoutePlannerScreen overwrites a Tour in place, so
  // ToursScreen — an IndexedStack sibling that otherwise never notices
  // changes made on another tab — reloads its list instead of showing the
  // now-stale points.
  int _tourListRefreshRequestId = 0;

  void _onRegattaSelected(Regatta regatta) {
    setState(() {
      _referenceRoute = regatta.points;
      _referenceRouteLabel = regatta.name;
      _selectedIndex = 2;
    });
  }

  void _onStartTour(List<LatLng> points) {
    setState(() {
      _referenceRoute = points;
      _referenceRouteLabel = null;
      _selectedIndex = 2;
    });
  }

  void _onEditRoute(List<LatLng> points) {
    setState(() {
      _routeToEdit = points;
      _editRouteRequestId++;
      _selectedIndex = 0;
    });
  }

  void _onEditTour(Tour tour) {
    setState(() {
      _tourToEdit = tour;
      _editTourRequestId++;
      _selectedIndex = 0;
    });
  }

  void _onTourOverwritten(Tour tour) {
    setState(() => _tourListRefreshRequestId++);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      RoutePlannerScreen(
        onStartTour: _onStartTour,
        externalRoute: _routeToEdit,
        externalRouteRequestId: _editRouteRequestId,
        externalTourToEdit: _tourToEdit,
        externalTourEditRequestId: _editTourRequestId,
        onTourUpdated: _onTourOverwritten,
      ),
      RegattaScreen(onRegattaSelected: _onRegattaSelected),
      ToursScreen(
        referenceRoute: _referenceRoute,
        referenceRouteLabel: _referenceRouteLabel,
        onEditRoute: _onEditRoute,
        onEditTour: _onEditTour,
        tourListRefreshRequestId: _tourListRefreshRequestId,
      ),
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
