import 'package:google_maps_flutter/google_maps_flutter.dart';

class BoatRoute {
  const BoatRoute({required this.name, required this.points});

  final String name;
  final List<LatLng> points;

  factory BoatRoute.fromJson(Map<String, dynamic> json) => BoatRoute(
        name: json['name'] as String,
        points: (json['points'] as List)
            .map((p) => LatLng(
                  (p['lat'] as num).toDouble(),
                  (p['lng'] as num).toDouble(),
                ))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'points': points
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
      };
}
