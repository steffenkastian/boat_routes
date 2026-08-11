import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/boat_route.dart';
import '../models/tour.dart';
import '../models/tour_folder.dart';

// Mirrors a signed-in user's locally-saved routes/Törns into their own
// Firestore subcollections, so logging in on another device shows the same
// data. Local SharedPreferences storage (RouteStorageService/
// TourStorageService) stays the source of truth for offline/logged-out use
// — this is purely an additional copy, merged in on top when signed in.
class UserLibraryService {
  CollectionReference<Map<String, dynamic>> _routes(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('routes');

  CollectionReference<Map<String, dynamic>> _tours(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('tours');

  CollectionReference<Map<String, dynamic>> _folders(String uid) => FirebaseFirestore
      .instance
      .collection('users')
      .doc(uid)
      .collection('tourFolders');

  // Written under the route/tour's own locally-generated id (not
  // Firestore's auto-id via .add()) so the same id addresses it in local
  // storage, Firestore, and any share of it.
  Future<void> addRoute(String uid, BoatRoute route) =>
      _routes(uid).doc(route.id).set(route.toJson());

  Future<List<BoatRoute>> loadRoutes(String uid) async {
    final snapshot = await _routes(uid).get();
    return snapshot.docs.map((doc) => BoatRoute.fromJson(doc.data())).toList();
  }

  Future<void> addTour(String uid, Tour tour) =>
      _tours(uid).doc(tour.id).set(tour.toJson());

  Future<List<Tour>> loadTours(String uid) async {
    final snapshot = await _tours(uid).get();
    return snapshot.docs.map((doc) => Tour.fromJson(doc.data())).toList();
  }

  Future<void> addFolder(String uid, TourFolder folder) =>
      _folders(uid).doc(folder.id).set(folder.toJson());

  Future<List<TourFolder>> loadFolders(String uid) async {
    final snapshot = await _folders(uid).get();
    return snapshot.docs.map((doc) => TourFolder.fromJson(doc.data())).toList();
  }
}
