import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/tour.dart';

class TourStorageService {
  static const _prefsKey = 'tours';

  Future<List<Tour>> loadTours() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    return raw
        .map((r) => Tour.fromJson(jsonDecode(r) as Map<String, dynamic>))
        .toList();
  }

  Future<void> addTour(Tour tour) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    raw.add(jsonEncode(tour.toJson()));
    await prefs.setStringList(_prefsKey, raw);
  }
}
