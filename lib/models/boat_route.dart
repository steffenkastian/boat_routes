import 'package:google_maps_flutter/google_maps_flutter.dart';

class BoatRoute {
  BoatRoute({required this.name, required this.points, DateTime? createdAt})
      : createdAt = createdAt ?? DateTime.now();

  final String name;
  final List<LatLng> points;
  final DateTime createdAt;

  factory BoatRoute.fromJson(Map<String, dynamic> json) => BoatRoute(
        name: json['name'] as String,
        points: (json['points'] as List)
            .map((p) => LatLng(
                  (p['lat'] as num).toDouble(),
                  (p['lng'] as num).toDouble(),
                ))
            .toList(),
        // Older locally-saved routes predate this field.
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'points': points
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
        'createdAt': createdAt.toIso8601String(),
      };
}
