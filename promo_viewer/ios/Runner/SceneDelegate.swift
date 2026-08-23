import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  // FlutterSceneDelegate forwards scene:willConnectTo:options: to plugins (cold-start links work),
  // but does NOT forward scene:openURLContexts: (foreground resume links are dropped).
  // Fix: manually call the AppDelegate URL handler, which app_links is registered on,
  // so Supabase's deep-link handler fires when returning from the OAuth browser.
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    let app = UIApplication.shared
    for context in URLContexts {
      _ = app.delegate?.application?(app, open: context.url, options: [:])
    }
  }
}
