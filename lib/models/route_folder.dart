import '../utils/id_generator.dart';

// A named, ordered group of planned routes (e.g. several legs combined into
// one longer trip) — holds only the member routes' ids, not copies of their
// data, so it stays in sync automatically as those routes change.
class RouteFolder {
  RouteFolder({
    String? id,
    required this.name,
    required this.routeIds,
    DateTime? createdAt,
  })  : id = id ?? generateLocalId(),
        createdAt = createdAt ?? DateTime.now();

  final String id;
  final String name;
  // Ordered — this is the leg order shown in the folder's detail view.
  final List<String> routeIds;
  final DateTime createdAt;

  RouteFolder copyWith({String? name, List<String>? routeIds}) => RouteFolder(
        id: id,
        name: name ?? this.name,
        routeIds: routeIds ?? this.routeIds,
        createdAt: createdAt,
      );

  factory RouteFolder.fromJson(Map<String, dynamic> json) => RouteFolder(
        id: json['id'] as String?,
        name: json['name'] as String,
        routeIds:
            (json['routeIds'] as List).map((e) => e as String).toList(),
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'routeIds': routeIds,
        'createdAt': createdAt.toIso8601String(),
      };
}
