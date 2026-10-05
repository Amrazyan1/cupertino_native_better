import FlutterMacOS
import AppKit

class CNNavigationBarFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    return FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    if #available(macOS 26.0, *) {
      return CNNavigationBarNSView(viewId: viewId, args: args, messenger: messenger)
    } else {
      // The Dart widget renders a Flutter fallback below macOS 26.
      return NSView()
    }
  }
}
