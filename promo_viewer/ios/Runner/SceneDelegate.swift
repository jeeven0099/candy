import Flutter
import UIKit
import UserNotifications

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    // Scene launches do not populate the older UIApplication launch options.
    if let response = connectionOptions.notificationResponse,
       response.actionIdentifier == UNNotificationDefaultActionIdentifier {
      let info = response.notification.request.content.userInfo
      if let id = info["promo_id"] as? String, !id.isEmpty {
        AppDelegate.notificationLaunchPromoId = id
      } else if let payload = info["payload"] as? String, !payload.isEmpty {
        if let data = payload.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let id = decoded["id"] as? String {
          AppDelegate.notificationLaunchPromoId = id
        } else {
          AppDelegate.notificationLaunchPromoId = payload
        }
      }
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }
}
