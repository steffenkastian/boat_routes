import 'package:flutter/material.dart';

import '../models/regatta.dart';
import '../services/regatta_storage_service.dart';
import '../utils/geo_utils.dart';

class RegattaScreen extends StatefulWidget {
  const RegattaScreen({required this.onRegattaSelected, super.key});

  final ValueChanged<Regatta> onRegattaSelected;

  @override
  State<RegattaScreen> createState() => _RegattaScreenState();
}

class _RegattaScreenState extends State<RegattaScreen> {
  final _storage = RegattaStorageService();
  final _plzController = TextEditingController();

  bool _isSearching = false;
  bool _hasSearched = false;
  List<Regatta> _results = [];

  @override
  void dispose() {
    _plzController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final plz = _plzController.text.trim();
    if (plz.isEmpty) return;

    setState(() => _isSearching = true);
    final results = await _storage.searchByPlz(plz);
    setState(() {
      _results = results;
      _isSearching = false;
      _hasSearched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Regatta fahren')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _plzController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'PLZ',
                      hintText: 'z.B. 24148',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.search),
                  onPressed: _isSearching ? null : _search,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildResults()),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_hasSearched) {
      return const Center(child: Text('PLZ eingeben, um Regatten zu suchen'));
    }
    if (_results.isEmpty) {
      return Center(
        child: Text('Keine Regatten für PLZ ${_plzController.text.trim()} gefunden'),
      );
    }

    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final regatta = _results[index];
        final distance = totalDistanceNm(regatta.points);
        return Card(
          child: ListTile(
            leading: const Icon(Icons.flag),
            title: Text(regatta.name),
            subtitle: Text('${distance.toStringAsFixed(2)} sm'),
            trailing: ElevatedButton(
              onPressed: () => widget.onRegattaSelected(regatta),
              child: const Text('Laden'),
            ),
          ),
        );
      },
    );
  }
}
