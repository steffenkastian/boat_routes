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

  Future<void> deleteTourAt(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    raw.removeAt(index);
    await prefs.setStringList(_prefsKey, raw);
  }

  Future<void> renameTourAt(int index, String newName) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    final tour = Tour.fromJson(jsonDecode(raw[index]) as Map<String, dynamic>);
    final renamed = Tour(
      // Without this, the id ?? generateLocalId() fallback in Tour's
      // constructor mints a fresh id on every rename, leaving the copy
      // persisted here out of sync with whatever id is still held in
      // memory (tours_screen.dart) or already uploaded to the cloud.
      id: tour.id,
      name: newName,
      points: tour.points,
      startedAt: tour.startedAt,
      endedAt: tour.endedAt,
    );
    raw[index] = jsonEncode(renamed.toJson());
    await prefs.setStringList(_prefsKey, raw);
  }
}
