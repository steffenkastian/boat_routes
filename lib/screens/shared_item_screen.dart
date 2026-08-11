import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../controllers/auth_controller.dart';
import '../controllers/route_annotations_controller.dart';
import '../models/boat_route.dart';
import '../models/shared_item.dart';
import '../models/tour.dart';
import '../models/tour_folder.dart';
import '../services/auth_service.dart';
import '../services/route_storage_service.dart';
import '../services/share_service.dart';
import '../services/tour_folder_storage_service.dart';
import '../services/tour_storage_service.dart';
import '../services/user_library_service.dart';
import '../utils/geo_utils.dart';
import '../widgets/route_map_view.dart';
import 'main_shell.dart';

// Read-only view of a route/Törn someone shared — either passed in already
// loaded (from the "Geteilt mit mir" list) or loaded by [shareId] (opened
// via a public share link, possibly while signed out).
class SharedItemScreen extends StatefulWidget {
  const SharedItemScreen({
    this.item,
    this.shareId,
    this.isAppRoot = false,
    super.key,
  }) : assert(item != null || shareId != null);

  final SharedItem? item;
  final String? shareId;
  // True when this screen is shown directly from a share link (app.dart),
  // i.e. there's no normal back navigation into the rest of the app —
  // shows a button to get there instead of leaving a dead end.
  final bool isAppRoot;

  @override
  State<SharedItemScreen> createState() => _SharedItemScreenState();
}

class _SharedItemScreenState extends State<SharedItemScreen> {
  final _shareService = ShareService();
  final _routeStorage = RouteStorageService();
  final _tourStorage = TourStorageService();
  final _folderStorage = TourFolderStorageService();
  final _userLibrary = UserLibraryService();
  final _auth = AuthController(AuthService());
  final _annotations = RouteAnnotationsController();

  SharedItem? _item;
  bool _loading = false;
  String? _error;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _annotations.addListener(_onAnnotationsChanged);
    final item = widget.item;
    if (item != null) {
      _item = item;
      _annotations.ensureIconsFor(_pointsOf(item));
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _annotations.removeListener(_onAnnotationsChanged);
    _annotations.dispose();
    _auth.dispose();
    super.dispose();
  }

  void _onAnnotationsChanged() => setState(() {});

  List<LatLng> _pointsOf(SharedItem item) => switch (item.type) {
        SharedItemType.route => item.toRoute().points,
        SharedItemType.tour => item.toTour().points,
        // Every day's track concatenated in order — one continuous line
        // covering the whole trip, same as "Gesamte Strecke anzeigen" in
        // TourFolderDetailScreen.
        SharedItemType.folder =>
          item.toFolderTours().expand((t) => t.points).toList(),
      };

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final item = await _shareService.loadShare(widget.shareId!);
      if (!mounted) return;
      if (item == null) {
        setState(() {
          _loading = false;
          _error = 'Dieser Link ist ungültig oder wurde entfernt.';
        });
        return;
      }
      setState(() {
        _item = item;
        _loading = false;
      });
      await _annotations.ensureIconsFor(_pointsOf(item));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Diese Freigabe konnte nicht geladen werden — falls sie nur an eine bestimmte E-Mail-Adresse geteilt wurde, logg dich mit diesem Konto ein.';
      });
    }
  }

  // Saves an independent copy into the current user's own local (and, if
  // signed in, cloud) library — not a reference to the shared item, which
  // stays whatever the owner shared and could change or be revoked later.
  Future<void> _saveToMyLibrary() async {
    final item = _item;
    if (item == null) return;
    // Not _auth.currentUser: AuthController may not have processed its
    // first authStateChanges event yet if this screen is the freshly
    // launched app root (opened directly from a share link) — that leaves
    // currentUser null even for an already-signed-in user whose session is
    // still being restored, silently skipping the cloud save below while
    // the UI still reports success.
    final user = await FirebaseAuth.instance.authStateChanges().first;
    if (!mounted) return;

    switch (item.type) {
      case SharedItemType.route:
        final route = BoatRoute(name: item.name, points: item.toRoute().points);
        await _routeStorage.addRoute(route);
        if (user != null) {
          try {
            await _userLibrary.addRoute(user.uid, route);
          } catch (_) {
            // Local copy already saved either way; cloud sync can catch
            // up on next login-triggered merge.
          }
        }
      case SharedItemType.tour:
        final sharedTour = item.toTour();
        final copy = Tour(
          name: sharedTour.name,
          points: sharedTour.points,
          startedAt: sharedTour.startedAt,
          endedAt: sharedTour.endedAt,
        );
        await _tourStorage.addTour(copy);
        if (user != null) {
          try {
            await _userLibrary.addTour(user.uid, copy);
          } catch (_) {}
        }
      case SharedItemType.folder:
        // Fresh ids throughout (not the shared copies' ids) — this becomes
        // an independent folder + Törns in the recipient's own library,
        // not a reference to the owner's.
        final copies = item.toFolderTours().map((t) => Tour(
              name: t.name,
              points: t.points,
              startedAt: t.startedAt,
              endedAt: t.endedAt,
            )).toList();
        for (final tour in copies) {
          await _tourStorage.addTour(tour);
        }
        final folder = TourFolder(
          name: item.name,
          tourIds: copies.map((t) => t.id).toList(),
        );
        await _folderStorage.addFolder(folder);
        if (user != null) {
          // Each tour uploaded independently (one failure shouldn't skip
          // the rest), and the cloud folder doc below only references the
          // ones that actually made it up — otherwise a partial failure
          // here would leave a cloud folder pointing at tour ids that
          // were never uploaded. The local copy (already saved above) is
          // unaffected either way; a future login-triggered sync will
          // offer to (re-)upload whatever's still local-only.
          final uploadedIds = <String>[];
          for (final tour in copies) {
            try {
              await _userLibrary.addTour(user.uid, tour);
              uploadedIds.add(tour.id);
            } catch (_) {}
          }
          try {
            await _userLibrary.addFolder(
              user.uid,
              folder.copyWith(tourIds: uploadedIds),
            );
          } catch (_) {}
        }
    }
    if (!mounted) return;
    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Zu deiner eigenen Liste hinzugefügt.')),
    );
  }

  String _typeLabel(SharedItemType type) => switch (type) {
        SharedItemType.route => 'Route',
        SharedItemType.tour => 'Törn',
        SharedItemType.folder => 'Ordner',
      };

  // Reachable directly from a share link (app.dart), with no normal back
  // navigation into the rest of the app in that case.
  Widget? _goToAppButton(BuildContext context) {
    if (!widget.isAppRoot) return null;
    return TextButton(
      onPressed: () => Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MainShell()),
      ),
      child: const Text('Zur App'),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Geteilt'),
          actions: [?_goToAppButton(context)],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final error = _error;
    if (error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Geteilt'),
          actions: [?_goToAppButton(context)],
        ),
        body: Center(
          child: Padding(padding: const EdgeInsets.all(24), child: Text(error)),
        ),
      );
    }

    final item = _item!;
    // Computed once and reused below (map points + day cards) rather than
    // re-parsing the whole tours list from JSON twice per build.
    final folderTours =
        item.type == SharedItemType.folder ? item.toFolderTours() : const <Tour>[];
    final points = item.type == SharedItemType.folder
        ? folderTours.expand((t) => t.points).toList()
        : _pointsOf(item);
    final initialCamera = CameraPosition(
      target:
          points.isNotEmpty ? points.first : const LatLng(54.382440, 11.145867),
      zoom: 12,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
        actions: [?_goToAppButton(context)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Geteilt von ${item.ownerEmail} · ${_typeLabel(item.type)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                FilledButton.icon(
                  onPressed: _saved ? null : _saveToMyLibrary,
                  icon: Icon(_saved ? Icons.check : Icons.download),
                  label: Text(_saved ? 'Übernommen' : 'Übernehmen'),
                ),
              ],
            ),
          ),
          if (item.type == SharedItemType.folder)
            SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: folderTours.asMap().entries.map((entry) {
                  final tour = entry.value;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Tag ${entry.key + 1}',
                              style: Theme.of(context).textTheme.labelLarge),
                          Text(tour.name),
                          Text(
                            '${totalDistanceNm(tour.points).toStringAsFixed(1)} sm',
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          Expanded(
            child: RouteMapView(
              initialCamera: initialCamera,
              points: points,
              showPointMarkers: false,
              onTap: (_) {},
              onMapCreated: (_) {},
              extraMarkers: _annotations.buildMarkers(points, idPrefix: 'shared'),
            ),
          ),
        ],
      ),
    );
  }
}
