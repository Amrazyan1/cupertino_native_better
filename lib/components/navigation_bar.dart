import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../channel/params.dart';
import '../style/sf_symbol.dart';
import '../utils/theme_helper.dart';
import '../utils/version_detector.dart';

/// A single tappable icon or label inside a [CNNavigationBarGroup].
class CNNavigationBarItem {
  /// Creates a navigation bar item. Provide an [icon], a [label], or both.
  const CNNavigationBarItem({
    this.id,
    this.icon,
    this.label,
    this.onPressed,
    this.enabled = true,
    this.color,
  }) : assert(icon != null || label != null);

  /// Stable identity of the item. When two consecutive configurations share
  /// an id the item stays in place; a new id blurs the old content out and
  /// the new content in. Defaults to the group position plus the icon name
  /// or label.
  final String? id;

  /// SF Symbol to show. Its [CNSymbol.size] and [CNSymbol.color] are used.
  final CNSymbol? icon;

  /// Text to show, alone or next to [icon].
  final String? label;

  /// Called when the item is tapped.
  final VoidCallback? onPressed;

  /// Whether the item can be tapped.
  final bool enabled;

  /// Colour of the item's label and icon, overriding the group default
  /// (white on a tinted group, the primary label colour otherwise) — e.g. a
  /// dark "Next" on a light tint. Falls back to [icon]'s colour when null.
  final Color? color;

  Color? get _effectiveColor => color ?? icon?.color;
}

/// One Liquid Glass capsule in a [CNNavigationBar], holding one or more items.
///
/// Groups with the same [id] in consecutive configurations morph into each
/// other: the capsule resizes and moves, and items cross-fade inside it.
/// A group that disappears melts into its neighbour, a new one splits off.
class CNNavigationBarGroup {
  /// Creates a glass capsule containing [items].
  const CNNavigationBarGroup({this.id, required this.items, this.tint});

  /// Creates a capsule holding a single icon button.
  CNNavigationBarGroup.icon(
    CNSymbol icon, {
    this.id,
    VoidCallback? onPressed,
    this.tint,
    bool enabled = true,
    Color? color,
  }) : items = [
         CNNavigationBarItem(
           icon: icon,
           onPressed: onPressed,
           enabled: enabled,
           color: color,
         ),
       ];

  /// Glass identity used for morphing. Defaults to the group's side and
  /// position (`leading.0`, `trailing.1`, ...), so the first trailing group of
  /// one screen morphs into the first trailing group of the next.
  final String? id;

  /// Items laid out horizontally inside the capsule.
  final List<CNNavigationBarItem> items;

  /// Optional glass tint, e.g. a green "compose" button. Icons on a tinted
  /// group default to white.
  final Color? tint;
}

/// A top bar of Liquid Glass buttons that morphs between configurations.
///
/// Change [leading] or [trailing] and the native bar animates to the new
/// buttons the way the iOS 26 navigation bar does: capsules stretch, merge
/// and split, icons blur-replace, and everything settles with a light spring.
///
/// The bar only draws the buttons; the area between them is transparent so
/// the page underneath can show its own title. To keep one bar alive across
/// pushes and pops, wrap a [Navigator] in a [CNNavigationBarScope] and declare
/// each page's buttons with [CNNavigationBarItems].
///
/// On iOS / macOS < 26 a Flutter fallback is shown.
class CNNavigationBar extends StatefulWidget {
  /// Creates a morphing glass navigation bar.
  const CNNavigationBar({
    super.key,
    this.leading = const [],
    this.trailing = const [],
    this.height = CNNavigationBar.defaultHeight,
    this.horizontalPadding = 16.0,
    this.groupSpacing = 10.0,
    this.pageKey,
  });

  /// Default bar height.
  static const double defaultHeight = 56.0;

  /// Glass groups aligned to the leading edge.
  final List<CNNavigationBarGroup> leading;

  /// Glass groups aligned to the trailing edge.
  final List<CNNavigationBarGroup> trailing;

  /// Height of the bar.
  final double height;

  /// Inset of the outermost groups from the screen edges.
  final double horizontalPadding;

  /// Gap between neighbouring groups on the same side.
  final double groupSpacing;

  /// Identity of the screen the buttons belong to. When it changes the update
  /// counts as navigation and every capsule plays the glass pulse (swell and
  /// blur), as on a push or pop; otherwise only the capsules that changed do.
  final Object? pageKey;

  @override
  State<CNNavigationBar> createState() => _CNNavigationBarState();
}

class _CNNavigationBarState extends State<CNNavigationBar> {
  MethodChannel? _channel;
  String? _lastSignature;
  Object? _lastPageKey;
  bool? _lastIsDark;
  Map<String, Object?> _lastItems = const {};
  Map<String, VoidCallback> _callbacks = const {};

  /// Button frames reported by the native bar; null until the first report.
  List<Rect>? _hitRects;

  bool get _useNative =>
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) &&
      PlatformVersion.shouldUseNativeGlass;

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  List<Map<String, Object?>> _serialize(
    List<CNNavigationBarGroup> groups,
    String side,
    Map<String, VoidCallback> callbacks,
  ) {
    return [
      for (var g = 0; g < groups.length; g++)
        () {
          final group = groups[g];
          final groupId = group.id ?? '$side.$g';
          return <String, Object?>{
            'id': groupId,
            if (group.tint != null)
              'tint': resolveColorToArgb(group.tint, context),
            'items': [
              for (var i = 0; i < group.items.length; i++)
                () {
                  final item = group.items[i];
                  final itemId =
                      item.id ??
                      '$groupId.$i.${item.icon?.name ?? ''}.${item.label ?? ''}';
                  if (item.onPressed != null) {
                    callbacks[itemId] = item.onPressed!;
                  }
                  return <String, Object?>{
                    'id': itemId,
                    if (item.icon != null) 'symbol': item.icon!.name,
                    if (item.icon != null) 'symbolSize': item.icon!.size,
                    if (item._effectiveColor != null)
                      'color': resolveColorToArgb(
                        item._effectiveColor,
                        context,
                      ),
                    if (item.label != null) 'label': item.label,
                    'enabled': item.enabled && item.onPressed != null,
                  };
                }(),
            ],
          };
        }(),
    ];
  }

  void _onCreated(int id) {
    final channel = MethodChannel('CNNavigationBar_$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'itemPressed') {
        final itemId = (call.arguments as Map?)?['id'] as String?;
        if (itemId != null) _callbacks[itemId]?.call();
      } else if (call.method == 'framesChanged') {
        final frames = (call.arguments as Map?)?['frames'] as List? ?? const [];
        final rects = [
          for (final f in frames.cast<Map>())
            Rect.fromLTWH(
              (f['x'] as num).toDouble(),
              (f['y'] as num).toDouble(),
              (f['w'] as num).toDouble(),
              (f['h'] as num).toDouble(),
            ),
        ];
        if (mounted) setState(() => _hitRects = rects);
      }
    });
    // Items may have changed between the first build (creation params) and
    // the view being created; resync without animating.
    channel.invokeMethod('setItems', {..._lastItems, 'animated': false});
    if (_lastIsDark != null) {
      channel.invokeMethod('setBrightness', {'isDark': _lastIsDark});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_useNative) return _buildFallback(context);

    final callbacks = <String, VoidCallback>{};
    final leading = _serialize(widget.leading, 'leading', callbacks);
    final trailing = _serialize(widget.trailing, 'trailing', callbacks);
    _callbacks = callbacks;
    final isDark = ThemeHelper.isDark(context);
    final signature = jsonEncode([leading, trailing]);

    final channel = _channel;
    if (channel != null) {
      final pageChanged = !identical(widget.pageKey, _lastPageKey);
      if (signature != _lastSignature || pageChanged) {
        channel.invokeMethod('setItems', {
          'leading': leading,
          'trailing': trailing,
          'animated': true,
          'pulseAll': pageChanged,
        });
      }
      if (isDark != _lastIsDark) {
        channel.invokeMethod('setBrightness', {'isDark': isDark});
      }
    }
    _lastSignature = signature;
    _lastPageKey = widget.pageKey;
    _lastIsDark = isDark;
    _lastItems = {'leading': leading, 'trailing': trailing};

    final creationParams = <String, Object?>{
      'leading': leading,
      'trailing': trailing,
      'horizontalPadding': widget.horizontalPadding,
      'groupSpacing': widget.groupSpacing,
      'isDark': isDark,
    };

    const viewType = 'CNNavigationBar';
    // Only the glass groups take touches; the rest of the bar lets them
    // through to whatever is underneath (e.g. a tappable page title).
    // No groups: nothing to tap, let every touch through.
    final isEmpty = widget.leading.isEmpty && widget.trailing.isEmpty;
    return _CNHitRegions(
      rects: isEmpty ? const [] : _hitRects,
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: defaultTargetPlatform == TargetPlatform.iOS
            ? UiKitView(
                viewType: viewType,
                creationParams: creationParams,
                creationParamsCodec: const StandardMessageCodec(),
                onPlatformViewCreated: _onCreated,
              )
            : AppKitView(
                viewType: viewType,
                creationParams: creationParams,
                creationParamsCodec: const StandardMessageCodec(),
                onPlatformViewCreated: _onCreated,
              ),
      ),
    );
  }

  Widget _buildFallback(BuildContext context) {
    Widget side(List<CNNavigationBarGroup> groups, String name) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var g = 0; g < groups.length; g++) ...[
            if (g > 0) SizedBox(width: widget.groupSpacing),
            _FallbackGroup(group: groups[g]),
          ],
        ],
      );
    }

    return SizedBox(
      height: widget.height,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Row(
            key: ValueKey(_fallbackKey()),
            children: [
              side(widget.leading, 'leading'),
              const Spacer(),
              side(widget.trailing, 'trailing'),
            ],
          ),
        ),
      ),
    );
  }

  String _fallbackKey() => [
    for (final g in [...widget.leading, ...widget.trailing])
      g.items.map((i) => '${i.icon?.name}${i.label}').join(','),
  ].join('|');
}

/// Hit-tests [child] only inside [rects] (slightly inflated). A miss returns
/// false so a [Stack] keeps looking at the widgets below. With null rects
/// (not reported yet) the whole box is hittable.
class _CNHitRegions extends SingleChildRenderObjectWidget {
  const _CNHitRegions({required this.rects, required super.child});

  final List<Rect>? rects;

  @override
  _RenderCNHitRegions createRenderObject(BuildContext context) =>
      _RenderCNHitRegions(rects);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCNHitRegions renderObject,
  ) {
    renderObject.rects = rects;
  }
}

class _RenderCNHitRegions extends RenderProxyBox {
  _RenderCNHitRegions(this.rects);

  List<Rect>? rects;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final regions = rects;
    if (regions != null &&
        !regions.any((r) => r.inflate(4).contains(position))) {
      return false;
    }
    return super.hitTest(result, position: position);
  }
}

class _FallbackGroup extends StatelessWidget {
  const _FallbackGroup({required this.group});

  final CNNavigationBarGroup group;

  @override
  Widget build(BuildContext context) {
    final tint = group.tint;
    final background =
        tint ?? CupertinoColors.tertiarySystemFill.resolveFrom(context);
    final foreground = tint != null
        ? CupertinoColors.white
        : CupertinoColors.label.resolveFrom(context);
    return Container(
      height: 44,
      padding: EdgeInsets.symmetric(horizontal: group.items.length > 1 ? 6 : 0),
      decoration: ShapeDecoration(
        color: background,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in group.items)
            CupertinoButton(
              padding: EdgeInsets.symmetric(
                horizontal: item.label != null ? 14 : 0,
              ),
              minimumSize: const Size(44, 44),
              onPressed: item.enabled ? item.onPressed : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.icon != null)
                    Icon(
                      _fallbackIcon(item.icon!.name),
                      size: item.icon!.size + 3,
                      color: item._effectiveColor ?? foreground,
                    ),
                  if (item.icon != null && item.label != null)
                    const SizedBox(width: 6),
                  if (item.label != null)
                    Text(
                      item.label!,
                      style: TextStyle(
                        color: item._effectiveColor ?? foreground,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static IconData _fallbackIcon(String symbol) {
    switch (symbol) {
      case 'chevron.left':
      case 'chevron.backward':
        return CupertinoIcons.back;
      case 'ellipsis':
        return CupertinoIcons.ellipsis;
      case 'plus':
        return CupertinoIcons.add;
      case 'camera':
        return CupertinoIcons.camera;
      case 'video':
        return CupertinoIcons.video_camera;
      case 'phone':
        return CupertinoIcons.phone;
      case 'trash':
        return CupertinoIcons.trash;
      case 'qrcode':
        return CupertinoIcons.qrcode;
      case 'chevron.down':
        return CupertinoIcons.chevron_down;
      case 'magnifyingglass':
        return CupertinoIcons.search;
      default:
        return CupertinoIcons.circle;
    }
  }
}

/// Hosts a single [CNNavigationBar] above [child] — typically a [Navigator] —
/// and shows the buttons declared by the visible page's
/// [CNNavigationBarItems].
///
/// Because the bar outlives the pages, pushing or popping a route morphs the
/// buttons instead of sliding a new bar in. The bar switches as soon as a
/// push or a tap-pop starts; during an interactive back swipe it keeps the
/// current buttons and morphs once the swipe finishes.
///
/// Pages lay out their own content (including any title) and should leave
/// [height] of space below the top safe area for the bar.
///
/// ```dart
/// CNNavigationBarScope(
///   child: Navigator(
///     onGenerateRoute: (_) => CupertinoPageRoute(
///       builder: (_) => CNNavigationBarItems(
///         trailing: [CNNavigationBarGroup.icon(CNSymbol('plus'))],
///         child: const ChatsPage(),
///       ),
///     ),
///   ),
/// )
/// ```
class CNNavigationBarScope extends StatefulWidget {
  /// Creates a scope that shows one persistent bar above [child].
  const CNNavigationBarScope({
    super.key,
    required this.child,
    this.height = CNNavigationBar.defaultHeight,
    this.horizontalPadding = 16.0,
    this.groupSpacing = 10.0,
  });

  /// The content under the bar, usually a [Navigator].
  final Widget child;

  /// Height of the bar below the top safe area.
  final double height;

  /// See [CNNavigationBar.horizontalPadding].
  final double horizontalPadding;

  /// See [CNNavigationBar.groupSpacing].
  final double groupSpacing;

  @override
  State<CNNavigationBarScope> createState() => _CNNavigationBarScopeState();
}

class _CNNavigationBarScopeState extends State<CNNavigationBarScope> {
  final List<_CNNavigationBarItemsState> _entries = [];
  _CNNavigationBarItemsState? _active;
  double _topInset = 0;

  /// Whether the native bar is mounted. It is dropped after staying empty for
  /// [_unmountDelay] so screens without buttons don't carry a platform view.
  bool _mountBar = false;
  Timer? _unmountTimer;
  static const _unmountDelay = Duration(milliseconds: 800);

  @override
  void dispose() {
    _unmountTimer?.cancel();
    super.dispose();
  }

  void _register(_CNNavigationBarItemsState entry) {
    _entries.add(entry);
    _scheduleUpdate();
  }

  void _unregister(_CNNavigationBarItemsState entry) {
    _entries.remove(entry);
    _scheduleUpdate();
  }

  bool _updateScheduled = false;

  // Registration happens while pages build, so the bar is always updated
  // after the current frame (coalescing multiple requests into one).
  void _scheduleUpdate() {
    if (!mounted || _updateScheduled) return;
    _updateScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      _update();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _update() {
    if (!mounted) return;
    // Freeze the bar while the finger is still dragging a back swipe: it can
    // still be cancelled. Flutter keeps the gesture flag up until the settle
    // animation ends, but once the swipe is released and committed the page's
    // route is popped (it starts leaving) — morph right then, like UIKit,
    // instead of waiting for the slide to finish.
    final gestureActive = _entries.any((e) => e._gestureInProgress);
    final active = _active;
    if (gestureActive &&
        active != null &&
        _entries.contains(active) &&
        !active._isLeaving) {
      return;
    }
    // Rebuild even if the active page is unchanged: its items may have.
    setState(() => _active = _pickActive());

    final items = _active?.widget;
    final hasButtons =
        items != null &&
        (items.leading.isNotEmpty || items.trailing.isNotEmpty);
    if (hasButtons) {
      _unmountTimer?.cancel();
      _unmountTimer = null;
      if (!_mountBar) setState(() => _mountBar = true);
    } else if (_mountBar && _unmountTimer == null) {
      // Wait for the glass to melt away before dropping the view.
      _unmountTimer = Timer(_unmountDelay, () {
        _unmountTimer = null;
        if (mounted) setState(() => _mountBar = false);
      });
    }
  }

  // The most recently registered page that is on top of its navigator and
  // not marked inactive. None (e.g. a sheet or dialog on top) hides the bar.
  _CNNavigationBarItemsState? _pickActive() {
    for (final entry in _entries.reversed) {
      if (entry._isEligible) return entry;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final active = _active?.widget;
    // An empty bar keeps the last inset so it doesn't move while invisible.
    if (active != null) _topInset = active.topInset;
    final top = MediaQuery.paddingOf(context).top + _topInset;
    return _CNNavigationBarScopeMarker(
      state: this,
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          if (_mountBar)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              top: top,
              left: 0,
              right: 0,
              height: widget.height,
              child: CNNavigationBar(
                leading: active?.leading ?? const [],
                trailing: active?.trailing ?? const [],
                height: widget.height,
                horizontalPadding: widget.horizontalPadding,
                groupSpacing: widget.groupSpacing,
                pageKey: _active,
              ),
            ),
        ],
      ),
    );
  }
}

class _CNNavigationBarScopeMarker extends InheritedWidget {
  const _CNNavigationBarScopeMarker({
    required this.state,
    required super.child,
  });

  final _CNNavigationBarScopeState state;

  @override
  bool updateShouldNotify(_CNNavigationBarScopeMarker oldWidget) =>
      !identical(state, oldWidget.state);
}

/// Declares the buttons the enclosing [CNNavigationBarScope] should show
/// while this page is the visible route.
///
/// Rebuilding with different [leading] / [trailing] morphs the bar in place,
/// e.g. to enter a selection mode.
///
/// The buttons only show while the page's route is the top route of its
/// navigator, so a sheet or dialog pushed above the page hides them.
class CNNavigationBarItems extends StatefulWidget {
  /// Declares bar buttons for the page containing [child].
  const CNNavigationBarItems({
    super.key,
    this.leading = const [],
    this.trailing = const [],
    this.active = true,
    this.topInset = 0,
    required this.child,
  });

  /// Extra space between the top safe area and the bar while this page owns
  /// it, e.g. to make room for a mini player above the page's own header.
  /// Changes animate.
  final double topInset;

  /// Whether this page currently owns the bar. Set it to false for pages
  /// that stay mounted while hidden, such as an unselected tab.
  final bool active;

  /// Leading glass groups for this page.
  final List<CNNavigationBarGroup> leading;

  /// Trailing glass groups for this page.
  final List<CNNavigationBarGroup> trailing;

  /// The page content.
  final Widget child;

  @override
  State<CNNavigationBarItems> createState() => _CNNavigationBarItemsState();
}

class _CNNavigationBarItemsState extends State<CNNavigationBarItems> {
  _CNNavigationBarScopeState? _scope;
  ModalRoute<Object?>? _route;
  Animation<double>? _animation;
  ValueListenable<bool>? _gesture;

  /// True once this page's route is being popped (or is gone).
  bool get _isLeaving {
    final route = _route;
    if (route == null) return false;
    if (!route.isActive) return true;
    final status = _animation?.status;
    return status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed;
  }

  bool get _gestureInProgress => _gesture?.value ?? false;

  bool get _isEligible {
    if (!widget.active || _isLeaving) return false;
    final route = _route;

    return route == null || route.isCurrent;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = context
        .dependOnInheritedWidgetOfExactType<_CNNavigationBarScopeMarker>()
        ?.state;
    final route = ModalRoute.of(context);

    if (!identical(route, _route)) {
      _animation?.removeStatusListener(_onRouteStatus);
      _gesture?.removeListener(_onChanged);
      _route = route;
      _animation = route?.animation;
      _animation?.addStatusListener(_onRouteStatus);
      _gesture = route?.navigator?.userGestureInProgressNotifier;
      _gesture?.addListener(_onChanged);
    }

    if (!identical(scope, _scope)) {
      _scope?._unregister(this);
      _scope = scope;
      _scope?._register(this);
    } else {
      // ModalRoute.of notifies when the route stops or starts being on top.
      _onChanged();
    }
  }

  @override
  void didUpdateWidget(covariant CNNavigationBarItems oldWidget) {
    super.didUpdateWidget(oldWidget);
    _onChanged();
  }

  void _onRouteStatus(AnimationStatus _) => _onChanged();

  void _onChanged() => _scope?._scheduleUpdate();

  @override
  void dispose() {
    _animation?.removeStatusListener(_onRouteStatus);
    _gesture?.removeListener(_onChanged);
    _scope?._unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
