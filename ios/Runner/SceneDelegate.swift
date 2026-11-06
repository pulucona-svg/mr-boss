import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var privacySnapshotView: UIView?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    // Listen for screen recording / mirroring changes (public iOS API)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenCaptureChanged),
      name: UIScreen.capturedDidChangeNotification,
      object: nil
    )
    if UIScreen.main.isCaptured {
      showPrivacyCover(scene: scene)
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  @objc private func screenCaptureChanged() {
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
    if UIScreen.main.isCaptured {
      showPrivacyCover(scene: windowScene)
    } else {
      removePrivacyCover()
    }
  }

  override func sceneWillResignActive(_ scene: UIScene) {
    super.sceneWillResignActive(scene)
    // Global app-switcher privacy cover applied unconditionally
    showPrivacyCover(scene: scene)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    if !UIScreen.main.isCaptured {
      removePrivacyCover()
    }
  }

  private func showPrivacyCover(scene: UIScene) {
    guard privacySnapshotView == nil,
          let windowScene = scene as? UIWindowScene,
          let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first else {
      return
    }
    let cover = UIView(frame: window.bounds)
    cover.backgroundColor = UIColor(red: 0.03, green: 0.03, blue: 0.09, alpha: 1.0) // #070716
    cover.tag = 998877
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(cover)
    privacySnapshotView = cover
  }

  private func removePrivacyCover() {
    privacySnapshotView?.removeFromSuperview()
    privacySnapshotView = nil
  }
}
