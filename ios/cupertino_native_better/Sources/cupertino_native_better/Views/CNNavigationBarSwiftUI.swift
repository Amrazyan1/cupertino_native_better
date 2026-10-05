import SwiftUI

/// One tappable icon/label inside a navigation bar glass group.
@available(iOS 26.0, *)
struct CNNavBarItem: Identifiable, Equatable {
  let id: String
  let symbol: String?
  let symbolSize: CGFloat
  let label: String?
  let color: Color?
  let enabled: Bool
}

/// One glass capsule in the bar. Groups keep their glass identity across
/// updates via `id`, which is what lets SwiftUI morph one set of buttons into
/// the next (resize, merge, split) instead of swapping them.
@available(iOS 26.0, *)
struct CNNavBarGroup: Identifiable, Equatable {
  let id: String
  let items: [CNNavBarItem]
  let tint: Color?
}

@available(iOS 26.0, *)
final class CNNavigationBarModel: ObservableObject {
  @Published var leading: [CNNavBarGroup] = []
  @Published var trailing: [CNNavBarGroup] = []
  /// Per-group counter; bumping it plays that group's glass pulse.
  @Published var pulses: [String: Int] = [:]
  var horizontalPadding: CGFloat = 16
  var groupSpacing: CGFloat = 10
  var onPressed: (String) -> Void = { _ in }
  /// Receives the frames of all groups (bar coordinates) whenever they change,
  /// so Flutter can let touches outside the buttons through.
  var onFramesChanged: ([CGRect]) -> Void = { _ in }

  private var frames: [String: CGRect] = [:]
  private var framesFlushScheduled = false

  func setFrame(_ rect: CGRect?, for id: String) {
    if let rect = rect { frames[id] = rect } else { frames.removeValue(forKey: id) }
    guard !framesFlushScheduled else { return }
    framesFlushScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.framesFlushScheduled = false
      self.onFramesChanged(Array(self.frames.values))
    }
  }

  /// Replaces the groups and bumps the pulse of every group that stays on
  /// screen: all of them on navigation ([pulseAll]), otherwise only the ones
  /// whose content changed. New groups don't pulse — they split off instead.
  func apply(leading newLeading: [CNNavBarGroup], trailing newTrailing: [CNNavBarGroup], pulseAll: Bool) {
    let old = Dictionary((leading + trailing).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    for group in newLeading + newTrailing {
      guard let previous = old[group.id] else { continue }
      if pulseAll || previous != group {
        pulses[group.id, default: 0] += 1
      }
    }
    leading = newLeading
    trailing = newTrailing
  }

  /// Parses the `leading`/`trailing` group lists sent from Dart.
  static func parseGroups(_ raw: Any?) -> [CNNavBarGroup] {
    guard let list = raw as? [[String: Any]] else { return [] }
    return list.compactMap { dict in
      guard let id = dict["id"] as? String else { return nil }
      let items: [CNNavBarItem] = (dict["items"] as? [[String: Any]] ?? []).compactMap { item in
        guard let itemId = item["id"] as? String else { return nil }
        return CNNavBarItem(
          id: itemId,
          symbol: item["symbol"] as? String,
          symbolSize: (item["symbolSize"] as? NSNumber).map { CGFloat(truncating: $0) } ?? 17,
          label: item["label"] as? String,
          color: (item["color"] as? NSNumber).map { colorFromARGB($0.intValue) },
          enabled: (item["enabled"] as? NSNumber)?.boolValue ?? true
        )
      }
      let tint = (dict["tint"] as? NSNumber).map { colorFromARGB($0.intValue) }
      return CNNavBarGroup(id: id, items: items, tint: tint)
    }
  }

  static func colorFromARGB(_ argb: Int) -> Color {
    Color(
      .sRGB,
      red: Double((argb >> 16) & 0xFF) / 255.0,
      green: Double((argb >> 8) & 0xFF) / 255.0,
      blue: Double(argb & 0xFF) / 255.0,
      opacity: Double((argb >> 24) & 0xFF) / 255.0
    )
  }
}

/// Leading and trailing glass groups sharing one `GlassEffectContainer`, so a
/// change of items morphs the glass shapes (the iOS 26 navigation bar
/// behaviour) rather than cross-fading two separate bars.
@available(iOS 26.0, *)
struct CNNavigationBarSwiftUI: View {
  @ObservedObject var model: CNNavigationBarModel
  @Namespace private var namespace
  private static let barSpace = "CNNavigationBar"

  var body: some View {
    // Blend distance below the gap between groups: at rest every capsule
    // stays separate and fully round; shapes only fuse while a morph brings
    // them closer than this.
    GlassEffectContainer(spacing: max(0, model.groupSpacing - 4)) {
      HStack(spacing: 0) {
        HStack(spacing: model.groupSpacing) {
          ForEach(model.leading) { groupView($0) }
        }
        Spacer(minLength: 0)
        HStack(spacing: model.groupSpacing) {
          ForEach(model.trailing) { groupView($0) }
        }
      }
      .padding(.horizontal, model.horizontalPadding)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .coordinateSpace(.named(Self.barSpace))
    .ignoresSafeArea()
  }

  /// The iOS 26 bar-button transition: the whole glass swells and its
  /// content goes soft, then it springs back as the new state settles.
  private func groupView(_ group: CNNavBarGroup) -> some View {
    KeyframeAnimator(initialValue: CNGlassPulse(), trigger: model.pulses[group.id] ?? 0) { pulse in
      glassGroup(group, blur: pulse.blur)
        .scaleEffect(pulse.scale)
    } keyframes: { _ in
      KeyframeTrack(\.scale) {
        CubicKeyframe(1.18, duration: 0.12)
        SpringKeyframe(1.0, duration: 0.34, spring: .bouncy(duration: 0.34, extraBounce: 0.05))
      }
      // Held soft while the old and new content crossfade underneath.
      KeyframeTrack(\.blur) {
        CubicKeyframe(6, duration: 0.1)
        LinearKeyframe(6, duration: 0.08)
        CubicKeyframe(0, duration: 0.2)
      }
    }
    // Layout (target) frames, not the animated ones: reported once per change.
    .onGeometryChange(for: CGRect.self) { proxy in
      proxy.frame(in: .named(Self.barSpace))
    } action: { rect in
      model.setFrame(rect, for: group.id)
    }
    .onDisappear { model.setFrame(nil, for: group.id) }
  }

  @ViewBuilder
  private func glassGroup(_ group: CNNavBarGroup, blur: CGFloat) -> some View {
    let isMulti = group.items.count > 1
    let foreground: Color = group.tint != nil ? .white : .primary
    HStack(spacing: 0) {
      ForEach(group.items) { item in
        Button {
          model.onPressed(item.id)
        } label: {
          itemLabel(item)
            .foregroundStyle(item.color ?? foreground)
            .frame(minWidth: isMulti ? 36 : 44, minHeight: 44)
            .padding(.horizontal, item.label != nil ? 14 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.enabled)
        .opacity(item.enabled ? 1 : 0.4)
        // Plain crossfade: icons don't scale or blur on their own. The
        // softness and the swell come from the whole glass (the group pulse),
        // so the content moves as one piece with its capsule.
        .transition(.opacity)
      }
    }
    .blur(radius: blur)
    .padding(.horizontal, isMulti ? 6 : 0)
    .frame(height: 44)
    .glassEffect(
      group.tint.map { Glass.regular.tint($0).interactive() } ?? Glass.regular.interactive(),
      in: .capsule
    )
    .glassEffectID(group.id, in: namespace)
  }

  @ViewBuilder
  private func itemLabel(_ item: CNNavBarItem) -> some View {
    if let symbol = item.symbol, let label = item.label {
      Label(label, systemImage: symbol)
        .font(.system(size: item.symbolSize, weight: .medium))
    } else if let symbol = item.symbol {
      Image(systemName: symbol)
        .font(.system(size: item.symbolSize, weight: .medium))
    } else {
      Text(item.label ?? "")
        .font(.system(size: 17, weight: .medium))
    }
  }
}

@available(iOS 26.0, *)
struct CNGlassPulse {
  var scale: CGFloat = 1
  var blur: CGFloat = 0
}
