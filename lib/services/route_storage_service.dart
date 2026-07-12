import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/boat_route.dart';

class RouteStorageService {
  static const _prefsKey = 'routes';

  Future<List<BoatRoute>> loadRoutes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    return raw
        .map((r) => BoatRoute.fromJson(jsonDecode(r) as Map<String, dynamic>))
        .toList();
  }

  Future<void> addRoute(BoatRoute route) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    raw.add(jsonEncode(route.toJson()));
    await prefs.setStringList(_prefsKey, raw);
  }

  Future<void> deleteRouteAt(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    raw.removeAt(index);
    await prefs.setStringList(_prefsKey, raw);
  }
}
