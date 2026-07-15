import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/boat_route.dart';
import '../models/tour.dart';

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

  Future<void> addRoute(String uid, BoatRoute route) =>
      _routes(uid).add(route.toJson());

  Future<List<BoatRoute>> loadRoutes(String uid) async {
    final snapshot = await _routes(uid).get();
    return snapshot.docs.map((doc) => BoatRoute.fromJson(doc.data())).toList();
  }

  Future<void> addTour(String uid, Tour tour) => _tours(uid).add(tour.toJson());

  Future<List<Tour>> loadTours(String uid) async {
    final snapshot = await _tours(uid).get();
    return snapshot.docs.map((doc) => Tour.fromJson(doc.data())).toList();
  }
}
