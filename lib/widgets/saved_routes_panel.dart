import 'package:flutter/material.dart';

import '../models/boat_route.dart';

class SavedRoutesPanel extends StatelessWidget {
  const SavedRoutesPanel({
    required this.routes,
    required this.onLoad,
    required this.onDelete,
    super.key,
  });

  final List<BoatRoute> routes;
  final ValueChanged<BoatRoute> onLoad;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context) {
    if (routes.isEmpty) {
      return const Center(child: Text('Noch keine Routen gespeichert'));
    }

    return ListView.builder(
      itemCount: routes.length,
      itemBuilder: (context, index) {
        final route = routes[index];
        return ListTile(
          leading: const Icon(Icons.directions_boat),
          title: Text(route.name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.play_arrow, color: Colors.green),
                onPressed: () => onLoad(route),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => onDelete(index),
              ),
            ],
          ),
        );
      },
    );
  }
}
