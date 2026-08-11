import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../controllers/auth_controller.dart';
import '../controllers/route_annotations_controller.dart';
import '../models/boat_route.dart';
import '../models/shared_item.dart';
import '../models/tour.dart';
import '../services/auth_service.dart';
import '../services/route_storage_service.dart';
import '../services/share_service.dart';
import '../services/tour_storage_service.dart';
import '../services/user_library_service.dart';
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

  List<LatLng> _pointsOf(SharedItem item) => item.type == SharedItemType.route
      ? item.toRoute().points
      : item.toTour().points;

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

    if (item.type == SharedItemType.route) {
      final route = BoatRoute(name: item.name, points: item.toRoute().points);
      await _routeStorage.addRoute(route);
      if (user != null) {
        try {
          await _userLibrary.addRoute(user.uid, route);
        } catch (_) {
          // Local copy already saved either way; cloud sync can catch up
          // on next login-triggered merge.
        }
      }
    } else {
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
    }
    if (!mounted) return;
    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Zu deiner eigenen Liste hinzugefügt.')),
    );
  }

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
    final points = _pointsOf(item);
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
                    'Geteilt von ${item.ownerEmail}'
                    '${item.type == SharedItemType.route ? " · Route" : " · Törn"}',
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
