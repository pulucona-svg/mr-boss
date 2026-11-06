import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Global app-wide security policy active by default
  static var isSecureScreenActive = true

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "com.mirrordigital.app/security",
      binaryMessenger: engineBridge.binaryMessenger
    )
    channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "enableSecureScreen":
        AppDelegate.isSecureScreenActive = true
        result(true)
      case "disableSecureScreen":
        // In global security mode, protection is enforced application-wide.
        AppDelegate.isSecureScreenActive = true
        result(true)
      case "isSecureScreenEnabled":
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
