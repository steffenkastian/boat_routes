import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/boat_route.dart';
import '../models/shared_item.dart';
import '../models/tour.dart';

// A route/Törn shared either as a public link (anyone who has the link can
// view it, no login needed) or to one specific email address (only that
// signed-in account can view it) — see firestore.rules for how the two are
// distinguished and secured.
class ShareService {
  CollectionReference<Map<String, dynamic>> get _shares =>
      FirebaseFirestore.instance.collection('shared_items');

  Future<String> shareRoute(
    BoatRoute route, {
    required String ownerUid,
    required String ownerEmail,
    String? sharedWithEmail,
  }) => _share(
        type: 'route',
        name: route.name,
        data: route.toJson(),
        ownerUid: ownerUid,
        ownerEmail: ownerEmail,
        sharedWithEmail: sharedWithEmail,
      );

  Future<String> shareTour(
    Tour tour, {
    required String ownerUid,
    required String ownerEmail,
    String? sharedWithEmail,
  }) => _share(
        type: 'tour',
        name: tour.name,
        data: tour.toJson(),
        ownerUid: ownerUid,
        ownerEmail: ownerEmail,
        sharedWithEmail: sharedWithEmail,
      );

  // Bundles every day-Törn's full data into one share, ordered — a
  // recipient sees the whole trip (day list, combined map, totals) exactly
  // like the owner does, and "Übernehmen" imports all of it as a new
  // folder plus its Törns rather than each Törn separately.
  Future<String> shareFolder(
    String folderName,
    List<Tour> tours, {
    required String ownerUid,
    required String ownerEmail,
    String? sharedWithEmail,
  }) => _share(
        type: 'folder',
        name: folderName,
        data: {
          'folderName': folderName,
          'tours': tours.map((t) => t.toJson()).toList(),
        },
        ownerUid: ownerUid,
        ownerEmail: ownerEmail,
        sharedWithEmail: sharedWithEmail,
      );

  Future<String> _share({
    required String type,
    required String name,
    required Map<String, dynamic> data,
    required String ownerUid,
    required String ownerEmail,
    String? sharedWithEmail,
  }) async {
    final doc = _shares.doc();
    await doc.set({
      'type': type,
      'name': name,
      'data': data,
      'ownerUid': ownerUid,
      'ownerEmail': ownerEmail,
      'sharedWithEmail': sharedWithEmail?.trim().toLowerCase(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<SharedItem?> loadShare(String shareId) async {
    final doc = await _shares.doc(shareId).get();
    final data = doc.data();
    if (data == null) return null;
    return SharedItem.fromDoc(doc.id, data);
  }

  // Items explicitly shared with the given (verified, signed-in) email —
  // public link shares never show up here, only ones addressed to someone.
  Future<List<SharedItem>> loadSharedWithMe(String email) async {
    final snapshot = await _shares
        .where('sharedWithEmail', isEqualTo: email.trim().toLowerCase())
        .get();
    return snapshot.docs
        .map((doc) => SharedItem.fromDoc(doc.id, doc.data()))
        .toList();
  }
}
