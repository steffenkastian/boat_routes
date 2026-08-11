import 'boat_route.dart';
import 'tour.dart';

enum SharedItemType { route, tour, folder }

// A route or Törn shared via the `shared_items` Firestore collection —
// either publicly (anyone with the link, sharedWithEmail == null) or to one
// specific signed-in email address. See firestore.rules for the access
// model this mirrors.
class SharedItem {
  SharedItem({
    required this.id,
    required this.type,
    required this.name,
    required this.ownerEmail,
    required this.sharedWithEmail,
    required this.data,
  });

  final String id;
  final SharedItemType type;
  final String name;
  final String ownerEmail;
  final String? sharedWithEmail;
  final Map<String, dynamic> data;

  bool get isPublicLink => sharedWithEmail == null;

  factory SharedItem.fromDoc(String id, Map<String, dynamic> json) =>
      SharedItem(
        id: id,
        type: switch (json['type']) {
          'tour' => SharedItemType.tour,
          'folder' => SharedItemType.folder,
          _ => SharedItemType.route,
        },
        name: json['name'] as String? ?? '',
        ownerEmail: json['ownerEmail'] as String? ?? '',
        sharedWithEmail: json['sharedWithEmail'] as String?,
        data: Map<String, dynamic>.from(json['data'] as Map),
      );

  BoatRoute toRoute() => BoatRoute.fromJson(data);
  Tour toTour() => Tour.fromJson(data);

  // Only valid for SharedItemType.folder — the ordered day tours bundled
  // into this share (see ShareService.shareFolder).
  List<Tour> toFolderTours() => (data['tours'] as List)
      .map((t) => Tour.fromJson(Map<String, dynamic>.from(t as Map)))
      .toList();
}
