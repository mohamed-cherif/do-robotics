import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    registerPlatformChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// iOS side of lib/services/platform_service.dart (Android: MainActivity.kt).
  /// NOTE: written during the 2026-09 audit without a Mac; build and test
  /// before the first iOS release.
  private func registerPlatformChannel() {
    guard let registrar = self.registrar(forPlugin: "DoRoboticsPlatform") else { return }
    let channel = FlutterMethodChannel(
      name: "do_robotics/platform", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "keepScreenOn":
        UIApplication.shared.isIdleTimerDisabled = (call.arguments as? Bool) ?? false
        result(nil)
      case "acquireMulticastLock", "releaseMulticastLock":
        result(nil)  // Android-only concept; nothing to do on iOS.
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
