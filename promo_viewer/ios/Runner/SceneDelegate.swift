import Flutter
import UIKit
import app_links

class SceneDelegate: FlutterSceneDelegate {
  // FlutterSceneDelegate forwards scene:willConnectTo:options: to plugins (cold-start links work),
  // but does NOT forward scene:openURLContexts: (foreground resume links are dropped).
  // Override to manually deliver the URL to app_links so Supabase's deep-link handler fires.
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    for context in URLContexts {
      AppLinks.shared.handleLink(url: context.url)
    }
  }
}
