class AppConfig {
  static const String googleMapsApiKey = String.fromEnvironment('MAPS_API_KEY');

  // The deployed web app's URL — share links always point here regardless
  // of which platform (web or Android) the share was created from, since
  // a link only makes sense opened in a browser (Uri.base on Android
  // resolves to something app-internal, not a usable web address).
  static const String webBaseUrl = 'https://steffenkastian.github.io/boat_routes/';
}