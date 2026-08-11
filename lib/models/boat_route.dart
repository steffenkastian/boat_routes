import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../utils/id_generator.dart';

class BoatRoute {
  BoatRoute({
    String? id,
    required this.name,
    required this.points,
    DateTime? createdAt,
  })  : id = id ?? generateLocalId(),
        createdAt = createdAt ?? DateTime.now();

  // Generated locally at creation time (not a Firestore-assigned id) so it's
  // already stable and known before this route is ever synced to an
  // account — that's what lets a share link or "shared with me" reference
  // stay valid across local storage, Firestore, and a pasted link.
  final String id;
  final String name;
  final List<LatLng> points;
  final DateTime createdAt;

  factory BoatRoute.fromJson(Map<String, dynamic> json) => BoatRoute(
        // Routes saved before this field existed don't have one — falling
        // back to a fresh id here (rather than leaving it stable) is fine
        // since those routes were never shareable in the first place.
        id: json['id'] as String?,
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
        'id': id,
        'name': name,
        'points': points
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
        'createdAt': createdAt.toIso8601String(),
      };
}
