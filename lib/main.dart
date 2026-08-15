import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/background_tracking_service.dart';

export 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Configures (but doesn't start) the background Törn-tracking service —
  // must happen before runApp() per the package's own docs, so the
  // onStart callback is registered before anything could call start().
  // No-op-safe on web/iOS: BackgroundTrackingService is only ever started
  // from ToursScreen on Android.
  await BackgroundTrackingService().initialize();
  runApp(const BoatRoutesApp());
}
