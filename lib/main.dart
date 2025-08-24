import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const BoatRoutesApp());
}

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
      home: const RoutePlannerScreen(),
    );
  }
}

class RoutePlannerScreen extends StatefulWidget {
  const RoutePlannerScreen({super.key});

  @override
  State<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends State<RoutePlannerScreen> {
  final List<LatLng> _points = [];
  GoogleMapController? _mapController;
  List<Map<String, dynamic>> _savedRoutes = [];
  bool _addingEnabled = true; // << neu

  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(54.382440, 11.145867),
    zoom: 11,
  );

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  void _addPoint(LatLng position) {
    setState(() {
      _points.add(position);
    });
  }

  void _removePoint(int index) {
    setState(() {
      _points.removeAt(index);
    });
  }

// --- Route löschen ---
  Future<void> _deleteRoute(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final routes = prefs.getStringList("routes") ?? [];
    routes.removeAt(index);
    await prefs.setStringList("routes", routes);
    setState(() {
      _savedRoutes.removeAt(index);
    });
  }

  Future<void> _saveRoute() async {
    if (_points.isEmpty) return;

    final nameController = TextEditingController();
    final prefs = await SharedPreferences.getInstance();


    setState(() => _addingEnabled = false); // Punkte deaktivieren

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Routenname eingeben"),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(hintText: "z.B. Ostseetörn"),
        ),
        actions: [
          TextButton(
            child: const Text("Abbrechen"),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            child: const Text("Speichern"),
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;

              final newRoute = {
                "name": name,
                "points": _points
                    .map((p) => {"lat": p.latitude, "lng": p.longitude})
                    .toList(),
              };

              final routes = prefs.getStringList("routes") ?? [];
              routes.add(jsonEncode(newRoute));
              await prefs.setStringList("routes", routes);

              Navigator.pop(context);
              setState(() {
                _savedRoutes.add(newRoute);
              });
            },
          ),
        ],
      ),
    );

    setState(() => _addingEnabled = true); // wieder aktivieren
  }



  Future<void> _loadRoutes() async {
    final prefs = await SharedPreferences.getInstance();
    final routes = prefs.getStringList("routes") ?? [];
    setState(() {
      _savedRoutes =
          routes.map((r) => jsonDecode(r) as Map<String, dynamic>).toList();
    });
  }
  
// --- Route laden ---
  void _loadRoute(Map<String, dynamic> route) {
    final pts = (route["points"] as List)
        .map((p) => LatLng(p["lat"], p["lng"]))
        .toList();
    setState(() {
      _points
        ..clear()
        ..addAll(pts);
    });
  }

  double _distanceNm(LatLng p1, LatLng p2) {
    const earthRadius = 6371000; // Meter
    final dLat = _deg2rad(p2.latitude - p1.latitude);
    final dLon = _deg2rad(p2.longitude - p1.longitude);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(p1.latitude)) *
            cos(_deg2rad(p2.latitude)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    final distanceMeters = earthRadius * c;
    return distanceMeters / 1852;
  }

  double _deg2rad(double deg) => deg * pi / 180;

  @override
  Widget build(BuildContext context) {
    final markers = _points.asMap().entries.map((entry) {
      final idx = entry.key;
      final pos = entry.value;
      return Marker(
        markerId: MarkerId('point_$idx'),
        position: pos,
        infoWindow: InfoWindow(title: 'Punkt ${idx + 1}'),
      );
    }).toSet();

    final polyline = Polyline(
      polylineId: const PolylineId('route'),
      color: Colors.blue,
      width: 4,
      points: _points,
    );

    double totalDistance = 0.0;
    for (var i = 0; i < _points.length - 1; i++) {
      totalDistance += _distanceNm(_points[i], _points[i + 1]);
    }

  return Scaffold(
    appBar: AppBar(
      title: const Text('Routenplaner'),
      actions: [
        IconButton(
          tooltip: 'Neue Route',
          icon: const Icon(Icons.add), // Icon für neue Route
          onPressed: () {
            setState(() {
              _points.clear(); // Alle Punkte löschen
            });
          },
        ),
        IconButton(
          icon: const Icon(Icons.save),
          onPressed: _saveRoute,
        ),
      ],
    ),
    body: Column(
      children: [
        // obere Hälfte: Karte + Punkte nebeneinander
        Expanded(
          flex: 2,
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: GoogleMap(
                  initialCameraPosition: _initialCamera,
                  onMapCreated: (controller) => _mapController = controller,
                  onTap: (pos) {
                    if (_addingEnabled) _addPoint(pos);
                  },
                  markers: markers,
                  polylines: {polyline},
                  zoomControlsEnabled: true,
                  compassEnabled: true,
                ),
              ),
 Expanded(
                flex: 1,
                child: Container(
                  color: Colors.grey.shade100,
                  child: Column(
                    children: [
                      // Liste der Punkte inkl. Teilstrecken
                      Expanded(
                              child: _points.isEmpty
                                  ? const Center(child: Text('Noch keine Punkte gesetzt'))
                                  : ListView.builder(
                                      itemCount: _points.length,
                                      itemBuilder: (context, index) {
                                        final point = _points[index];

                                        // --- NEU: Distanz vom vorherigen Punkt berechnen ---
                                        double? segmentDistance;
                                        if (index > 0) {
                                          segmentDistance = _distanceNm(_points[index - 1], point);
                                        }

                                        return Card(
                                          child: ListTile(
                                            leading: CircleAvatar(
                                              child: Text('${index + 1}'),
                                            ),
                                            title: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Lat: ${point.latitude.toStringAsFixed(4)}\nLng: ${point.longitude.toStringAsFixed(4)}',
                                                  style: const TextStyle(fontSize: 12),
                                                ),
                                                // --- NEU: Distanz in sm anzeigen, falls nicht erster Punkt ---
                                                if (segmentDistance != null)
                                                  Text(
                                                    'Distanz: ${segmentDistance.toStringAsFixed(2)} sm',
                                                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                                                  ),
                                              ],
                                            ),
                                            trailing: IconButton(
                                              icon: const Icon(Icons.delete, color: Colors.red),
                                              onPressed: () => _removePoint(index),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                            // --- NEU: Gesamtdistanz unterhalb der Liste ---
                            if (_points.length > 1)
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  'Gesamtdistanz: ${totalDistance.toStringAsFixed(2)} sm',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

        // untere Hälfte: gespeicherte Routen
        Expanded(
          flex: 1,
          child: ListView.builder(
            itemCount: _savedRoutes.length,
            itemBuilder: (context, index) {
              final route = _savedRoutes[index];
              return ListTile(
                leading: const Icon(Icons.directions_boat),
                title: Text(route["name"]),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.play_arrow, color: Colors.green),
                      onPressed: () => _loadRoute(route),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteRoute(index),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    ),
    );
  }
}