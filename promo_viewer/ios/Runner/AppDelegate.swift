import Flutter
import UIKit
import FirebaseCore

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let options = FirebaseOptions(
      googleAppID: "1:1013201175960:ios:1a3b652ce16aafde4f17ed",
      gcmSenderID: "1013201175960"
    )
    options.apiKey = "AIzaSyCRcqgmPloq4c-I9_mMB86JrRjZU2Akcmg"
    options.projectID = "cnady-ce15b"
    options.bundleID = "com.jeeven.candy"
    options.storageBucket = "cnady-ce15b.firebasestorage.app"
    FirebaseApp.configure(options: options)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
