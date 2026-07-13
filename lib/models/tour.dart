import 'package:google_maps_flutter/google_maps_flutter.dart';

class Tour {
  const Tour({
    required this.name,
    required this.points,
    required this.startedAt,
    required this.endedAt,
  });

  final String name;
  final List<LatLng> points;
  final DateTime startedAt;
  final DateTime endedAt;

  factory Tour.fromJson(Map<String, dynamic> json) => Tour(
        name: json['name'] as String,
        points: (json['points'] as List)
            .map((p) => LatLng(
                  (p['lat'] as num).toDouble(),
                  (p['lng'] as num).toDouble(),
                ))
            .toList(),
        startedAt: DateTime.parse(json['startedAt'] as String),
        endedAt: DateTime.parse(json['endedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'points': points
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
      };
}
