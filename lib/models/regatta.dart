import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class Regatta {
  const Regatta({
    this.id,
    required this.name,
    required this.plz,
    required this.points,
    required this.createdAt,
  });

  final String? id;
  final String name;
  final String plz;
  final List<LatLng> points;
  final DateTime createdAt;

  factory Regatta.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Regatta(
      id: doc.id,
      name: data['name'] as String,
      plz: data['plz'] as String,
      points: (data['points'] as List)
          .map((p) => LatLng(
                (p['lat'] as num).toDouble(),
                (p['lng'] as num).toDouble(),
              ))
          .toList(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'plz': plz,
        'points': points
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
        'createdAt': FieldValue.serverTimestamp(),
      };
}
