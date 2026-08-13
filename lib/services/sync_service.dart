import 'route_folder_storage_service.dart';
import 'route_storage_service.dart';
import 'tour_folder_storage_service.dart';
import 'tour_storage_service.dart';
import 'user_library_service.dart';

class SyncResult {
  SyncResult({required this.label, required this.success, this.error});

  final String label;
  final bool success;
  final String? error;
}

// Manually pushes anything saved only locally up to the signed-in user's
// cloud library, with a visible per-item result — a self-service
// alternative to the automatic login-triggered merges (ToursScreen.
// _syncToursOnLogin and friends), for when that hasn't run (no fresh
// sign-in transition happened since the item was created/edited) or
// silently failed. Matches local vs. cloud by id (every route/tour/folder
// already carries a stable one), unlike those automatic merges, which use
// heuristics like matching a Tour's startedAt.
class SyncService {
  final _routeStorage = RouteStorageService();
  final _tourStorage = TourStorageService();
  final _routeFolderStorage = RouteFolderStorageService();
  final _tourFolderStorage = TourFolderStorageService();
  final _userLibrary = UserLibraryService();

  Future<List<SyncResult>> syncAll(String uid) async {
    final results = <SyncResult>[];

    final localRoutes = await _routeStorage.loadRoutes();
    final cloudRouteIds =
        (await _userLibrary.loadRoutes(uid)).map((r) => r.id).toSet();
    for (final route in localRoutes) {
      if (cloudRouteIds.contains(route.id)) continue;
      results.add(await _upload(
        'Route: ${route.name}',
        () => _userLibrary.addRoute(uid, route),
      ));
    }

    final localTours = await _tourStorage.loadTours();
    final cloudTourIds =
        (await _userLibrary.loadTours(uid)).map((t) => t.id).toSet();
    for (final tour in localTours) {
      if (cloudTourIds.contains(tour.id)) continue;
      results.add(await _upload(
        'Törn: ${tour.name}',
        () => _userLibrary.addTour(uid, tour),
      ));
    }

    final localRouteFolders = await _routeFolderStorage.loadFolders();
    final cloudRouteFolderIds =
        (await _userLibrary.loadRouteFolders(uid)).map((f) => f.id).toSet();
    for (final folder in localRouteFolders) {
      if (cloudRouteFolderIds.contains(folder.id)) continue;
      results.add(await _upload(
        'Routen-Ordner: ${folder.name}',
        () => _userLibrary.addRouteFolder(uid, folder),
      ));
    }

    final localTourFolders = await _tourFolderStorage.loadFolders();
    final cloudTourFolderIds =
        (await _userLibrary.loadFolders(uid)).map((f) => f.id).toSet();
    for (final folder in localTourFolders) {
      if (cloudTourFolderIds.contains(folder.id)) continue;
      results.add(await _upload(
        'Törn-Ordner: ${folder.name}',
        () => _userLibrary.addFolder(uid, folder),
      ));
    }

    return results;
  }

  Future<SyncResult> _upload(String label, Future<void> Function() upload) async {
    try {
      await upload();
      return SyncResult(label: label, success: true);
    } catch (e) {
      return SyncResult(label: label, success: false, error: e.toString());
    }
  }
}
