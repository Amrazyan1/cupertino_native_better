import UIKit

/// Root view for a PlatformView that cancels in-flight touches when the
/// view leaves the window.
///
/// When a Flutter route is covered by an opaque route, the Overlay moves it
/// offstage and the engine removes its PlatformViews from the UIKit
/// hierarchy. A touch that iOS hit-tested to the PlatformView's touch
/// interceptor while the covering page was still sliding in is then
/// orphaned: on iOS 26 UIKit sends neither touchesEnded nor
/// touchesCancelled to the interceptor's recognizers, so Flutter never
/// sees an up/cancel for that pointer and every recognizer that joined it
/// stays stuck.
///
/// Before leaving the window, this view toggles `isEnabled` on every
/// recognizer of its superview (the engine's touch interceptor) that is
/// still tracking touches, which makes UIKit cancel them. Only public
/// UIKit API is used: if a future engine moves its recognizers, the loop
/// finds nothing and behavior is unchanged.
class CNTouchCancellingContainerView: UIView {
  override func willMove(toWindow newWindow: UIWindow?) {
    super.willMove(toWindow: newWindow)
    guard newWindow == nil else { return }
    for recognizer in superview?.gestureRecognizers ?? [] {
      guard recognizer.isEnabled, recognizer.numberOfTouches > 0 else { continue }
      NSLog(
        "[CN TouchCancel] cancelling \(recognizer.numberOfTouches) in-flight touch(es) on \(type(of: recognizer)), state=\(recognizer.state.rawValue)"
      )
      recognizer.isEnabled = false
      recognizer.isEnabled = true
    }
  }
}
