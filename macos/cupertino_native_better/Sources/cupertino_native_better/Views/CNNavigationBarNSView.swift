import FlutterMacOS
import AppKit
import SwiftUI

@available(macOS 26.0, *)
class CNNavigationBarNSView: NSView {
  private let hostingView: NSHostingView<CNNavigationBarSwiftUI>
  private let channel: FlutterMethodChannel
  private let model = CNNavigationBarModel()
  private var activeObserver: NSObjectProtocol?

  deinit {
    if let observer = activeObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  init(viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(name: "CNNavigationBar_\(viewId)", binaryMessenger: messenger)

    let dict = args as? [String: Any] ?? [:]
    model.leading = CNNavigationBarModel.parseGroups(dict["leading"])
    model.trailing = CNNavigationBarModel.parseGroups(dict["trailing"])
    if let padding = dict["horizontalPadding"] as? NSNumber {
      model.horizontalPadding = CGFloat(truncating: padding)
    }
    if let spacing = dict["groupSpacing"] as? NSNumber {
      model.groupSpacing = CGFloat(truncating: spacing)
    }

    self.hostingView = NSHostingView(rootView: CNNavigationBarSwiftUI(model: model))

    super.init(frame: .zero)

    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    let isDark = (dict["isDark"] as? NSNumber)?.boolValue ?? false
    hostingView.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)

    hostingView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(hostingView)
    NSLayoutConstraint.activate([
      hostingView.topAnchor.constraint(equalTo: topAnchor),
      hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
      hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
      hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])

    model.onPressed = { [weak self] id in
      self?.channel.invokeMethod("itemPressed", arguments: ["id": id])
    }
    model.onFramesChanged = { [weak self] frames in
      let list: [[String: Any]] = frames.map {
        ["id": $0.id, "x": $0.rect.minX, "y": $0.rect.minY, "w": $0.rect.width, "h": $0.rect.height]
      }
      self?.channel.invokeMethod("framesChanged", arguments: ["frames": list])
    }
    // Returning to the foreground: re-report, in case a lifecycle change
    // (modal, backgrounding) left Flutter with stale hit regions.
    activeObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.model.reportFrames()
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
          withAnimation(.spring(duration: 0.38, bounce: 0.22)) {
            self.model.apply(leading: leading, trailing: trailing, pulseAll: pulseAll)
          }
        } else {
          self.model.leading = leading
          self.model.trailing = trailing
        }
        result(nil)
      case "requestFrames":
        self.model.reportFrames()
        result(nil)
      case "setBrightness":
        let isDark = ((call.arguments as? [String: Any])?["isDark"] as? NSNumber)?.boolValue ?? false
        self.hostingView.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
