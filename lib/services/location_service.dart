import 'package:geolocator/geolocator.dart';

enum LocationAccessStatus {
  granted,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
}

class LocationService {
  Future<LocationAccessStatus> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccessStatus.serviceDisabled;
    }

    LocationPermission permission;
    try {
      permission = await Geolocator.checkPermission();
    } catch (_) {
      // Some mobile browsers don't reliably support the Permissions API
      // query for geolocation and throw here instead of returning a status.
      // Treat that the same as "unknown" and fall through to requesting
      // directly, which triggers the browser's native prompt via
      // getCurrentPosition instead of relying on the Permissions API.
      permission = LocationPermission.denied;
    }

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    switch (permission) {
      case LocationPermission.denied:
        return LocationAccessStatus.permissionDenied;
      case LocationPermission.deniedForever:
        return LocationAccessStatus.permissionDeniedForever;
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        return LocationAccessStatus.granted;
      case LocationPermission.unableToDetermine:
        return LocationAccessStatus.permissionDenied;
    }
  }

  Stream<Position> positionStream({LocationSettings? settings}) {
    return Geolocator.getPositionStream(
      locationSettings: settings ??
          const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 3,
          ),
    );
  }
}
