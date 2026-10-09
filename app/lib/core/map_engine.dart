/// Map engine configuration.
///
/// The Google Maps renderer is enabled at build time with:
///   flutter run --dart-define=USE_GOOGLE_MAPS=true
/// and requires a client-side Maps SDK key in the platform config
/// (app/android/secrets.properties or app/ios/Flutter/Secrets.xcconfig).
///
/// Without a key/flag the app uses the keyless OpenStreetMap renderer and
/// labels it in the UI, so the app is never silently broken or misleading
/// about which map you are looking at.
const bool useGoogleMaps = bool.fromEnvironment('USE_GOOGLE_MAPS');
