import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/route_folder.dart';

class RouteFolderStorageService {
  static const _prefsKey = 'route_folders';

  Future<List<RouteFolder>> loadFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    return raw
        .map((f) => RouteFolder.fromJson(jsonDecode(f) as Map<String, dynamic>))
        .toList();
  }

  Future<void> addFolder(RouteFolder folder) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    raw.add(jsonEncode(folder.toJson()));
    await prefs.setStringList(_prefsKey, raw);
  }

  // Adds [folder] if no stored folder shares its id, otherwise overwrites
  // that one in place — every caller only ever knows a folder's id, not
  // which SharedPreferences index it happens to be stored at.
  Future<void> upsertFolder(RouteFolder folder) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    final index = raw.indexWhere((f) =>
        (jsonDecode(f) as Map<String, dynamic>)['id'] == folder.id);
    if (index == -1) {
      raw.add(jsonEncode(folder.toJson()));
    } else {
      raw[index] = jsonEncode(folder.toJson());
    }
    await prefs.setStringList(_prefsKey, raw);
  }

  Future<void> deleteFolder(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    raw.removeWhere((f) => (jsonDecode(f) as Map<String, dynamic>)['id'] == id);
    await prefs.setStringList(_prefsKey, raw);
  }
}
