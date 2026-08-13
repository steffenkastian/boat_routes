import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../config.dart';
import '../controllers/auth_controller.dart';
import '../controllers/live_location_controller.dart';
import '../controllers/mark_rounding_controller.dart';
import '../controllers/route_annotations_controller.dart';
import '../models/regatta.dart';
import '../models/tour.dart';
import '../models/tour_folder.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/regatta_storage_service.dart';
import '../services/share_service.dart';
import '../services/tour_folder_storage_service.dart';
import '../services/tour_notification_service.dart';
import '../services/tour_storage_service.dart';
import '../services/user_library_service.dart';
import '../utils/geo_utils.dart';
import '../utils/track_simplifier.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/hud_overlay.dart';
import '../widgets/map_layers_menu.dart';
import '../widgets/prompt_name_dialog.dart';
import '../widgets/route_map_view.dart';
import '../widgets/save_options_dialog.dart';
import '../widgets/share_dialog.dart';
import 'tour_detail_screen.dart';
import 'tour_folder_detail_screen.dart';

class ToursScreen extends StatefulWidget {
  const ToursScreen({
    this.referenceRoute,
    this.referenceRouteLabel,
    this.onEditRoute,
    this.onEditTour,
    this.tourListRefreshRequestId = 0,
    super.key,
  });

  // Points to show as a reference course while tracking — either a loaded
  // regatta or the currently drawn route from "Route planen".
  final List<LatLng>? referenceRoute;
  final String? referenceRouteLabel;
  // "Route bearbeiten" in the next-mark menu calls this (with the current
  // referenceRoute) to hand off to MainShell, which switches to Route
  // planen with those points loaded for editing.
  final ValueChanged<List<LatLng>>? onEditRoute;
  // TourFolderDetailScreen's "Törn bearbeiten" action calls this (threaded
  // through when this screen pushes that detail screen) to hand off to
  // MainShell, which switches to Route planen with that Tour's points
  // loaded and offers overwriting it in place there.
  final ValueChanged<Tour>? onEditTour;
  // Bumped by MainShell after a Tour was overwritten via the route
  // planner — reloads _savedTours since this screen, as an IndexedStack
  // sibling, otherwise never notices a change made on another tab.
  final int tourListRefreshRequestId;

  @override
  State<ToursScreen> createState() => _ToursScreenState();
}

class _ToursScreenState extends State<ToursScreen> {
  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(54.382440, 11.145867),
    zoom: 11,
  );

  final _tourStorage = TourStorageService();
  final _folderStorage = TourFolderStorageService();
  final _regattaStorage = RegattaStorageService();
  final _userLibrary = UserLibraryService();
  final _shareService = ShareService();
  final _location = LiveLocationController(LocationService());
  final _auth = AuthController(AuthService());
  final _referenceAnnotations = RouteAnnotationsController();
  final _tourNotification = TourNotificationService();
  DateTime? _lastNotificationUpdate;

  GoogleMapController? _mapController;
  List<Tour> _savedTours = [];
  List<TourFolder> _savedFolders = [];
  bool _isTracking = false;
  DateTime? _startedAt;
  bool _showSeaMarks = true;
  bool _showDepth = false;
  bool _showCourseAndDistance = true;
  bool _showArrows = true;
  String? _syncedForUid;
  // Awaited by _syncToursOnLogin() before it looks at _savedTours — the
  // initial SharedPreferences load and the Firebase auth-state event race
  // each other with no guaranteed order, so without this a login arriving
  // first would compute "local-only Törns" against a still-empty list and
  // never re-check once the load actually finishes.
  late final Future<void> _initialLoadTours;
  late final Future<void> _initialLoadFolders;
  MarkRoundingController? _markRounding;
  LatLng? _queriedPoint;
  bool _mapTapGuard = false;
  // "Routenplanung beenden" in the next-mark menu sets this false, which
  // hides the reference route's polyline/annotations and stops the
  // mark-rounding readout without touching the actual GPS tracking — a
  // newly loaded route (didUpdateWidget) resets it back to true.
  bool _followingReferenceRoute = true;

  // On Flutter web the GoogleMap platform view can receive a tap directly
  // (it isn't routed through Flutter's own widget hit-testing), so a tap
  // meant to dismiss a bottom sheet/marker info window, or tap the HUD, can
  // also reach the map underneath and set a new query point right there.
  void _guardNextMapTap() {
    _mapTapGuard = true;
    Future.delayed(const Duration(milliseconds: 400), () {
      _mapTapGuard = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _initialLoadTours = _loadTours();
    _initialLoadFolders = _loadFolders();
    _location.addListener(_onLocationChanged);
    // Started here rather than only in _startTour(): a GPS/fused-location
    // fix can take the better part of a minute to acquire from a cold
    // start (unlike the fast network-based fix Route planen gets), so
    // starting it the moment this screen opens gives it time to be ready
    // by the time "Törn starten" is actually tapped, instead of starting
    // that wait only then.
    _location.start();
    _auth.addListener(_onAuthChanged);
    _referenceAnnotations.addListener(_onAnnotationsChanged);
    _referenceAnnotations.ensureIconsFor(widget.referenceRoute ?? const []);
  }

  // List<LatLng> has no value equality of its own — comparing by `!=`
  // (identity) would treat "Route bearbeiten" → "Törn starten" without
  // any actual edit as a brand-new route (RoutePlannerScreen always
  // builds a fresh List for onStartTour), wiping already-rounded marks'
  // progress for no reason. LatLng itself does have value equality, so a
  // pairwise comparison is enough.
  bool _sameRoute(List<LatLng>? a, List<LatLng>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void didUpdateWidget(covariant ToursScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final route = widget.referenceRoute;
    if (!_sameRoute(route, oldWidget.referenceRoute)) {
      _referenceAnnotations.ensureIconsFor(route ?? const []);
      setState(() {
        // A freshly (re)loaded route is followed again by default, even
        // if "Routenplanung beenden" had previously turned this off for
        // the old one.
        _followingReferenceRoute = true;
        // Only touches mark-rounding progress while a Törn is actually
        // being tracked — outside of that, _markRounding is always null
        // and only _startTour() ever creates it. This is what makes
        // "Route bearbeiten" → edit in Route planen → "Törn starten"
        // update the *ongoing* Törn's reference route instead of
        // requiring it to be ended and restarted.
        if (_isTracking) {
          _markRounding = route != null && route.isNotEmpty
              ? MarkRoundingController(route)
              : null;
        }
      });
    }
    if (widget.tourListRefreshRequestId != oldWidget.tourListRefreshRequestId) {
      _loadTours();
    }
  }

  @override
  void dispose() {
    _location.removeListener(_onLocationChanged);
    _location.dispose();
    _auth.removeListener(_onAuthChanged);
    _auth.dispose();
    _referenceAnnotations.removeListener(_onAnnotationsChanged);
    _referenceAnnotations.dispose();
    if (_isTracking) {
      WakelockPlus.disable();
      _tourNotification.cancel();
    }
    super.dispose();
  }

  void _onLocationChanged() {
    final position = _location.currentPosition;
    if (_isTracking && position != null) {
      final here = LatLng(position.latitude, position.longitude);
      _markRounding?.updateWithPosition(here);
      _updateTourNotification(here);
    }
    setState(() {});
  }

  // Throttled to avoid re-posting on every single GPS fix (every few meters
  // while sailing) — geolocator's own "Törn läuft" notification can't be
  // updated after it starts, so this is a second, self-managed one just for
  // the live distance readout.
  void _updateTourNotification(LatLng here) {
    final now = DateTime.now();
    final last = _lastNotificationUpdate;
    if (last != null && now.difference(last) < const Duration(seconds: 15)) {
      return;
    }
    _lastNotificationUpdate = now;

    final remaining = _markRounding?.remainingDistanceNm(here);
    final text = remaining != null
        ? 'Verbleibend: ${remaining.toStringAsFixed(1)} sm'
        : 'Gefahren: ${totalDistanceNm(_location.track).toStringAsFixed(1)} sm';
    _tourNotification.showProgress(text);
  }
  void _onAnnotationsChanged() => setState(() {});

  void _onAuthChanged() {
    final uid = _auth.currentUser?.uid;
    if (uid != null && uid != _syncedForUid) {
      _syncedForUid = uid;
      _syncToursOnLogin(uid);
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

  // Same shape as _syncToursOnLogin, matched by id instead — folders don't
  // have a natural "same content" key like a Törn's start time, but their
  // id is already stable from creation (see TourFolder), so identity is
  // simpler and just as correct here.
  Future<void> _syncFoldersOnLogin(String uid) async {
    await _initialLoadFolders;
    if (!mounted) return;

    final cloudFolders = await _userLibrary.loadFolders(uid);
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
        await _userLibrary.addFolder(uid, folder);
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
      hint: 'z.B. Ostsee-Urlaub 2026',
    );
    if (name == null) return;

    final folder = TourFolder(name: name, tourIds: const []);
    await _folderStorage.addFolder(folder);
    if (!mounted) return;
    setState(() => _savedFolders.add(folder));

    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        await _userLibrary.addFolder(uid, folder);
      } catch (_) {}
    }
  }

  Future<void> _openFolder(TourFolder folder) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => TourFolderDetailScreen(
          folder: folder,
          onEditTour: widget.onEditTour,
        ),
      ),
    );
    // The detail screen manages its own storage (rename/add/remove Törns,
    // delete) — simplest to just reload rather than thread every possible
    // change back through a callback.
    if (mounted) _loadFolders();
  }

  // Merges in Törns saved to this account from any device — local storage
  // stays authoritative for offline/logged-out use, this just adds what
  // isn't already present (matched by start time, which is unique per Törn).
  // Then offers to push the other direction: Törns that were only ever
  // saved locally (e.g. recorded before this login, or while logged out)
  // aren't uploaded automatically, since that's a one-way action the user
  // should confirm.
  Future<void> _syncToursOnLogin(String uid) async {
    // Must resolve before touching _savedTours: this and the initial
    // SharedPreferences load race each other with no guaranteed order.
    await _initialLoadTours;
    if (!mounted) return;

    final cloudTours = await _userLibrary.loadTours(uid);
    if (!mounted) return;

    bool sameTour(Tour a, Tour b) => a.startedAt == b.startedAt;

    final newFromCloud = cloudTours
        .where((tour) => !_savedTours.any((t) => sameTour(t, tour)))
        .toList();
    if (newFromCloud.isNotEmpty) {
      setState(() => _savedTours.addAll(newFromCloud));
      // Without this, these entries would only exist in _savedTours —
      // renameTourAt()/deleteTourAt() index into the SharedPreferences
      // list, which would then be shorter and throw RangeError the moment
      // one of these merged-in Törns is renamed or deleted.
      for (final tour in newFromCloud) {
        await _tourStorage.addTour(tour);
      }
    }

    final localOnly = _savedTours
        .where((t) => !cloudTours.any((c) => sameTour(c, t)))
        .toList();
    if (localOnly.isEmpty || !mounted) return;

    final confirmed = await confirmDialog(
      context,
      title: 'Lokale Törns übernehmen?',
      message: localOnly.length == 1
          ? 'Du hast 1 lokal gespeicherten Törn, der noch nicht in deinem Account ist. Soll er übernommen werden?'
          : 'Du hast ${localOnly.length} lokal gespeicherte Törns, die noch nicht in deinem Account sind. Sollen sie übernommen werden?',
      confirmLabel: 'Übernehmen',
    );
    if (!confirmed) return;

    var failures = 0;
    for (final tour in localOnly) {
      try {
        await _userLibrary.addTour(uid, tour);
      } catch (_) {
        failures++;
      }
    }
    if (!mounted || failures == 0) return;
    final message = failures == 1
        ? '1 Törn konnte nicht übernommen werden.'
        : '$failures Törns konnten nicht übernommen werden.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _loadTours() async {
    final tours = await _tourStorage.loadTours();
    if (!mounted) return;
    setState(() => _savedTours = tours);
  }

  Future<void> _startTour() async {
    final route = widget.referenceRoute;
    setState(() {
      _isTracking = true;
      _startedAt = DateTime.now();
      _queriedPoint = null;
      // Otherwise a "Routenplanung beenden" from a previous Törn (against
      // the same, unchanged reference route — didUpdateWidget only fires
      // on a reference route *change*) would silently carry over and
      // start this new Törn with route-following already off.
      _followingReferenceRoute = true;
      _markRounding = route != null && route.isNotEmpty
          ? MarkRoundingController(route)
          : null;
    });
    _location.startRecording();
    _lastNotificationUpdate = null;

    // On Android this requests the separate "always" (background) location
    // tier — a no-op everywhere else — and has to happen *before*
    // start() below: it shows a system permission dialog that briefly
    // pauses the Activity, and doing that while start()'s fused-location
    // request is still settling silently drops it, so no fixes ever
    // arrive afterwards. Foreground tracking still works fine if this is
    // denied, so it doesn't block on the result.
    if (!await _location.ensureBackgroundPermission() && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Standort im Hintergrund nicht erlaubt — Tracking pausiert, sobald der Bildschirm gesperrt wird.',
          ),
        ),
      );
    }
    // Same reasoning as above — requested before start() so the permission
    // dialog can't interrupt the in-flight location request. Without this
    // granted (Android 13+), the foreground-service notification and the
    // live-distance one below both still get created but are never shown —
    // tracking itself still works either way.
    await _location.ensureNotificationPermission();

    // Upgrades to Android's foreground-service mode now that a Törn is
    // actually being tracked — this is what shows the "Törn läuft"
    // notification and survives a screen lock, unlike the plain stream
    // that's been running since initState() (which pre-warms the GPS lock
    // without a service/notification). Restarting the stream here doesn't
    // repeat the up-to-a-minute cold-start wait: the underlying GPS/GNSS
    // receiver stays warm across the restart, only the Dart-level
    // subscription is new.
    await _location.start(background: true);

    // True background tracking (screen off, browser tab backgrounded) isn't
    // achievable for a web app — mobile browsers throttle/suspend
    // geolocation once the screen locks. Keeping the screen awake is the
    // practical equivalent, and also avoids the GPS jump that tends to
    // happen right as the stream is suspended/resumed around a lock.
    await WakelockPlus.enable();
  }

  Future<void> _endTour() async {
    final points = _location.stopRecording();
    final startedAt = _startedAt;
    setState(() {
      _isTracking = false;
      _markRounding = null;
      _queriedPoint = null;
    });
    await _tourNotification.cancel();
    // Downgrades back out of foreground-service mode — otherwise the
    // "Törn läuft" notification and background service would keep running
    // indefinitely after tracking has actually stopped.
    await _location.start();
    await WakelockPlus.disable();
    if (!mounted) return;
    if (points.isEmpty || startedAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Keine Positionsdaten aufgezeichnet – Törn wurde nicht gespeichert.',
          ),
        ),
      );
      return;
    }

    final options = await promptForSaveOptions(
      context,
      title: 'Törnname eingeben',
      hint: 'z.B. Wochenendtörn',
      canPublishAsRegatta: _auth.isAdmin,
    );
    if (options == null) return;

    // Cuts a long recorded track down to far fewer points before it's ever
    // persisted — see track_simplifier.dart. A multi-hour Törn can
    // otherwise accumulate thousands of points that get stored three times
    // over (locally, in the cloud, in every share) and redrawn on every
    // map render.
    final simplifiedPoints = simplifyTrack(
      points,
      toleranceMeters: TrackSimplificationConfig.toleranceMeters,
    );

    final tour = Tour(
      name: options.name,
      points: simplifiedPoints,
      startedAt: startedAt,
      endedAt: DateTime.now(),
    );
    await _tourStorage.addTour(tour);
    setState(() => _savedTours.add(tour));

    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      await _userLibrary.addTour(uid, tour);
    }

    if (options.publishAsRegatta) {
      await _regattaStorage.addRegatta(Regatta(
        name: options.name,
        plz: options.plz!,
        points: simplifiedPoints,
        createdAt: DateTime.now(),
      ));
    }
  }

  Future<void> _shareTour(Tour tour) async {
    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zum Teilen bitte zuerst einloggen.')),
      );
      return;
    }
    await showShareDialog(
      context,
      createShare: ({String? email}) => _shareService.shareTour(
        tour,
        ownerUid: user.uid,
        ownerEmail: user.email ?? '',
        sharedWithEmail: email,
      ),
    );
  }

  Future<void> _deleteTour(int index) async {
    final tour = _savedTours[index];
    final confirmed = await confirmDialog(
      context,
      title: 'Törn löschen?',
      message: '"${tour.name}" wirklich löschen?',
    );
    if (!confirmed) return;

    await _tourStorage.deleteTourAt(index);
    setState(() => _savedTours.removeAt(index));
    await _removeTourFromAllFolders(tour.id);
  }

  // Without this, a deleted Törn's id lingers forever in any folder's
  // tourIds — TourFolderDetailScreen's day list already tolerates that
  // (silently filters out ids that no longer resolve to a saved Törn), but
  // the folder chip's "(N)" count on this screen would stay stale, and the
  // dangling id would sit in local storage and any synced cloud copy with
  // no other cleanup path.
  Future<void> _removeTourFromAllFolders(String tourId) async {
    final affected =
        _savedFolders.where((f) => f.tourIds.contains(tourId)).toList();
    if (affected.isEmpty) return;

    final updated = <TourFolder>[];
    for (final folder in affected) {
      final next = folder.copyWith(
        tourIds: folder.tourIds.where((id) => id != tourId).toList(),
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
          await _userLibrary.addFolder(uid, folder);
        } catch (_) {}
      }
    }
  }

  Future<void> _renameTour(int index) async {
    final tour = _savedTours[index];
    final newName = await promptForName(
      context,
      title: 'Törn umbenennen',
      hint: tour.name,
    );
    if (newName == null) return;

    await _tourStorage.renameTourAt(index, newName);
    final renamed = Tour(
      // Without this, renaming would mint a fresh id on every rename
      // (the id ?? generateLocalId() fallback in Tour's constructor),
      // breaking any existing share link/cloud copy tied to the old one.
      id: tour.id,
      name: newName,
      points: tour.points,
      startedAt: tour.startedAt,
      endedAt: tour.endedAt,
    );
    setState(() => _savedTours[index] = renamed);

    // Re-upload under the same id (an upsert — see UserLibraryService) so
    // the cloud copy, and any other device signed into this account,
    // picks up the new name too. Without this, sameTour()'s startedAt-only
    // match in _syncToursOnLogin would keep treating the stale cloud copy
    // as already present and never correct it.
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        await _userLibrary.addTour(uid, renamed);
      } catch (_) {}
    }
  }

  void _handleTrackingTap(LatLng position) {
    if (_mapTapGuard) return;
    setState(() => _queriedPoint = position);
  }

  // Tapping the next-mark marker while tracking a Törn against a loaded
  // route — GPS tracking itself is untouched by any of these three
  // actions, only the reference-route/mark-rounding guidance is affected.
  Future<void> _showMarkMenu() async {
    // Guards the *opening* tap too: unlike the marker (protected by its
    // own consumeTapEvents), the next-mark info Card is a plain widget
    // stacked over the map, and on Flutter web the GoogleMap platform view
    // can receive that same tap directly underneath it.
    _guardNextMapTap();
    final action = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Nächste Tonne'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'skip'),
            child: const Text('Tonne überspringen'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'edit'),
            child: const Text('Route bearbeiten'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'end'),
            child: const Text('Routenplanung beenden'),
          ),
        ],
      ),
    );
    // Guards against the dialog-dismissing tap also reaching the map
    // underneath — same reasoning as showMapLayersMenu's .then(...).
    _guardNextMapTap();
    if (!mounted || action == null) return;

    switch (action) {
      case 'skip':
        setState(() => _markRounding?.skipCurrentTarget());
      case 'edit':
        final route = widget.referenceRoute;
        if (route != null) widget.onEditRoute?.call(route);
      case 'end':
        setState(() {
          _followingReferenceRoute = false;
          // Also drops mark-rounding progress itself (not just the
          // polyline/annotations), since _nextMarkInfoText and the
          // background-tracking notification both read _markRounding
          // directly — leaving it alive would keep showing "Nächste
          // Tonne: …" even though route-following was just turned off.
          _markRounding = null;
        });
    }
  }

  String? get _nextMarkInfoText {
    final rounding = _markRounding;
    final position = _location.currentPosition;
    if (rounding == null || position == null) return null;
    if (rounding.isFinished) return 'Alle Tonnen gerundet';

    final from = LatLng(position.latitude, position.longitude);
    final distance = rounding.distanceToTargetNm(from);
    final course = rounding.bearingToTarget(from);
    if (distance == null || course == null) return null;
    return 'Nächste Tonne: ${course.round()}°  •  ${distance.toStringAsFixed(2)} sm';
  }

  String? get _queriedPointInfoText {
    final point = _queriedPoint;
    final position = _location.currentPosition;
    if (point == null || position == null) return null;

    final from = LatLng(position.latitude, position.longitude);
    final course = bearing(from, point).round();
    final distance = distanceNm(from, point);
    return 'Kurs: $course°  •  Abstand: ${distance.toStringAsFixed(2)} sm';
  }

  void _viewTour(Tour tour) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => TourDetailScreen(tour: tour)),
    );
  }

  String _tourSubtitle(Tour tour) {
    final date = tour.startedAt;
    final dateText =
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    final distance = totalDistanceNm(tour.points);
    final duration = tour.endedAt.difference(tour.startedAt);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final durationText = hours > 0 ? '${hours}h ${minutes}min' : '${minutes}min';
    return '$dateText  •  ${distance.toStringAsFixed(2)} sm  •  $durationText';
  }

  @override
  Widget build(BuildContext context) {
    if (_isTracking) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Törn läuft'),
          actions: [
            IconButton(
              tooltip: 'Kartenebenen',
              icon: const Icon(Icons.layers),
              onPressed: () => showMapLayersMenu(
                context,
                showSeaMarks: _showSeaMarks,
                onSeaMarksChanged: (value) =>
                    setState(() => _showSeaMarks = value),
                showDepth: _showDepth,
                onDepthChanged: (value) => setState(() => _showDepth = value),
                showCourseAndDistance: _showCourseAndDistance,
                onCourseAndDistanceChanged: (value) =>
                    setState(() => _showCourseAndDistance = value),
                showArrows: _showArrows,
                onArrowsChanged: (value) => setState(() => _showArrows = value),
              ).then((_) => _guardNextMapTap()),
            ),
          ],
        ),
        body: Stack(
          children: [
            RouteMapView(
              initialCamera: _initialCamera,
              points: _location.track,
              showPointMarkers: false,
              onTap: _handleTrackingTap,
              onMapCreated: (controller) => _mapController = controller,
              extraMarkers: {
                if (_location.boatMarker case final marker?) marker,
                if (_followingReferenceRoute)
                  ..._referenceAnnotations.buildMarkers(
                    widget.referenceRoute ?? const [],
                    idPrefix: 'reference',
                    showCourseLabels: _showCourseAndDistance,
                    showArrows: _showArrows,
                  ),
                if (_followingReferenceRoute)
                  if (_markRounding?.currentTarget case final target?)
                    Marker(
                      markerId: const MarkerId('next_mark'),
                      position: target,
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueYellow,
                      ),
                      consumeTapEvents: true,
                      onTap: _showMarkMenu,
                    ),
                if (_queriedPoint case final point?)
                  Marker(
                    markerId: const MarkerId('queried_point'),
                    position: point,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueViolet,
                    ),
                    consumeTapEvents: true,
                  ),
              },
              referenceRoute:
                  _followingReferenceRoute ? widget.referenceRoute : null,
              showSeaMarks: _showSeaMarks,
              showDepth: _showDepth,
            ),
            HudOverlay(
              speedKnots: _location.speedKnots,
              headingDegrees: _location.displayedHeading,
              statusMessage: _location.statusMessage,
              onTap: () {
                _guardNextMapTap();
                final position = _location.currentPosition;
                if (position == null) return;
                _mapController?.animateCamera(
                  CameraUpdate.newLatLngZoom(
                    LatLng(position.latitude, position.longitude),
                    15,
                  ),
                );
              },
            ),
            if (_nextMarkInfoText case final text?)
              Positioned(
                right: 8,
                top: 8,
                // Same menu as tapping the next-mark marker itself — this
                // card is often easier to hit than the marker, especially
                // when it's off-screen or overlapping other markers.
                child: GestureDetector(
                  onTap: _showMarkMenu,
                  child: Card(
                    color: Colors.black.withValues(alpha: 0.6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: Text(
                        text,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ),
            if (_queriedPointInfoText case final text?)
              Positioned(
                right: 8,
                top: 56,
                child: Card(
                  color: Colors.black.withValues(alpha: 0.6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.white, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            // Same tap-passthrough hazard as the next-mark
                            // Card: on Flutter web this tap can also reach
                            // the map underneath and immediately set a new
                            // _queriedPoint right as this one clears.
                            _guardNextMapTap();
                            setState(() => _queriedPoint = null);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: ElevatedButton(
                onPressed: _endTour,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Törn beenden'),
              ),
            ),
          ],
        ),
      );
    }

    // Törns that belong to a folder are shown there instead — hidden here
    // rather than listed twice. The (originalIndex, tour) pairing is
    // load-bearing: _renameTour/_deleteTour index into _savedTours (and,
    // via TourStorageService, the same position in the underlying
    // SharedPreferences list), so the builder below must keep using
    // entry.key, not its own iteration index, once the list is filtered.
    final folderTourIds = _savedFolders.expand((f) => f.tourIds).toSet();
    final visibleTours = _savedTours
        .asMap()
        .entries
        .where((e) => !folderTourIds.contains(e.value.id))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Törns ansehen')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (widget.referenceRoute != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.flag),
                  title: Text(
                    widget.referenceRouteLabel != null
                        ? 'Geladen: ${widget.referenceRouteLabel}'
                        : 'Route geladen',
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _startTour,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Törn starten'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Ordner', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: 'Ordner erstellen',
                  icon: const Icon(Icons.create_new_folder),
                  onPressed: _createFolder,
                ),
              ],
            ),
            if (_savedFolders.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'z.B. für einen Urlaub aus mehreren Tagestörns',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
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
                        label: Text('${folder.name} (${folder.tourIds.length})'),
                        onPressed: () => _openFolder(folder),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
            Expanded(
              child: visibleTours.isEmpty
                  ? const Center(child: Text('Noch keine Törns gespeichert'))
                  : ListView.builder(
                      itemCount: visibleTours.length,
                      itemBuilder: (context, i) {
                        final entry = visibleTours[i];
                        final index = entry.key;
                        final tour = entry.value;
                        return ListTile(
                          leading: const Icon(Icons.directions_boat),
                          title: Text(tour.name),
                          subtitle: Text(_tourSubtitle(tour)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Route ansehen',
                                icon: const Icon(Icons.map),
                                onPressed: () => _viewTour(tour),
                              ),
                              IconButton(
                                tooltip: 'Teilen',
                                icon: const Icon(Icons.share),
                                onPressed: () => _shareTour(tour),
                              ),
                              IconButton(
                                tooltip: 'Umbenennen',
                                icon: const Icon(Icons.edit),
                                onPressed: () => _renameTour(index),
                              ),
                              IconButton(
                                tooltip: 'Löschen',
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteTour(index),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
