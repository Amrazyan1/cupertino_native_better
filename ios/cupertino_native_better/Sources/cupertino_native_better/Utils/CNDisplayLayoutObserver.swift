import Flutter
import UIKit

/// Reports the display layout that iPhone Duo-style hardware adds on top of
/// the safe area: the edge where the system puts vertical bars, and the
/// reserved regions (fold division, camera occlusion).
///
/// One observer per engine, bound to that engine's own Flutter view: other
/// windows (SDK overlays, a second engine) never feed it, and a headless
/// engine (no view controller) reports nothing.
///
/// Dart calls `start`; from then on an invisible probe view in the Flutter
/// window re-reads the layout whenever it lays out (open, close, rotate, Split
/// View), its safe area or traits change, or the hinge moves, and pushes
/// `layoutChanged` when the result differs from the last report. Frames are
/// in window points, which match Flutter's logical pixels.
final class CNDisplayLayoutObserver: NSObject {
  private let channel: FlutterMethodChannel
  private weak var registrar: FlutterPluginRegistrar?
  private var probe: CNDisplayLayoutProbe?
  private var lastReport: [String: Any]?
  private var observers: [NSObjectProtocol] = []

  /// Starts serving the engine of [registrar]. The channel handler keeps the
  /// observer alive for as long as the engine.
  static func register(with registrar: FlutterPluginRegistrar) {
    _ = CNDisplayLayoutObserver(registrar: registrar)
  }

  private init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    self.channel = FlutterMethodChannel(
      name: "cupertino_native/display_layout", binaryMessenger: registrar.messenger())
    super.init()
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "start":
        self.start()
        result(self.currentLayout())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit {
    observers.forEach(NotificationCenter.default.removeObserver)
    probe?.removeFromSuperview()
  }

  private func start() {
    if observers.isEmpty {
      // Opening or closing the device can move the Flutter view to another
      // window or scene; follow it. The view controller may also only exist
      // after the engine registered its plugins.
      let center = NotificationCenter.default
      for name in [UIWindow.didBecomeKeyNotification, UIScene.didActivateNotification] {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          self?.attach()
        })
      }
    }
    attach()
  }

  /// Moves the probe into the Flutter view's window (no-op if already there).
  private func attach() {
    guard let window = registrar?.viewController?.view.window else { return }
    if probe?.window === window { return }
    probe?.removeFromSuperview()
    let probe = CNDisplayLayoutProbe(frame: window.bounds)
    probe.onChange = { [weak self] in self?.report() }
    window.insertSubview(probe, at: 0)
    self.probe = probe
    report()
  }

  private func report() {
    let layout = currentLayout()
    if let last = lastReport, NSDictionary(dictionary: last).isEqual(to: layout) { return }
    lastReport = layout
    channel.invokeMethod("layoutChanged", arguments: layout)
  }

  private func currentLayout() -> [String: Any] {
    guard let probe = probe, let window = probe.window else { return [:] }
    var layout: [String: Any] = [:]
    if let edge = probe.verticalBarEdge() {
      layout["verticalBarEdge"] = edge
    }
    layout["reservedRegions"] = probe.reservedRegions()
    if let statusBar = window.windowScene?.statusBarManager?.statusBarFrame, !statusBar.isEmpty {
      layout["statusBarFrame"] = Self.rect(statusBar)
    }
    return layout
  }

  static func rect(_ r: CGRect) -> [String: Any] {
    ["x": r.minX, "y": r.minY, "w": r.width, "h": r.height]
  }
}

/// Invisible, non-interactive view filling the window. Its layout, safe area,
/// trait and hinge callbacks are the signals that the display layout may have
/// changed.
private final class CNDisplayLayoutProbe: UIView {
  var onChange: () -> Void = {}

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    backgroundColor = .clear
    autoresizingMask = [.flexibleWidth, .flexibleHeight]
    if #available(iOS 17.0, *) {
      registerForTraitChanges(
        [UITraitHorizontalSizeClass.self, UITraitVerticalSizeClass.self, UITraitLayoutDirection.self]
      ) { (probe: CNDisplayLayoutProbe, _: UITraitCollection) in
        probe.onChange()
      }
    }
    #if canImport(UIKit, _version: 9127.0.85)
    if #available(iOS 27.1, *) {
      // Folding or unfolding toggles the division region without resizing
      // the window, so layout alone would miss it.
      addInteraction(UIHingeInteraction { [weak self] _, _ in
        DispatchQueue.main.async { self?.onChange() }
      })
    }
    #endif
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    onChange()
  }

  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    onChange()
  }

  /// The physical edge ("left" / "right") where the system puts vertical
  /// bars, or nil where it never does.
  func verticalBarEdge() -> String? {
    #if canImport(UIKit, _version: 9127.0.85)
    if #available(iOS 27.1, *) {
      let rtl = traitCollection.layoutDirection == .rightToLeft
      switch traitCollection.verticalBarEdge {
      case .leading: return rtl ? "right" : "left"
      case .trailing: return rtl ? "left" : "right"
      default: return nil
      }
    }
    #endif
    return nil
  }

  /// Division (fold) and occlusion (camera) regions, inactive ones included
  /// so Flutter can plan for a fold even while the device is flat.
  func reservedRegions() -> [[String: Any]] {
    #if canImport(UIKit, _version: 9127.0.85)
    if #available(iOS 27.1, *) {
      let kinds: [(UIView.ReservedRegion.Kind, String)] = [(.division, "division"), (.occlusion, "occlusion")]
      return kinds.flatMap { kind, name in
        reservedRegions(kind: kind, options: .includeInactive).map { region -> [String: Any] in
          let m = region.margins
          return [
            "kind": name,
            "frame": CNDisplayLayoutObserver.rect(convert(region.frame, to: nil)),
            "margins": ["l": m.left, "t": m.top, "r": m.right, "b": m.bottom],
            "active": region.isActive,
          ]
        }
      }
    }
    #endif
    return []
  }
}
