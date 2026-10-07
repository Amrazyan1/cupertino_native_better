import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Used by the "Navigation bar hit testing" page: presents a full-screen
    // UIViewController over Flutter (like QuickLook) and dismisses it.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FullScreenModal") {
      let channel = FlutterMethodChannel(
        name: "cn_example/full_screen_modal",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { _, result in
        let window = UIApplication.shared.connectedScenes
          .compactMap { $0 as? UIWindowScene }
          .flatMap { $0.windows }
          .first { $0.isKeyWindow }
        guard var top = window?.rootViewController else {
          result(false)
          return
        }
        while let presented = top.presentedViewController { top = presented }
        let modal = UIViewController()
        modal.view.backgroundColor = .systemTeal
        modal.modalPresentationStyle = .fullScreen
        top.present(modal, animated: true) {
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            modal.dismiss(animated: true) { result(true) }
          }
        }
      }
    }
  }
}
