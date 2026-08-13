import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../controllers/auth_controller.dart';
import '../controllers/live_location_controller.dart';
import '../models/boat_route.dart';
import '../models/regatta.dart';
import '../models/route_folder.dart';
import '../models/tour.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/regatta_storage_service.dart';
import '../services/route_folder_storage_service.dart';
import '../services/route_storage_service.dart';
import '../services/share_service.dart';
import '../services/tour_storage_service.dart';
import '../services/user_library_service.dart';
import '../utils/geo_utils.dart';
import '../utils/marker_icon_factory.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/hud_overlay.dart';
import '../widgets/map_layers_menu.dart';
import '../widgets/prompt_name_dialog.dart';
import '../widgets/route_map_view.dart';
import '../widgets/route_points_panel.dart';
import '../widgets/save_options_dialog.dart';
import '../widgets/saved_routes_panel.dart';
import '../widgets/share_dialog.dart';
import 'route_folder_detail_screen.dart';

class RoutePlannerScreen extends StatefulWidget {
  const RoutePlannerScreen({
    required this.onStartTour,
    this.externalRoute,
    this.externalRouteRequestId = 0,
    this.externalTourToEdit,
    this.externalTourEditRequestId = 0,
    this.onTourUpdated,
    super.key,
  });

  final ValueChanged<List<LatLng>> onStartTour;
  // Set by MainShell when the user taps "Route bearbeiten" while tracking a
  // Törn (see ToursScreen) — loads these points into the canvas here for
  // editing, same as picking a saved route would.
  final List<LatLng>? externalRoute;
  // Incremented on every "Route bearbeiten" tap, even ones that hand over
  // the exact same route again — didUpdateWidget below reloads on this
  // changing rather than on externalRoute itself, since two consecutive
  // taps would otherwise pass an unchanged list reference and silently do
  // nothing the second time.
  final int externalRouteRequestId;
  // Set by MainShell when the user taps "Törn bearbeiten" on a saved Törn
  // (see TourFolderDetailScreen) — loads that Tour's points into the canvas
  // and offers overwriting it in place once edited, unlike externalRoute
  // above (a plain point list with no "save back to X" identity).
  final Tour? externalTourToEdit;
  // Same reload-trigger role as externalRouteRequestId, for
  // externalTourToEdit.
  final int externalTourEditRequestId;
  // Called after successfully overwriting externalTourToEdit's points —
  // lets MainShell tell ToursScreen (an IndexedStack sibling that
  // otherwise never notices this) to reload its list.
  final ValueChanged<Tour>? onTourUpdated;

  @override
  State<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends State<RoutePlannerScreen> {
  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(54.382440, 11.145867),
    zoom: 11,
  );

  final _routeStorage = RouteStorageService();
  final _folderStorage = RouteFolderStorageService();
  final _tourStorage = TourStorageService();
  final _regattaStorage = RegattaStorageService();
  final _userLibrary = UserLibraryService();
  final _shareService = ShareService();
  final _location = LiveLocationController(LocationService());
  final _auth = AuthController(AuthService());

  final List<LatLng> _points = [];
  GoogleMapController? _mapController;
  List<BoatRoute> _savedRoutes = [];
  List<RouteFolder> _savedFolders = [];
  // The Tour currently loaded via "Törn bearbeiten", if any — offers
  // overwriting it in place instead of only saving the canvas as a new
  // route. Cleared whenever the canvas is repurposed for something else
  // (a new route, a different saved route loaded, ...).
  Tour? _editingTour;
  bool _addingEnabled = true;
  bool _hasAutoCenteredOnLocation = false;
  bool _mapTapGuard = false;
  bool _showSeaMarks = true;
  bool _showDepth = false;
  bool _showCourseAndDistance = true;
  String? _syncedForUid;
  // Awaited by _syncRoutesOnLogin() before it looks at _savedRoutes — the
  // initial SharedPreferences load and the Firebase auth-state event race
  // each other with no guaranteed order, so without this a login arriving
  // first would compute "local-only routes" against a still-empty list and
  // never re-check once the load actually finishes.
  late final Future<void> _initialLoadRoutes;
  late final Future<void> _initialLoadFolders;

  final Map<String, BitmapDescriptor> _courseLabelIcons = {};
  final Map<int, BitmapDescriptor> _pointNumberIcons = {};

  @override
  void initState() {
    super.initState();
    _initialLoadRoutes = _loadRoutes();
    _initialLoadFolders = _loadFolders();
    _location.addListener(_onLocationChanged);
    _location.start();
    _auth.addListener(_onAuthChanged);
  }

  @override
  void didUpdateWidget(covariant RoutePlannerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final external = widget.externalRoute;
    if (external != null &&
        widget.externalRouteRequestId != oldWidget.externalRouteRequestId) {
      setState(() {
        _points
          ..clear()
          ..addAll(external);
        _editingTour = null;
      });
      _ensureMarkerIcons();
    }

    final tourToEdit = widget.externalTourToEdit;
    if (tourToEdit != null &&
        widget.externalTourEditRequestId != oldWidget.externalTourEditRequestId) {
      setState(() {
        _points
          ..clear()
          ..addAll(tourToEdit.points);
        _editingTour = tourToEdit;
      });
      _ensureMarkerIcons();
    }
  }

  @override
  void dispose() {
    _location.removeListener(_onLocationChanged);
    _location.dispose();
    _auth.removeListener(_onAuthChanged);
    _auth.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    final uid = _auth.currentUser?.uid;
    if (uid != null && uid != _syncedForUid) {
      _syncedForUid = uid;
      _syncRoutesOnLogin(uid);
      _syncFoldersOnLogin(uid);
    } else if (uid == null) {
      _syncedForUid = null;
    }
    setState(() {});
  }

  Future<void> _loadFolders() async {
    final folders = await _folderStorage.loadFolders();
    if (!mounted) return;
    setState(() => _savedFolders = folders);
  }

  // Same shape as _syncRoutesOnLogin, matched by id instead — folders don't
  // have a natural "same content" key like a route's created time, but
  // their id is already stable from creation (see RouteFolder), so identity
  // is simpler and just as correct here.
  Future<void> _syncFoldersOnLogin(String uid) async {
    await _initialLoadFolders;
    if (!mounted) return;

    final cloudFolders = await _userLibrary.loadRouteFolders(uid);
    if (!mounted) return;

    final newFromCloud = cloudFolders
        .where((f) => !_savedFolders.any((sf) => sf.id == f.id))
        .toList();
    if (newFromCloud.isNotEmpty) {
      setState(() => _savedFolders.addAll(newFromCloud));
      for (final folder in newFromCloud) {
        await _folderStorage.addFolder(folder);
      }
    }

    final localOnly = _savedFolders
        .where((f) => !cloudFolders.any((cf) => cf.id == f.id))
        .toList();
    if (localOnly.isEmpty || !mounted) return;

    final confirmed = await confirmDialog(
      context,
      title: 'Lokale Ordner übernehmen?',
      message: localOnly.length == 1
          ? 'Du hast 1 lokal gespeicherten Ordner, der noch nicht in deinem Account ist. Soll er übernommen werden?'
          : 'Du hast ${localOnly.length} lokal gespeicherte Ordner, die noch nicht in deinem Account sind. Sollen sie übernommen werden?',
      confirmLabel: 'Übernehmen',
    );
    if (!confirmed) return;

    var failures = 0;
    for (final folder in localOnly) {
      try {
        await _userLibrary.addRouteFolder(uid, folder);
      } catch (_) {
        failures++;
      }
    }
    if (!mounted || failures == 0) return;
    final message = failures == 1
        ? '1 Ordner konnte nicht übernommen werden.'
        : '$failures Ordner konnten nicht übernommen werden.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createFolder() async {
    final name = await promptForName(
      context,
      title: 'Ordner erstellen',
      hint: 'z.B. Ostsee-Segeltörn',
    );
    if (name == null) return;

    final folder = RouteFolder(name: name, routeIds: const []);
    await _folderStorage.addFolder(folder);
    if (!mounted) return;
    setState(() => _savedFolders.add(folder));

    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        await _userLibrary.addRouteFolder(uid, folder);
      } catch (_) {}
    }
  }

  Future<void> _openFolder(RouteFolder folder) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => RouteFolderDetailScreen(folder: folder),
      ),
    );
    // The detail screen manages its own storage (rename/add/remove routes,
    // delete) — simplest to just reload rather than thread every possible
    // change back through a callback.
    if (mounted) _loadFolders();
  }

  // Without this, a deleted route's id lingers forever in any folder's
  // routeIds — RouteFolderDetailScreen's leg list already tolerates that
  // (silently filters out ids that no longer resolve to a saved route), but
  // the folder chip's "(N)" count on this screen would stay stale, and the
  // dangling id would sit in local storage and any synced cloud copy with
  // no other cleanup path.
  Future<void> _removeRouteFromAllFolders(String routeId) async {
    final affected =
        _savedFolders.where((f) => f.routeIds.contains(routeId)).toList();
    if (affected.isEmpty) return;

    final updated = <RouteFolder>[];
    for (final folder in affected) {
      final next = folder.copyWith(
        routeIds: folder.routeIds.where((id) => id != routeId).toList(),
      );
      await _folderStorage.upsertFolder(next);
      updated.add(next);
    }
    if (!mounted) return;
    setState(() {
      for (final folder in updated) {
        final index = _savedFolders.indexWhere((f) => f.id == folder.id);
        if (index != -1) _savedFolders[index] = folder;
      }
    });

    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      for (final folder in updated) {
        try {
          await _userLibrary.addRouteFolder(uid, folder);
        } catch (_) {}
      }
    }
  }

  // Merges in routes saved to this account from any device — local storage
  // stays authoritative for offline/logged-out use, this just adds what
  // isn't already present (matched by name + save time). Then offers to
  // push the other direction: routes that were only ever saved locally
  // (e.g. created before this login, or while logged out) aren't uploaded
  // automatically, since that's a one-way action the user should confirm.
  Future<void> _syncRoutesOnLogin(String uid) async {
    // Must resolve before touching _savedRoutes: this and the initial
    // SharedPreferences load race each other with no guaranteed order.
    await _initialLoadRoutes;
    if (!mounted) return;

    final cloudRoutes = await _userLibrary.loadRoutes(uid);
    if (!mounted) return;

    bool sameRoute(BoatRoute a, BoatRoute b) =>
        a.name == b.name && a.createdAt == b.createdAt;

    final newFromCloud = cloudRoutes
        .where((route) => !_savedRoutes.any((r) => sameRoute(r, route)))
        .toList();
    if (newFromCloud.isNotEmpty) {
      setState(() => _savedRoutes.addAll(newFromCloud));
      // Without this, these entries would only exist in _savedRoutes —
      // deleteRouteAt() indexes into the SharedPreferences list, which
      // would then be shorter and throw RangeError the moment one of
      // these merged-in routes is deleted.
      for (final route in newFromCloud) {
        await _routeStorage.addRoute(route);
      }
    }

    final localOnly = _savedRoutes
        .where((r) => !cloudRoutes.any((c) => sameRoute(c, r)))
        .toList();
    if (localOnly.isEmpty || !mounted) return;

    final confirmed = await confirmDialog(
      context,
      title: 'Lokale Routen übernehmen?',
      message: localOnly.length == 1
          ? 'Du hast 1 lokal gespeicherte Route, die noch nicht in deinem Account ist. Soll sie übernommen werden?'
          : 'Du hast ${localOnly.length} lokal gespeicherte Routen, die noch nicht in deinem Account sind. Sollen sie übernommen werden?',
      confirmLabel: 'Übernehmen',
    );
    if (!confirmed) return;

    var failures = 0;
    for (final route in localOnly) {
      try {
        await _userLibrary.addRoute(uid, route);
      } catch (_) {
        failures++;
      }
    }
    if (!mounted || failures == 0) return;
    final message = failures == 1
        ? '1 Route konnte nicht übernommen werden.'
        : '$failures Routen konnten nicht übernommen werden.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _onLocationChanged() {
    if (!_hasAutoCenteredOnLocation && _location.currentPosition != null) {
      _centerOnPosition(_location.currentPosition!.latitude,
          _location.currentPosition!.longitude,
          animate: false);
    }
    setState(() {});
  }

  void _centerOnPosition(double lat, double lng, {bool animate = true}) {
    final controller = _mapController;
    if (controller == null) return;

    _hasAutoCenteredOnLocation = true;
    final target = CameraPosition(target: LatLng(lat, lng), zoom: 15);
    if (animate) {
      controller.animateCamera(CameraUpdate.newCameraPosition(target));
    } else {
      controller.moveCamera(CameraUpdate.newCameraPosition(target));
    }
  }

  // On Flutter web the GoogleMap platform view can receive a tap directly
  // (it isn't routed through Flutter's own widget hit-testing), so a tap
  // meant for the HUD button, or to dismiss a bottom sheet/dialog/marker
  // info window, can also reach the map underneath and add a route point.
  // Guard the next map tap for a brief window rather than trying to
  // geometrically detect the overlap, which proved unreliable.
  void _guardNextMapTap() {
    _mapTapGuard = true;
    Future.delayed(const Duration(milliseconds: 400), () {
      _mapTapGuard = false;
    });
  }

  void _jumpToCurrentLocation() {
    _guardNextMapTap();

    final position = _location.currentPosition;
    if (position == null) {
      // No fix yet (or permission was never granted) — retry from here,
      // inside a real user gesture, so the browser reliably shows its
      // location permission prompt.
      _location.start();
      return;
    }
    _centerOnPosition(position.latitude, position.longitude);
  }

  void _addPoint(LatLng position) {
    if (_mapTapGuard) return;
    setState(() {
      _points.add(position);
    });
    _ensureMarkerIcons();
  }

  void _handleMapTap(LatLng position) {
    if (!_addingEnabled) return;
    _addPoint(position);
  }

  void _removePoint(int index) {
    setState(() {
      _points.removeAt(index);
    });
    _ensureMarkerIcons();
  }

  void _reorderPoints(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    setState(() {
      final point = _points.removeAt(oldIndex);
      _points.insert(newIndex, point);
    });
    _ensureMarkerIcons();
  }

  Future<void> _ensureMarkerIcons() async {
    await Future.wait([
      _ensureCourseLabelIcons(),
      _ensurePointNumberIcons(),
    ]);
  }

  Future<void> _ensurePointNumberIcons() async {
    final missing = [
      for (var n = 1; n <= _points.length; n++)
        if (!_pointNumberIcons.containsKey(n)) n,
    ];
    if (missing.isEmpty) return;

    for (final n in missing) {
      _pointNumberIcons[n] = await buildNumberedDotIcon(n);
    }
    if (mounted) setState(() {});
  }

  void _showLayersMenu() {
    showMapLayersMenu(
      context,
      showSeaMarks: _showSeaMarks,
      onSeaMarksChanged: (value) => setState(() => _showSeaMarks = value),
      showDepth: _showDepth,
      onDepthChanged: (value) => setState(() => _showDepth = value),
      showCourseAndDistance: _showCourseAndDistance,
      onCourseAndDistanceChanged: (value) =>
          setState(() => _showCourseAndDistance = value),
    ).then((_) => _guardNextMapTap());
  }

  // Route segment course labels ("123°" over "2.3 sm") are drawn as map
  // markers, which on google_maps_flutter requires baking each distinct
  // label into a bitmap ahead of time. Generated lazily and cached by the
  // course+distance text so repeated segments (e.g. a beat back and forth)
  // reuse the same icon.
  String _courseLabelKey(LatLng from, LatLng to) =>
      '${bearing(from, to).round()}°|${distanceNm(from, to).toStringAsFixed(1)} sm';

  Future<void> _ensureCourseLabelIcons() async {
    final needed = <String>{
      for (var i = 1; i < _points.length; i++)
        _courseLabelKey(_points[i - 1], _points[i]),
    };
    final missing = needed.difference(_courseLabelIcons.keys.toSet());
    if (missing.isEmpty) return;

    for (final key in missing) {
      final parts = key.split('|');
      _courseLabelIcons[key] =
          await buildLabelIcon(parts[0], secondaryText: parts[1]);
    }
    if (mounted) setState(() {});
  }

  Set<Marker> _buildCourseLabelMarkers() {
    final markers = <Marker>{};
    for (var i = 1; i < _points.length; i++) {
      final from = _points[i - 1];
      final to = _points[i];
      final icon = _courseLabelIcons[_courseLabelKey(from, to)];
      if (icon == null) continue;

      markers.add(Marker(
        markerId: MarkerId('course_$i'),
        position: LatLng(
          (from.latitude + to.latitude) / 2,
          (from.longitude + to.longitude) / 2,
        ),
        icon: icon,
        anchor: const Offset(0.5, 0.5),
        consumeTapEvents: true,
      ));
    }
    return markers;
  }

  Future<void> _loadRoutes() async {
    final routes = await _routeStorage.loadRoutes();
    if (!mounted) return;
    setState(() {
      _savedRoutes = routes;
    });
  }

  void _loadRoute(BoatRoute route) {
    setState(() {
      _points
        ..clear()
        ..addAll(route.points);
      _editingTour = null;
    });
    _ensureMarkerIcons();
  }

  Future<void> _deleteRoute(BoatRoute route) async {
    final index = _savedRoutes.indexWhere((r) => r.id == route.id);
    if (index == -1) return;
    await _routeStorage.deleteRouteAt(index);
    setState(() {
      _savedRoutes.removeAt(index);
    });
    await _removeRouteFromAllFolders(route.id);
  }

  Future<void> _saveRoute() async {
    if (_points.isEmpty) return;

    setState(() => _addingEnabled = false);
    final options = await promptForSaveOptions(
      context,
      title: 'Routenname eingeben',
      hint: 'z.B. Ostseetörn',
      canPublishAsRegatta: _auth.isAdmin,
    );
    setState(() => _addingEnabled = true);
    // On Flutter web the GoogleMap platform view can receive the dialog's
    // closing tap directly (same hazard as _guardNextMapTap elsewhere) —
    // _addingEnabled alone doesn't cover the exact tap that dismisses the
    // dialog, since it flips back to true right as that tap lands.
    _guardNextMapTap();

    if (options == null) return;

    final points = List.of(_points);
    final newRoute = BoatRoute(name: options.name, points: points);
    await _routeStorage.addRoute(newRoute);
    setState(() {
      _savedRoutes.add(newRoute);
    });

    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        await _userLibrary.addRoute(uid, newRoute);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cloud-Sync fehlgeschlagen: $e')),
          );
        }
      }
    }

    if (options.publishAsRegatta) {
      await _regattaStorage.addRegatta(Regatta(
        name: options.name,
        plz: options.plz!,
        points: points,
        createdAt: DateTime.now(),
      ));
    }
  }

  // Overwrites _editingTour's points in place with whatever's currently
  // drawn — the "Törn bearbeiten" counterpart to _saveRoute, which always
  // creates a brand-new BoatRoute instead.
  Future<void> _overwriteTour() async {
    final tour = _editingTour;
    if (tour == null || _points.isEmpty) return;

    final confirmed = await confirmDialog(
      context,
      title: 'Törn aktualisieren?',
      message:
          '"${tour.name}" wird mit der aktuell gezeichneten Strecke überschrieben.',
      confirmLabel: 'Überschreiben',
    );
    if (!confirmed || !mounted) return;

    final updated = Tour(
      // Keeps the same id — see TourStorageService.upsertTour — so this
      // overwrites the existing entry (locally and in the cloud) instead
      // of creating a second one.
      id: tour.id,
      name: tour.name,
      points: List.of(_points),
      startedAt: tour.startedAt,
      endedAt: tour.endedAt,
    );
    await _tourStorage.upsertTour(updated);

    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        await _userLibrary.addTour(uid, updated);
      } catch (_) {}
    }

    widget.onTourUpdated?.call(updated);
    if (!mounted) return;
    setState(() => _editingTour = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Törn aktualisiert.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mapAndHud = Stack(
      children: [
        RouteMapView(
          initialCamera: _initialCamera,
          points: _points,
          onTap: _handleMapTap,
          onMapCreated: (controller) {
            _mapController = controller;
            final position = _location.currentPosition;
            if (position != null && !_hasAutoCenteredOnLocation) {
              _centerOnPosition(
                position.latitude,
                position.longitude,
                animate: false,
              );
            }
          },
          extraMarkers: {
            if (_showCourseAndDistance) ..._buildCourseLabelMarkers(),
            if (_location.boatMarker case final marker?) marker,
          },
          showSeaMarks: _showSeaMarks,
          showDepth: _showDepth,
          pointIcons: _pointNumberIcons,
        ),
        HudOverlay(
          speedKnots: _location.speedKnots,
          headingDegrees: _location.displayedHeading,
          statusMessage: _location.statusMessage,
          onTap: _jumpToCurrentLocation,
        ),
        if (_editingTour case final tour?)
          Positioned(
            left: 8,
            top: 8,
            child: Card(
              color: Colors.black.withValues(alpha: 0.6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Bearbeite Törn: ${tour.name}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => setState(() => _editingTour = null),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );

    final pointsPanel = RoutePointsPanel(
      points: _points,
      onRemovePoint: _removePoint,
      onAddPoint: _addPoint,
      onReorderPoints: _reorderPoints,
    );

    final appBarActions = [
      IconButton(
        tooltip: 'Gespeicherte Routen',
        icon: const Icon(Icons.folder_open),
        onPressed: _showSavedRoutes,
      ),
      IconButton(
        tooltip: 'Kartenebenen',
        icon: const Icon(Icons.layers),
        onPressed: _showLayersMenu,
      ),
      IconButton(
        tooltip: 'Törn starten',
        icon: const Icon(Icons.play_circle_outline),
        onPressed: _points.isEmpty
            ? null
            : () => widget.onStartTour(List.of(_points)),
      ),
      IconButton(
        tooltip: 'Neue Route',
        icon: const Icon(Icons.add),
        onPressed: () {
          setState(() {
            _points.clear();
            _editingTour = null;
          });
        },
      ),
      IconButton(
        tooltip: 'Als neue Route speichern',
        icon: const Icon(Icons.save),
        onPressed: _saveRoute,
      ),
      if (_editingTour != null)
        IconButton(
          tooltip: 'Törn aktualisieren',
          icon: const Icon(Icons.save_as),
          onPressed: _overwriteTour,
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // A short viewport (phone in landscape — plenty of width but very
        // little height) needs the map to dominate the screen; the points
        // panel moves into a Drawer (opened via the AppBar's automatic
        // hamburger icon) instead of a permanent side column. Checked first
        // since a landscape phone can easily be wider than the portrait
        // breakpoint below.
        if (constraints.maxHeight < 500) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Routenplaner mit Standort'),
              actions: appBarActions,
            ),
            drawer: Drawer(child: SafeArea(child: pointsPanel)),
            body: mapAndHud,
          );
        }

        final Widget body;
        // Narrow (portrait phone) screens stack everything vertically — a
        // side-by-side points panel would be squeezed to a sliver too
        // narrow for its coordinate-entry row and drag handles.
        if (constraints.maxWidth < 700) {
          body = Column(
            children: [
              Expanded(flex: 5, child: mapAndHud),
              Expanded(flex: 7, child: pointsPanel),
            ],
          );
        } else {
          body = Row(
            children: [
              Expanded(flex: 3, child: mapAndHud),
              Expanded(flex: 1, child: pointsPanel),
            ],
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Routenplaner mit Standort'),
            actions: appBarActions,
          ),
          body: body,
        );
      },
    );
  }

  void _showSavedRoutes() {
    // Locks map-tap-to-add-point for the whole time this sheet (and any
    // dialog nested inside it, e.g. the "Ordner erstellen" name prompt) is
    // open — on Flutter web the GoogleMap platform view can otherwise
    // receive taps meant for the sheet/dialog directly, silently adding
    // stray points underneath.
    setState(() => _addingEnabled = false);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          // Routes that belong to a folder are shown there instead — hidden
          // here rather than listed twice.
          final folderRouteIds =
              _savedFolders.expand((f) => f.routeIds).toSet();
          final visibleRoutes = _savedRoutes
              .where((r) => !folderRouteIds.contains(r.id))
              .toList();

          return FractionallySizedBox(
            heightFactor: 0.7,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('Ordner', style: Theme.of(context).textTheme.titleMedium),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Ordner erstellen',
                          icon: const Icon(Icons.create_new_folder),
                          onPressed: () async {
                            await _createFolder();
                            setSheetState(() {});
                          },
                        ),
                      ],
                    ),
                    if (_savedFolders.isEmpty)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'z.B. um mehrere Routen zu einem Törn zu kombinieren',
                            style: TextStyle(color: Colors.black54, fontSize: 12),
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        height: 40,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _savedFolders.length,
                          itemBuilder: (context, index) {
                            final folder = _savedFolders[index];
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(
                                avatar: const Icon(Icons.folder, size: 18),
                                label: Text(
                                    '${folder.name} (${folder.routeIds.length})'),
                                onPressed: () {
                                  Navigator.pop(context);
                                  _openFolder(folder);
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: SavedRoutesPanel(
                        routes: visibleRoutes,
                        onLoad: (route) {
                          Navigator.pop(context);
                          _loadRoute(route);
                        },
                        onDelete: (route) async {
                          await _deleteRoute(route);
                          setSheetState(() {});
                        },
                        onShare: _shareRoute,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ).then((_) {
      setState(() => _addingEnabled = true);
      _guardNextMapTap();
    });
  }

  Future<void> _shareRoute(BoatRoute route) async {
    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zum Teilen bitte zuerst einloggen.')),
      );
      return;
    }
    await showShareDialog(
      context,
      createShare: ({String? email}) => _shareService.shareRoute(
        route,
        ownerUid: user.uid,
        ownerEmail: user.email ?? '',
        sharedWithEmail: email,
      ),
    );
  }
}
