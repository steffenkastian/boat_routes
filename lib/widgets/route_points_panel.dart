import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../utils/geo_utils.dart';

class RoutePointsPanel extends StatelessWidget {
  const RoutePointsPanel({
    required this.points,
    required this.onRemovePoint,
    super.key,
  });

  final List<LatLng> points;
  final ValueChanged<int> onRemovePoint;

  @override
  Widget build(BuildContext context) {
    double totalDistance = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      totalDistance += distanceNm(points[i], points[i + 1]);
    }

    return Container(
      color: Colors.grey.shade100,
      child: Column(
        children: [
          Expanded(
            child: points.isEmpty
                ? const Center(child: Text('Noch keine Punkte gesetzt'))
                : ListView.builder(
                    itemCount: points.length,
                    itemBuilder: (context, index) {
                      final point = points[index];

                      double? segmentDistance;
                      double? segmentBearing;
                      if (index > 0) {
                        segmentDistance =
                            distanceNm(points[index - 1], point);
                        segmentBearing = bearing(points[index - 1], point);
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
                              if (segmentDistance != null)
                                Text(
                                  'Kurs: ${segmentBearing!.toStringAsFixed(0)}°  •  Distanz: ${segmentDistance.toStringAsFixed(2)} sm',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black87,
                                  ),
                                ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => onRemovePoint(index),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (points.length > 1)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Gesamtdistanz: ${totalDistance.toStringAsFixed(2)} sm',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}
