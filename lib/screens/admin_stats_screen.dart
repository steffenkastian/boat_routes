import 'package:flutter/material.dart';

import '../services/auth_service.dart';

// Admin-only screen (see ProfileScreen's gating) showing how many users are
// registered — the simplest useful "background statistic" without standing
// up dedicated analytics infrastructure.
class AdminStatsScreen extends StatefulWidget {
  const AdminStatsScreen({super.key});

  @override
  State<AdminStatsScreen> createState() => _AdminStatsScreenState();
}

class _AdminStatsScreenState extends State<AdminStatsScreen> {
  final _authService = AuthService();
  int? _userCount;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final count = await _authService.fetchUserCount();
      if (!mounted) return;
      setState(() {
        _userCount = count;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Statistik konnte nicht geladen werden.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistik'),
        actions: [
          IconButton(
            tooltip: 'Aktualisieren',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : _error != null
                ? Text(_error!)
                : Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${_userCount ?? 0}',
                            style: Theme.of(context).textTheme.displayMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text('Registrierte Nutzer'),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}
