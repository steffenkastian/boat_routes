import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Lets a point be added by typing decimal-degree coordinates instead of
// tapping the map — e.g. for planning a route from a chart before being on
// the water.
class ManualPointInput extends StatefulWidget {
  const ManualPointInput({required this.onAddPoint, super.key});

  final ValueChanged<LatLng> onAddPoint;

  @override
  State<ManualPointInput> createState() => _ManualPointInputState();
}

class _ManualPointInputState extends State<ManualPointInput> {
  final _latController = TextEditingController();
  final _lngController = TextEditingController();

  @override
  void dispose() {
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  void _submit() {
    final lat = double.tryParse(_latController.text.trim().replaceAll(',', '.'));
    final lng = double.tryParse(_lngController.text.trim().replaceAll(',', '.'));

    if (lat == null || lng == null || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ungültige Koordinaten')),
      );
      return;
    }

    widget.onAddPoint(LatLng(lat, lng));
    _latController.clear();
    _lngController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _latController,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Breitengrad',
                hintText: 'z.B. 54.3824',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _lngController,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Längengrad',
                hintText: 'z.B. 11.1459',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            icon: const Icon(Icons.add),
            tooltip: 'Punkt hinzufügen',
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
