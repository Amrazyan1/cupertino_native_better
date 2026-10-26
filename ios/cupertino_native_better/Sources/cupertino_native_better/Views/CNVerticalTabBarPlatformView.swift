import Flutter
import UIKit
import SwiftUI

/// One tab of the vertical tab bar, images already resolved.
@available(iOS 26.0, *)
struct CNVerticalTab: Identifiable {
  let id: Int
  let label: String
  let image: UIImage?
  let selectedImage: UIImage?
  /// Drawn in its own colours (e.g. an avatar) instead of tinted.
  let originalColors: Bool
}

@available(iOS 26.0, *)
final class CNVerticalTabBarModel: ObservableObject {
  @Published var tabs: [CNVerticalTab] = []
  @Published var badges: [String] = []
  @Published var selectedIndex = 0
  @Published var tint: Color = .accentColor
  var onSelect: (Int) -> Void = { _ in }
}

/// Icon-only tab bar stacked in a vertical glass capsule, the form tab bars
/// take on iPhone Duo's vertical bar column (a `UITabBar` can't go vertical
/// on its own). Speaks the same channel protocol as
/// `CupertinoTabBarPlatformView`, so the Dart side is shared.
@available(iOS 26.0, *)
class CNVerticalTabBarPlatformView: NSObject, FlutterPlatformView {
  static let width: CGFloat = 56
  static let itemHeight: CGFloat = 48
  static let inset: CGFloat = 4

  private let container: UIView
  private let channel: FlutterMethodChannel
  private let hostingController: UIHostingController<CNVerticalTabBarSwiftUI>
  private let model = CNVerticalTabBarModel()
  private var iconScale: CGFloat = ImageUtils.displayScale

  init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(name: "CupertinoNativeTabBar_\(viewId)", binaryMessenger: messenger)
    self.container = UIView(frame: frame)
    self.container.backgroundColor = .clear
    self.hostingController = UIHostingController(rootView: CNVerticalTabBarSwiftUI(model: model))
    self.hostingController.view.backgroundColor = .clear
    self.hostingController.safeAreaRegions = []

    let dict = args as? [String: Any] ?? [:]
    super.init()

    if let scale = dict["iconScale"] as? NSNumber { iconScale = CGFloat(truncating: scale) }
    applyItems(dict)
    if let style = dict["style"] as? [String: Any], let n = style["tint"] as? NSNumber {
      model.tint = Color(uiColor: ImageUtils.colorFromARGB(n.intValue))
    }
    let isDark = (dict["isDark"] as? NSNumber)?.boolValue ?? false
    hostingController.overrideUserInterfaceStyle = isDark ? .dark : .light

    let hostView = hostingController.view!
    hostView.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(hostView)
    NSLayoutConstraint.activate([
      hostView.topAnchor.constraint(equalTo: container.topAnchor),
      hostView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      hostView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      hostView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    ])

    model.onSelect = { [weak self] index in
      guard let self = self else { return }
      // Select right away, as UITabBar does; Dart confirms via setSelectedIndex.
      withAnimation(.spring(duration: 0.3, bounce: 0.2)) { self.model.selectedIndex = index }
      self.channel.invokeMethod("valueChanged", arguments: ["index": index])
    }

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "getIntrinsicSize":
        result(["width": Self.width, "height": Self.height(for: self.model.tabs.count)])
      case "setItems":
        if let scale = args["iconScale"] as? NSNumber { self.iconScale = CGFloat(truncating: scale) }
        self.applyItems(args)
        result(nil)
      case "setSelectedIndex":
        if let idx = (args["index"] as? NSNumber)?.intValue, idx >= 0, idx < self.model.tabs.count {
          if idx != self.model.selectedIndex {
            withAnimation(.spring(duration: 0.3, bounce: 0.2)) { self.model.selectedIndex = idx }
          }
          result(nil)
        } else {
          result(FlutterError(code: "bad_args", message: "Index out of range", details: nil))
        }
      case "setStyle":
        if let n = args["tint"] as? NSNumber {
          self.model.tint = Color(uiColor: ImageUtils.colorFromARGB(n.intValue))
        }
        result(nil)
      case "setBrightness":
        let isDark = (args["isDark"] as? NSNumber)?.boolValue ?? false
        self.hostingController.overrideUserInterfaceStyle = isDark ? .dark : .light
        result(nil)
      case "setBadges":
        self.model.badges = args["badges"] as? [String] ?? []
        result(nil)
      case "setFont", "setLayout", "refresh":
        // No labels, no split layout, no lazy label layout to force.
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView { container }

  static func height(for count: Int) -> CGFloat {
    CGFloat(count) * itemHeight + inset * 2
  }

  /// Resolves every tab's images with the horizontal bar's priority:
  /// image asset > custom icon bytes > SF Symbol.
  private func applyItems(_ dict: [String: Any]) {
    func strings(_ key: String) -> [String] { dict[key] as? [String] ?? [] }
    func datas(_ key: String) -> [Data?] {
      (dict[key] as? [FlutterStandardTypedData?] ?? []).map { $0?.data }
    }
    func at<T>(_ list: [T], _ i: Int) -> T? { i < list.count ? list[i] : nil }

    let labels = strings("labels")
    let symbols = strings("sfSymbols")
    let activeSymbols = strings("activeSfSymbols")
    let customIcons = datas("customIconBytes")
    let activeCustomIcons = datas("activeCustomIconBytes")
    let assetPaths = strings("imageAssetPaths")
    let activeAssetPaths = strings("activeImageAssetPaths")
    let assetData = datas("imageAssetData")
    let activeAssetData = datas("activeImageAssetData")
    let assetFormats = strings("imageAssetFormats")
    let activeAssetFormats = strings("activeImageAssetFormats")
    let originalColors = (dict["originalColors"] as? [NSNumber] ?? []).map { $0.boolValue }
    let sizes = dict["sfSymbolSizes"] as? [NSNumber?] ?? []

    let scale = iconScale
    func image(_ i: Int, symbol: String?, custom: Data?, data: Data?, format: String?, path: String?, size: CGSize?) -> UIImage? {
      if let data = data {
        return ImageUtils.createImageFromData(data, format: format, size: size, scale: scale)
      }
      if let path = path, !path.isEmpty {
        return ImageUtils.loadFlutterAsset(path, size: size)
      }
      if let custom = custom {
        return UIImage(data: custom, scale: scale)?.withRenderingMode(.alwaysTemplate)
      }
      if let symbol = symbol, !symbol.isEmpty {
        let config = size.map { UIImage.SymbolConfiguration(pointSize: $0.width) }
        return UIImage(systemName: symbol, withConfiguration: config)
      }
      return nil
    }

    model.tabs = labels.indices.map { i in
      let points = (at(sizes, i) ?? nil).map { CGFloat(truncating: $0) }.flatMap { $0 > 0 ? $0 : nil }
      let size = points.map { CGSize(width: $0, height: $0) }
      let normal = image(
        i, symbol: at(symbols, i), custom: at(customIcons, i) ?? nil,
        data: at(assetData, i) ?? nil, format: at(assetFormats, i), path: at(assetPaths, i), size: size
      )
      let active = image(
        i, symbol: at(activeSymbols, i), custom: at(activeCustomIcons, i) ?? nil,
        data: at(activeAssetData, i) ?? nil, format: at(activeAssetFormats, i), path: at(activeAssetPaths, i),
        size: size
      ) ?? normal
      return CNVerticalTab(
        id: i,
        label: labels[i],
        image: CupertinoTabBarPlatformView.applyOriginalColors(normal, originalColors, i, size: size),
        selectedImage: CupertinoTabBarPlatformView.applyOriginalColors(active, originalColors, i, size: size),
        originalColors: at(originalColors, i) ?? false
      )
    }
    model.badges = strings("badges")
    if let idx = (dict["selectedIndex"] as? NSNumber)?.intValue {
      model.selectedIndex = idx
    }
  }
}

@available(iOS 26.0, *)
struct CNVerticalTabBarSwiftUI: View {
  @ObservedObject var model: CNVerticalTabBarModel
  @Namespace private var namespace

  var body: some View {
    VStack(spacing: 0) {
      ForEach(model.tabs) { tab in
        tabButton(tab)
      }
    }
    .padding(CNVerticalTabBarPlatformView.inset)
    .glassEffect(.regular.interactive(), in: .capsule)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .ignoresSafeArea()
  }

  private func tabButton(_ tab: CNVerticalTab) -> some View {
    let selected = tab.id == model.selectedIndex
    let badge = tab.id < model.badges.count ? model.badges[tab.id] : ""
    return Button {
      model.onSelect(tab.id)
    } label: {
      icon(tab, selected: selected)
        .frame(
          width: CNVerticalTabBarPlatformView.width - CNVerticalTabBarPlatformView.inset * 2,
          height: CNVerticalTabBarPlatformView.itemHeight
        )
        .background {
          if selected {
            Capsule()
              .fill(Color.primary.opacity(0.1))
              .matchedGeometryEffect(id: "selection", in: namespace)
          }
        }
        .overlay(alignment: .topTrailing) {
          if !badge.isEmpty {
            Text(badge)
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.white)
              .padding(.horizontal, 5)
              .frame(minWidth: 18, minHeight: 18)
              .background(Capsule().fill(Color.red))
              .offset(x: 2, y: 2)
          }
        }
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    // Icons only; the label is what VoiceOver reads.
    .accessibilityLabel(Text(tab.label))
    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
  }

  @ViewBuilder
  private func icon(_ tab: CNVerticalTab, selected: Bool) -> some View {
    if let image = selected ? tab.selectedImage : tab.image {
      if tab.originalColors {
        Image(uiImage: image)
          .clipShape(Circle())
          .overlay {
            // An avatar can't be tinted, so ring it when selected.
            Circle().strokeBorder(selected ? model.tint : .clear, lineWidth: 2)
          }
      } else {
        Image(uiImage: image)
          .renderingMode(.template)
          .foregroundStyle(selected ? model.tint : Color.primary)
      }
    }
  }
}
