import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Cancels pointers orphaned when a PlatformView is removed mid-touch.
///
/// When a page finishes sliding over a route that hosts a `UiKitView`, the
/// Overlay moves that route offstage and the iOS engine removes the
/// platform view from the UIKit hierarchy in the same frame. A touch that
/// iOS hit-tested to the platform view's touch interceptor while the page
/// was still sliding in is then orphaned: on iOS 26 UIKit never calls
/// `touchesCancelled` on the interceptor's `ForwardingGestureRecognizer`,
/// so the engine never forwards a cancel. Flutter never receives an up or
/// cancel for that pointer, and every recognizer that joined it (e.g. a
/// text field tap on the covering page) waits forever.
///
/// This tracks every pointer that went down inside [globalRect] and, when
/// [coveringAnimation] completes (a page now fully covers the host route),
/// cancels those still down — mirroring what
/// `Navigator._cancelActivePointers` does after a navigation. If the real
/// up ever arrives afterwards it hits an empty hit test, which is harmless.
///
/// Remove once the Flutter engine cancels touches on a removed platform
/// view itself.
class OrphanedPointerCanceller {
  /// Starts tracking pointers. Call [dispose] when the platform view goes.
  OrphanedPointerCanceller({required this.globalRect, this.slop = 4.0}) {
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handlePointerEvent);
  }

  /// The platform view's current global rect, or null if it can't be
  /// measured. Read on each pointer down: iOS hit-tests against the view's
  /// position at that moment, and the host route may be moving (e.g. the
  /// parallax slide of a Cupertino push).
  final Rect? Function() globalRect;

  /// How far outside [globalRect] a down position still counts as inside.
  final double slop;

  final Set<int> _pointersOnView = <int>{};
  Animation<double>? _coveringAnimation;

  /// Number of pointers currently tracked as down.
  @visibleForTesting
  int get trackedPointerCount => _pointersOnView.length;

  /// Sets the animation whose completion means the host route is covered,
  /// typically the host route's [ModalRoute.secondaryAnimation]. Pass null
  /// to stop cancelling.
  set coveringAnimation(Animation<double>? animation) {
    if (identical(animation, _coveringAnimation)) return;
    _coveringAnimation?.removeStatusListener(_onCoveringStatusChanged);
    _coveringAnimation = animation;
    _coveringAnimation?.addStatusListener(_onCoveringStatusChanged);
  }

  void _handlePointerEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      final rect = globalRect()?.inflate(slop);
      if (rect != null && rect.contains(event.position)) {
        _pointersOnView.add(event.pointer);
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointersOnView.remove(event.pointer);
    }
  }

  void _onCoveringStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final orphaned = _pointersOnView.toList();
    _pointersOnView.clear();
    orphaned.forEach(GestureBinding.instance.cancelPointer);
  }

  /// Stops tracking pointers and listening to [coveringAnimation].
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _handlePointerEvent,
    );
    coveringAnimation = null;
    _pointersOnView.clear();
  }
}
