import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'location_service.dart';

// A second, self-managed notification shown alongside geolocator's own
// "Törn läuft" foreground-service one while a Törn is being tracked: the
// geolocator plugin doesn't expose any way to update its notification's
// text after starting, so live distance has to go through a separate
// notification we fully control instead. Android-only — this package has no
// web implementation at all, so every method here must stay behind
// isAndroidPlatform checks (already done in tours_screen.dart) rather than
// ever being called on web.
class TourNotificationService {
  static const _channelId = 'toern_progress';
  static const _channelName = 'Törn-Fortschritt';
  static const _notificationId = 1001;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    if (!isAndroidPlatform) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _initialized = true;
  }

  Future<void> showProgress(String text) async {
    if (!isAndroidPlatform) return;
    await _ensureInitialized();
    await _plugin.show(
      id: _notificationId,
      title: 'Törn läuft',
      body: text,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          onlyAlertOnce: true,
          category: AndroidNotificationCategory.status,
        ),
      ),
    );
  }

  Future<void> cancel() async {
    if (!isAndroidPlatform) return;
    if (!_initialized) return;
    await _plugin.cancel(id: _notificationId);
  }
}
