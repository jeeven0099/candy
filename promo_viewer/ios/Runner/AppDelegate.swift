import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging

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
    // Write a "pending" marker so Dart can distinguish "not fired yet" from real errors
    UserDefaults.standard.set("awaiting registration…", forKey: "apns_status")
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(_ application: UIApplication,
                             didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Messaging.messaging().apnsToken = deviceToken
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    UserDefaults.standard.set("registered — \(hex.prefix(8))…", forKey: "apns_status")
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(_ application: UIApplication,
                             didFailToRegisterForRemoteNotificationsWithError error: Error) {
    UserDefaults.standard.set("FAILED: \(error.localizedDescription)", forKey: "apns_status")
    print("[APNs] didFailToRegisterForRemoteNotifications: \(error)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
