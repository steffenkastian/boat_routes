import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../controllers/auth_controller.dart';
import '../controllers/route_annotations_controller.dart';
import '../models/tour.dart';
import '../models/tour_folder.dart';
import '../services/auth_service.dart';
import '../services/share_service.dart';
import '../services/tour_folder_storage_service.dart';
import '../services/tour_storage_service.dart';
import '../services/user_library_service.dart';
import '../utils/geo_utils.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/prompt_name_dialog.dart';
import '../widgets/route_map_view.dart';
import '../widgets/share_dialog.dart';
import 'tour_detail_screen.dart';

// A folder groups several day-Törns (e.g. a multi-day sailing holiday) —
// shows the day list with per-day distance/duration and trip totals, a
// combined map of every day's track, and lets the whole trip be shared at
// once. Owns its own storage interactions rather than receiving live state
// from ToursScreen, which just reloads its folder list when this is popped.
class TourFolderDetailScreen extends StatefulWidget {
  const TourFolderDetailScreen({required this.folder, super.key});

  final TourFolder folder;

  @override
  State<TourFolderDetailScreen> createState() =>
      _TourFolderDetailScreenState();
}

class _TourFolderDetailScreenState extends State<TourFolderDetailScreen> {
  final _folderStorage = TourFolderStorageService();
  final _tourStorage = TourStorageService();
  final _userLibrary = UserLibraryService();
  final _shareService = ShareService();
  final _auth = AuthController(AuthService());

  late TourFolder _folder;
  List<Tour> _allTours = [];
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
    final tours = await _tourStorage.loadTours();
    if (!mounted) return;
    setState(() {
      _allTours = tours;
      _loading = false;
    });
  }

  // Folder tours in order, silently dropping any id that no longer
  // resolves to a saved Törn (e.g. it was deleted separately) rather than
  // crashing on a stale reference.
  List<Tour> get _dayTours => _folder.tourIds
      .map((id) {
        for (final t in _allTours) {
          if (t.id == id) return t;
        }
        return null;
      })
      .whereType<Tour>()
      .toList();

  Future<void> _persist(TourFolder updated) async {
    setState(() => _folder = updated);
    await _folderStorage.upsertFolder(updated);

    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        await _userLibrary.addFolder(uid, updated);
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

  Future<void> _addTour() async {
    final available =
        _allTours.where((t) => !_folder.tourIds.contains(t.id)).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alle gespeicherten Törns sind bereits in diesem Ordner.'),
        ),
      );
      return;
    }
    final chosen = await showDialog<Tour>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Törn hinzufügen'),
        children: available
            .map((t) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, t),
                  child: Text(t.name),
                ))
            .toList(),
      ),
    );
    if (chosen == null) return;
    await _persist(_folder.copyWith(tourIds: [..._folder.tourIds, chosen.id]));
  }

  Future<void> _removeTour(Tour tour) async {
    await _persist(_folder.copyWith(
      tourIds: _folder.tourIds.where((id) => id != tour.id).toList(),
    ));
  }

  Future<void> _deleteFolder() async {
    final confirmed = await confirmDialog(
      context,
      title: 'Ordner löschen?',
      message:
          '"${_folder.name}" wirklich löschen? Die enthaltenen Törns bleiben erhalten.',
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
    final dayTours = _dayTours;
    if (dayTours.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Der Ordner enthält noch keine Törns.')),
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
      createShare: ({String? email}) => _shareService.shareFolder(
        _folder.name,
        dayTours,
        ownerUid: user.uid,
        ownerEmail: user.email ?? '',
        sharedWithEmail: email,
      ),
    );
  }

  void _showCombinedMap() {
    final points = _dayTours.expand((t) => t.points).toList();
    if (points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine Streckendaten vorhanden.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            _CombinedRouteMapScreen(title: _folder.name, points: points),
      ),
    );
  }

  void _viewDayTour(Tour tour) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => TourDetailScreen(tour: tour)),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    return hours > 0 ? '${hours}h ${minutes}min' : '${minutes}min';
  }

  @override
  Widget build(BuildContext context) {
    final dayTours = _dayTours;
    final totalNm = dayTours.fold<double>(
      0, (sum, t) => sum + totalDistanceNm(t.points),
    );
    final totalDuration = dayTours.fold<Duration>(
      Duration.zero, (sum, t) => sum + t.endedAt.difference(t.startedAt),
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
                      '${dayTours.length} Tag(e) · ${totalNm.toStringAsFixed(1)} sm gesamt · ${_formatDuration(totalDuration)}',
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
                      child: dayTours.isEmpty
                          ? const Center(
                              child: Text('Noch keine Törns in diesem Ordner'),
                            )
                          : ListView.builder(
                              itemCount: dayTours.length,
                              itemBuilder: (context, index) {
                                final tour = dayTours[index];
                                final points = tour.points;
                                return ListTile(
                                  leading: CircleAvatar(child: Text('${index + 1}')),
                                  title: Text(tour.name),
                                  subtitle: Text(
                                    '${_formatDate(tour.startedAt)}  •  ${totalDistanceNm(points).toStringAsFixed(1)} sm  •  ${_formatDuration(tour.endedAt.difference(tour.startedAt))}',
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (value) {
                                      if (value == 'view') _viewDayTour(tour);
                                      if (value == 'remove') _removeTour(tour);
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
                        onPressed: _addTour,
                        icon: const Icon(Icons.add),
                        label: const Text('Törn hinzufügen'),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _CombinedRouteMapScreen extends StatefulWidget {
  const _CombinedRouteMapScreen({required this.title, required this.points});

  final String title;
  final List<LatLng> points;

  @override
  State<_CombinedRouteMapScreen> createState() =>
      _CombinedRouteMapScreenState();
}

class _CombinedRouteMapScreenState extends State<_CombinedRouteMapScreen> {
  final _annotations = RouteAnnotationsController();

  @override
  void initState() {
    super.initState();
    _annotations.addListener(_onChanged);
    _annotations.ensureIconsFor(widget.points);
  }

  @override
  void dispose() {
    _annotations.removeListener(_onChanged);
    _annotations.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: RouteMapView(
        initialCamera: CameraPosition(target: points.first, zoom: 11),
        points: points,
        showPointMarkers: false,
        onTap: (_) {},
        onMapCreated: (_) {},
        extraMarkers: _annotations.buildMarkers(points, idPrefix: 'folder'),
      ),
    );
  }
}
