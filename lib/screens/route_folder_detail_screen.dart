import 'package:flutter/material.dart';

import '../controllers/auth_controller.dart';
import '../models/boat_route.dart';
import '../models/route_folder.dart';
import '../services/auth_service.dart';
import '../services/route_folder_storage_service.dart';
import '../services/route_storage_service.dart';
import '../services/share_service.dart';
import '../services/user_library_service.dart';
import '../utils/geo_utils.dart';
import '../widgets/combined_route_map_screen.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/prompt_name_dialog.dart';
import '../widgets/share_dialog.dart';

// A folder groups several planned routes into one longer trip — shows the
// leg list with per-leg distance and trip totals, a combined map of every
// leg, and lets the whole trip be shared at once. Owns its own storage
// interactions rather than receiving live state from RoutePlannerScreen,
// which just reloads its folder list when this is popped.
class RouteFolderDetailScreen extends StatefulWidget {
  const RouteFolderDetailScreen({required this.folder, super.key});

  final RouteFolder folder;

  @override
  State<RouteFolderDetailScreen> createState() =>
      _RouteFolderDetailScreenState();
}

class _RouteFolderDetailScreenState extends State<RouteFolderDetailScreen> {
  final _folderStorage = RouteFolderStorageService();
  final _routeStorage = RouteStorageService();
  final _userLibrary = UserLibraryService();
  final _shareService = ShareService();
  final _auth = AuthController(AuthService());

  late RouteFolder _folder;
  List<BoatRoute> _allRoutes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _folder = widget.folder;
    _load();
  }

  @override
  void dispose() {
    _auth.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final routes = await _routeStorage.loadRoutes();
    if (!mounted) return;
    setState(() {
      _allRoutes = routes;
      _loading = false;
    });
  }

  // Folder legs in order, silently dropping any id that no longer resolves
  // to a saved route (e.g. it was deleted separately) rather than crashing
  // on a stale reference.
  List<BoatRoute> get _legs => _folder.routeIds
      .map((id) {
        for (final r in _allRoutes) {
          if (r.id == id) return r;
        }
        return null;
      })
      .whereType<BoatRoute>()
      .toList();

  Future<void> _persist(RouteFolder updated) async {
    setState(() => _folder = updated);
    await _folderStorage.upsertFolder(updated);

    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        await _userLibrary.addRouteFolder(uid, updated);
      } catch (_) {}
    }
  }

  Future<void> _renameFolder() async {
    final name = await promptForName(
      context,
      title: 'Ordner umbenennen',
      hint: _folder.name,
    );
    if (name == null) return;
    await _persist(_folder.copyWith(name: name));
  }

  Future<void> _addRoute() async {
    final available =
        _allRoutes.where((r) => !_folder.routeIds.contains(r.id)).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alle gespeicherten Routen sind bereits in diesem Ordner.'),
        ),
      );
      return;
    }
    final chosen = await showDialog<BoatRoute>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Route hinzufügen'),
        children: available
            .map((r) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, r),
                  child: Text(r.name),
                ))
            .toList(),
      ),
    );
    if (chosen == null) return;
    await _persist(_folder.copyWith(routeIds: [..._folder.routeIds, chosen.id]));
  }

  Future<void> _removeRoute(BoatRoute route) async {
    await _persist(_folder.copyWith(
      routeIds: _folder.routeIds.where((id) => id != route.id).toList(),
    ));
  }

  Future<void> _deleteFolder() async {
    final confirmed = await confirmDialog(
      context,
      title: 'Ordner löschen?',
      message:
          '"${_folder.name}" wirklich löschen? Die enthaltenen Routen bleiben erhalten.',
    );
    if (!confirmed || !mounted) return;

    await _folderStorage.deleteFolder(_folder.id);
    // No cloud delete call exists (UserLibraryService only ever upserts) —
    // acceptable here since the next login-merge simply re-offers it if
    // the cloud copy is still there; a real "delete everywhere" would need
    // a dedicated removal API, out of scope for this pass.
    if (mounted) Navigator.pop(context);
  }

  Future<void> _shareFolder() async {
    final legs = _legs;
    if (legs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Der Ordner enthält noch keine Routen.')),
      );
      return;
    }
    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zum Teilen bitte zuerst einloggen.')),
      );
      return;
    }
    await showShareDialog(
      context,
      createShare: ({String? email}) => _shareService.shareRouteFolder(
        _folder.name,
        legs,
        ownerUid: user.uid,
        ownerEmail: user.email ?? '',
        sharedWithEmail: email,
      ),
    );
  }

  void _showCombinedMap() {
    final legs = _legs.map((r) => r.points).toList();
    if (legs.every((leg) => leg.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine Streckendaten vorhanden.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CombinedRouteMapScreen(title: _folder.name, legs: legs),
      ),
    );
  }

  void _viewLeg(BoatRoute route) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CombinedRouteMapScreen(title: route.name, legs: [route.points]),
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final legs = _legs;
    final totalNm = legs.fold<double>(
      0, (sum, r) => sum + totalDistanceNm(r.points),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_folder.name),
        actions: [
          IconButton(
            tooltip: 'Umbenennen',
            icon: const Icon(Icons.edit),
            onPressed: _renameFolder,
          ),
          IconButton(
            tooltip: 'Teilen',
            icon: const Icon(Icons.share),
            onPressed: _shareFolder,
          ),
          IconButton(
            tooltip: 'Ordner löschen',
            icon: const Icon(Icons.delete),
            onPressed: _deleteFolder,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${legs.length} Etappe(n) · ${totalNm.toStringAsFixed(1)} sm gesamt',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showCombinedMap,
                        icon: const Icon(Icons.map),
                        label: const Text('Gesamte Strecke anzeigen'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: legs.isEmpty
                          ? const Center(
                              child: Text('Noch keine Routen in diesem Ordner'),
                            )
                          : ListView.builder(
                              itemCount: legs.length,
                              itemBuilder: (context, index) {
                                final route = legs[index];
                                final points = route.points;
                                return ListTile(
                                  leading: CircleAvatar(child: Text('${index + 1}')),
                                  title: Text(route.name),
                                  subtitle: Text(
                                    '${_formatDate(route.createdAt)}  •  ${totalDistanceNm(points).toStringAsFixed(1)} sm',
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (value) {
                                      if (value == 'view') _viewLeg(route);
                                      if (value == 'remove') _removeRoute(route);
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: 'view',
                                        child: Text('Route ansehen'),
                                      ),
                                      PopupMenuItem(
                                        value: 'remove',
                                        child: Text('Aus Ordner entfernen'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _addRoute,
                        icon: const Icon(Icons.add),
                        label: const Text('Route hinzufügen'),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
