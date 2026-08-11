import '../utils/id_generator.dart';

// A named, ordered group of Törns (e.g. a multi-day sailing holiday made up
// of individual day tours) — holds only the member Törns' ids, not copies
// of their data, so it stays in sync automatically as those Törns change.
class TourFolder {
  TourFolder({
    String? id,
    required this.name,
    required this.tourIds,
    DateTime? createdAt,
  })  : id = id ?? generateLocalId(),
        createdAt = createdAt ?? DateTime.now();

  final String id;
  final String name;
  // Ordered — this is the day order shown in the folder's detail view.
  final List<String> tourIds;
  final DateTime createdAt;

  TourFolder copyWith({String? name, List<String>? tourIds}) => TourFolder(
        id: id,
        name: name ?? this.name,
        tourIds: tourIds ?? this.tourIds,
        createdAt: createdAt,
      );

  factory TourFolder.fromJson(Map<String, dynamic> json) => TourFolder(
        id: json['id'] as String?,
        name: json['name'] as String,
        tourIds:
            (json['tourIds'] as List).map((e) => e as String).toList(),
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tourIds': tourIds,
        'createdAt': createdAt.toIso8601String(),
      };
}
