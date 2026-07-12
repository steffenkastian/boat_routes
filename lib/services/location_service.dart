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

    var permission = await Geolocator.checkPermission();
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
