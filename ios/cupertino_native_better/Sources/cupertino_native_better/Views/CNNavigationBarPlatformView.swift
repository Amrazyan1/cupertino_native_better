import Flutter
import UIKit
import SwiftUI

@available(iOS 26.0, *)
class CNNavigationBarPlatformView: NSObject, FlutterPlatformView {
  private let container: UIView
  private let hostingController: UIHostingController<CNNavigationBarSwiftUI>
  private let channel: FlutterMethodChannel
  private let model = CNNavigationBarModel()

  init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(name: "CNNavigationBar_\(viewId)", binaryMessenger: messenger)
    self.container = UIView(frame: frame)
    self.container.backgroundColor = .clear

    let dict = args as? [String: Any] ?? [:]
    model.leading = CNNavigationBarModel.parseGroups(dict["leading"])
    model.trailing = CNNavigationBarModel.parseGroups(dict["trailing"])
    if let padding = dict["horizontalPadding"] as? NSNumber {
      model.horizontalPadding = CGFloat(truncating: padding)
    }
    if let spacing = dict["groupSpacing"] as? NSNumber {
      model.groupSpacing = CGFloat(truncating: spacing)
    }

    self.hostingController = UIHostingController(rootView: CNNavigationBarSwiftUI(model: model))
    self.hostingController.view.backgroundColor = .clear
    self.hostingController.safeAreaRegions = []
    let isDark = (dict["isDark"] as? NSNumber)?.boolValue ?? false
    self.hostingController.overrideUserInterfaceStyle = isDark ? .dark : .light

    super.init()

    let hostView = hostingController.view!
    hostView.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(hostView)
    NSLayoutConstraint.activate([
      hostView.topAnchor.constraint(equalTo: container.topAnchor),
      hostView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      hostView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      hostView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    ])

    model.onPressed = { [weak self] id in
      self?.channel.invokeMethod("itemPressed", arguments: ["id": id])
    }
    model.onFramesChanged = { [weak self] rects in
      let list = rects.map { ["x": $0.minX, "y": $0.minY, "w": $0.width, "h": $0.height] }
      self?.channel.invokeMethod("framesChanged", arguments: ["frames": list])
    }

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "setItems":
        let args = call.arguments as? [String: Any] ?? [:]
        let leading = CNNavigationBarModel.parseGroups(args["leading"])
        let trailing = CNNavigationBarModel.parseGroups(args["trailing"])
        let animated = (args["animated"] as? NSNumber)?.boolValue ?? true
        let pulseAll = (args["pulseAll"] as? NSNumber)?.boolValue ?? false
        if animated {
          // Same feel as the system bar: quick morph with a small overshoot.
          withAnimation(.spring(duration: 0.38, bounce: 0.22)) {
            self.model.apply(leading: leading, trailing: trailing, pulseAll: pulseAll)
          }
        } else {
          self.model.leading = leading
          self.model.trailing = trailing
        }
        result(nil)
      case "setBrightness":
        let isDark = ((call.arguments as? [String: Any])?["isDark"] as? NSNumber)?.boolValue ?? false
        self.hostingController.overrideUserInterfaceStyle = isDark ? .dark : .light
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView {
    return container
  }
}

/// Placeholder for iOS < 26. The Dart widget renders a Flutter fallback there
/// and never creates this view, but the factory still has to return something.
class CNNavigationBarFallbackView: NSObject, FlutterPlatformView {
  private let container: UIView

  init(frame: CGRect) {
    self.container = UIView(frame: frame)
    self.container.backgroundColor = .clear
    super.init()
  }

  func view() -> UIView {
    return container
  }
}
