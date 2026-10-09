import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Google Maps SDK key from Secrets.xcconfig -> Info.plist (git-ignored
    // source). Empty/missing key => the app falls back to OpenStreetMap.
    if let key = Bundle.main.object(forInfoDictionaryKey: "GMSServicesApiKey") as? String,
       !key.isEmpty, key != "$(GMSS_MAPS_KEY)" {
      GMSServices.provideAPIKey(key)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
