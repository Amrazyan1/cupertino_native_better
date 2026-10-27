import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../channel/params.dart';
import '../style/sf_symbol.dart';
import '../utils/display_layout.dart';
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
    this.labelSize,
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

  /// Font size of [label]; 17 when null.
  final double? labelSize;

  Color? get _effectiveColor => color ?? icon?.color;
}

/// One Liquid Glass capsule in a [CNNavigationBar], holding one or more items.
///
/// Groups with the same [id] in consecutive configurations morph into each
/// other: the capsule resizes and moves, and items cross-fade inside it.
/// A group that disappears melts into its neighbour, a new one splits off.
class CNNavigationBarGroup {
  /// Creates a glass capsule containing [items].
  const CNNavigationBarGroup({
    this.id,
    required this.items,
    this.tint,
    this.width,
  });

  /// Creates a capsule holding a single icon button.
  CNNavigationBarGroup.icon(
    CNSymbol icon, {
    this.id,
    VoidCallback? onPressed,
    this.tint,
    this.width,
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

  /// Fixed capsule width; the height stays 44, so 44 keeps a circle. Labels
  /// then don't widen the capsule: they sit tight next to the icon and shrink
  /// to fit (e.g. a back chevron with an unread count). Null sizes the
  /// capsule to its content.
  final double? width;
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
/// With [axis] set to [Axis.vertical] the groups stack top to bottom in a
/// column [height] wide, like the vertical bars of iPhone Duo (iOS only; the
/// macOS bar stays horizontal). [CNNavigationBarScope] switches automatically.
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
    this.axis = Axis.horizontal,
  });

  /// Default bar height.
  static const double defaultHeight = 56.0;

  /// Glass groups aligned to the leading edge.
  final List<CNNavigationBarGroup> leading;

  /// Glass groups aligned to the trailing edge.
  final List<CNNavigationBarGroup> trailing;

  /// Height of a horizontal bar, or width of a vertical one.
  final double height;

  /// Inset of the outermost groups from the screen edges (horizontal bar).
  final double horizontalPadding;

  /// Gap between neighbouring groups on the same side.
  final double groupSpacing;

  /// Identity of the screen the buttons belong to. When it changes the update
  /// counts as navigation and every capsule plays the glass pulse (swell and
  /// blur), as on a push or pop; otherwise only the capsules that changed do.
  final Object? pageKey;

  /// [Axis.horizontal] lays the groups out leading/trailing across the top;
  /// [Axis.vertical] stacks them from the top of a side column (leading
  /// groups first), showing icons only — give every item an [icon]; a
  /// text-only item is shrunk to fit the 44pt-wide capsule. Changes animate.
  final Axis axis;

  @override
  State<CNNavigationBar> createState() => _CNNavigationBarState();
}

class _CNNavigationBarState extends State<CNNavigationBar>
    with WidgetsBindingObserver {
  MethodChannel? _channel;
  String? _lastSignature;
  Object? _lastPageKey;
  bool? _lastIsDark;
  bool _lastVertical = false;
  Map<String, Object?> _lastItems = const {};
  Map<String, VoidCallback> _callbacks = const {};

  /// Frame of each glass group (bar coordinates, keyed by group id) as last
  /// reported by the native bar; null until the first report.
  Map<String, Rect>? _hitFrames;

  bool get _useNative =>
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) &&
      PlatformVersion.shouldUseNativeGlass;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the background or a system sheet: make sure the hit regions
    // match what is on screen.
    if (state == AppLifecycleState.resumed) _requestFrames();
  }

  void _requestFrames() {
    _channel?.invokeMethod('requestFrames').catchError((_) {});
  }

  /// Hit regions for the groups in [groupIds]. Falls back to the whole bar
  /// (null) while any visible group has no known frame, so a missed native
  /// report costs at most a moment of untappable title — never dead buttons.
  List<Rect>? _hitRectsFor(List<String> groupIds) {
    if (groupIds.isEmpty) return const [];
    final frames = _hitFrames;
    if (frames == null || groupIds.any((id) => !frames.containsKey(id))) {
      return null;
    }

    return [for (final id in groupIds) frames[id]!];
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
            if (group.width != null) 'width': group.width,
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
                    if (item.labelSize != null) 'labelSize': item.labelSize,
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
        final byId = {
          for (final f in frames.cast<Map>())
            f['id'] as String: Rect.fromLTWH(
              (f['x'] as num).toDouble(),
              (f['y'] as num).toDouble(),
              (f['w'] as num).toDouble(),
              (f['h'] as num).toDouble(),
            ),
        };
        if (mounted) setState(() => _hitFrames = byId);
      }
    });
    // Items may have changed between the first build (creation params) and
    // the view being created; resync without animating.
    channel.invokeMethod('setItems', {..._lastItems, 'animated': false});
    if (_lastIsDark != null) {
      channel.invokeMethod('setBrightness', {'isDark': _lastIsDark});
    }
    if (_lastVertical) channel.invokeMethod('setVertical', {'vertical': true});
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
    // The macOS bar has no vertical layout.
    final vertical =
        widget.axis == Axis.vertical &&
        defaultTargetPlatform == TargetPlatform.iOS;

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
        // New screen: re-sync the hit regions even if no geometry changed.
        if (pageChanged) _requestFrames();
      }
      if (isDark != _lastIsDark) {
        channel.invokeMethod('setBrightness', {'isDark': isDark});
      }
      if (vertical != _lastVertical) {
        channel.invokeMethod('setVertical', {'vertical': vertical});
      }
    }
    _lastSignature = signature;
    _lastVertical = vertical;
    _lastPageKey = widget.pageKey;
    _lastIsDark = isDark;
    _lastItems = {'leading': leading, 'trailing': trailing};

    final creationParams = <String, Object?>{
      'leading': leading,
      'trailing': trailing,
      'horizontalPadding': widget.horizontalPadding,
      'groupSpacing': widget.groupSpacing,
      'isDark': isDark,
      'vertical': vertical,
    };

    const viewType = 'CNNavigationBar';
    // Only the glass groups take touches; the rest of the bar lets them
    // through to whatever is underneath (e.g. a tappable page title).
    final groupIds = [
      for (final group in [...leading, ...trailing]) group['id']! as String,
    ];
    return _CNHitRegions(
      rects: _hitRectsFor(groupIds),
      child: SizedBox(
        height: vertical ? double.infinity : widget.height,
        width: vertical ? widget.height : double.infinity,
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
    final vertical = widget.axis == Axis.vertical;
    Widget side(List<CNNavigationBarGroup> groups, String name) {
      return Flex(
        direction: widget.axis,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var g = 0; g < groups.length; g++) ...[
            if (g > 0) SizedBox.square(dimension: widget.groupSpacing),
            _FallbackGroup(group: groups[g], vertical: vertical),
          ],
        ],
      );
    }

    if (vertical) {
      return SizedBox(
        width: widget.height,
        height: double.infinity,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Column(
            key: ValueKey(_fallbackKey()),
            children: [
              side(widget.leading, 'leading'),
              SizedBox(height: widget.groupSpacing * 2),
              side(widget.trailing, 'trailing'),
            ],
          ),
        ),
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
  const _FallbackGroup({required this.group, this.vertical = false});

  final CNNavigationBarGroup group;

  /// One 44pt icon-only item per row, as in the native vertical bar.
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final tint = group.tint;
    final background =
        tint ?? CupertinoColors.tertiarySystemFill.resolveFrom(context);
    final foreground = tint != null
        ? CupertinoColors.white
        : CupertinoColors.label.resolveFrom(context);
    final fixedWidth = vertical ? 44.0 : group.width;
    final compact = fixedWidth != null;

    Widget content(CNNavigationBarItem item) {
      final color = item._effectiveColor ?? foreground;
      if (vertical && item.icon != null) {
        return Icon(
          _fallbackIcon(item.icon!.name),
          size: item.icon!.size + 3,
          color: color,
          semanticLabel: item.label,
        );
      }

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.icon != null)
            Icon(
              _fallbackIcon(item.icon!.name),
              size: item.icon!.size + 3,
              color: color,
            ),
          if (item.icon != null && item.label != null)
            SizedBox(width: compact ? 1 : 6),
          if (item.label != null)
            Text(
              item.label!,
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontSize: item.labelSize ?? 17,
                fontWeight: compact ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
        ],
      );
    }

    if (vertical) {
      return Container(
        width: fixedWidth,
        padding: EdgeInsets.symmetric(vertical: group.items.length > 1 ? 6 : 0),
        decoration: ShapeDecoration(
          color: background,
          shape: const StadiumBorder(),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in group.items)
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                onPressed: item.enabled ? item.onPressed : null,
                child: FittedBox(fit: BoxFit.scaleDown, child: content(item)),
              ),
          ],
        ),
      );
    }

    return Container(
      height: 44,
      width: fixedWidth,
      padding: EdgeInsets.symmetric(
        horizontal: !compact && group.items.length > 1 ? 6 : 0,
      ),
      decoration: ShapeDecoration(
        color: background,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final item in group.items)
            compact
                // Fixed width: items share the capsule and shrink to fit.
                ? Expanded(
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: const Size(0, 44),
                      onPressed: item.enabled ? item.onPressed : null,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: content(item),
                      ),
                    ),
                  )
                : CupertinoButton(
                    padding: EdgeInsets.symmetric(
                      horizontal: item.label != null ? 14 : 0,
                    ),
                    minimumSize: const Size(44, 44),
                    onPressed: item.enabled ? item.onPressed : null,
                    child: content(item),
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

/// Where a [CNNavigationBarScope] lays out its vertical bar column, for
/// placing other bar content (e.g. a vertical [CNTabBar]) in the same
/// column. All values are in the scope's coordinates.
@immutable
class CNVerticalBarColumn {
  /// Creates a column description.
  const CNVerticalBarColumn({
    required this.edge,
    required this.inset,
    required this.width,
    required this.top,
    required this.bottom,
  });

  /// The side of the scope the column is on.
  final CNVerticalBarEdge edge;

  /// Distance of the column from [edge].
  final double inset;

  /// Width of the column.
  final double width;

  /// Where the column starts: below the status bar and camera.
  final double top;

  /// Where the column ends, measured from the bottom: the bottom safe area.
  /// A vertical tab bar sits flush on it:
  ///
  /// ```dart
  /// Positioned(
  ///   right: column.edge == CNVerticalBarEdge.right ? column.inset : null,
  ///   left: column.edge == CNVerticalBarEdge.left ? column.inset : null,
  ///   bottom: column.bottom,
  ///   child: CNTabBar(axis: Axis.vertical, ...),
  /// )
  /// ```
  final double bottom;

  @override
  bool operator ==(Object other) =>
      other is CNVerticalBarColumn &&
      other.edge == edge &&
      other.inset == inset &&
      other.width == width &&
      other.top == top &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(edge, inset, width, top, bottom);
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
/// Where the system puts bars on a side edge (iPhone Duo, see
/// [CNDisplayLayout.verticalBarEdge]) the bar becomes a column on that edge,
/// below the status bar and camera, and the scope adds the column to the
/// [MediaQuery] padding on that side so [SafeArea]s below keep clear of it.
/// Pages can check [verticalEdgeOf] to drop the space they leave at the top,
/// and [verticalColumnOf] gives the column itself, e.g. to put a vertical
/// [CNTabBar] at its bottom. The navigation buttons take only the top of the
/// column, as tall as their capsules.
/// A scope that doesn't reach that edge — its [MediaQuery] padding there is
/// zero, e.g. inside a sheet inset from the side safe areas — keeps a
/// horizontal bar.
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

  /// The edge the enclosing scope's bar is drawn on as a vertical column, or
  /// null while it is a horizontal bar at the top (or there is no scope).
  static CNVerticalBarEdge? verticalEdgeOf(BuildContext context) =>
      verticalColumnOf(context)?.edge;

  /// The enclosing scope's vertical bar column, or null while its bar is
  /// horizontal (or there is no scope). Reported whether or not the visible
  /// page has navigation buttons.
  static CNVerticalBarColumn? verticalColumnOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_CNNavigationBarScopeMarker>()
      ?.column;

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

  /// Where the system puts vertical bars; only followed by the native iOS bar.
  ValueListenable<CNDisplayLayout>? _displayLayout;

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        PlatformVersion.shouldUseNativeGlass) {
      _displayLayout = CNDisplayLayout.listenable
        ..addListener(_onDisplayLayout);
    }
  }

  @override
  void dispose() {
    _displayLayout?.removeListener(_onDisplayLayout);
    _unmountTimer?.cancel();
    super.dispose();
  }

  void _onDisplayLayout() {
    if (mounted) setState(() {});
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
    final layout = _displayLayout?.value ?? CNDisplayLayout.empty;
    final padding = MediaQuery.paddingOf(context);
    // Go vertical only if the scope reaches the side the system bars sit on
    // (its safe area has an inset there), like a view's safeAreaInsets, and
    // no enclosing scope already owns that column: a nested scope would see
    // the column's raised padding and place itself with window coordinates
    // that aren't its own.
    final nested = CNNavigationBarScope.verticalColumnOf(context) != null;
    final edge = nested
        ? null
        : switch (layout.verticalBarEdge) {
            CNVerticalBarEdge.left when padding.left > 0 =>
              CNVerticalBarEdge.left,
            CNVerticalBarEdge.right when padding.right > 0 =>
              CNVerticalBarEdge.right,
            _ => null,
          };

    final column = edge == null
        ? null
        : _verticalColumn(context, layout, edge, padding);
    var childPadding = padding;
    if (column != null) {
      // Content keeps clear of the column, as with the system's vertical
      // bars, which add to the safe area on their side.
      final reach = column.inset + column.width;
      childPadding = column.edge == CNVerticalBarEdge.left
          ? padding.copyWith(left: reach > padding.left ? reach : null)
          : padding.copyWith(right: reach > padding.right ? reach : null);
    }

    final Widget? bar;
    if (!_mountBar) {
      bar = null;
    } else if (column == null) {
      // Horizontal bar under the status bar, kept inside the side safe areas
      // (e.g. clear of a camera or status column on the right).
      bar = AnimatedPositioned(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        top: padding.top + _topInset,
        left: padding.left,
        right: padding.right,
        height: widget.height,
        child: _bar(active, Axis.horizontal),
      );
    } else {
      // Only as tall as the capsules, so the rest of the column (e.g. a
      // vertical tab bar at its bottom) stays free.
      bar = AnimatedPositioned(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        top: column.top,
        height: _verticalExtent(active),
        left: column.edge == CNVerticalBarEdge.left ? column.inset : null,
        right: column.edge == CNVerticalBarEdge.right ? column.inset : null,
        width: column.width,
        child: _bar(active, Axis.vertical),
      );
    }

    return _CNNavigationBarScopeMarker(
      state: this,
      column: column,
      child: Stack(
        children: [
          // Always wrapped, so switching axis doesn't rebuild the subtree.
          Positioned.fill(
            child: _CNPaddingOverride(
              padding: childPadding,
              child: widget.child,
            ),
          ),
          ?bar,
        ],
      ),
    );
  }

  Widget _bar(CNNavigationBarItems? active, Axis axis) => CNNavigationBar(
    leading: active?.leading ?? const [],
    trailing: active?.trailing ?? const [],
    height: widget.height,
    horizontalPadding: widget.horizontalPadding,
    groupSpacing: widget.groupSpacing,
    pageKey: _active,
    axis: axis,
  );

  /// Height of the vertical bar's content, matching the native layout: 44pt
  /// per item, multi-item capsules padded by 6 at each end, [groupSpacing]
  /// between capsules and twice that between the leading and trailing
  /// stacks, plus 6 above and below for the glass pulse.
  double _verticalExtent(CNNavigationBarItems? active) {
    double side(List<CNNavigationBarGroup> groups) {
      if (groups.isEmpty) return 0;
      var extent = widget.groupSpacing * (groups.length - 1);
      for (final group in groups) {
        extent += group.items.length * 44 + (group.items.length > 1 ? 12 : 0);
      }
      return extent;
    }

    final leading = side(active?.leading ?? const []);
    final trailing = side(active?.trailing ?? const []);
    final between = leading > 0 && trailing > 0 ? widget.groupSpacing * 2 : 0;
    return leading + between + trailing + 12;
  }

  /// Places the vertical bar on [edge]: centred on the camera at the top of
  /// that side's safe-area strip, like the status items, else in the strip
  /// when it is wide enough (otherwise flush with the screen edge),
  /// starting below whatever the system keeps at the top of the strip — the
  /// status bar, the camera — or the top safe area.
  CNVerticalBarColumn _verticalColumn(
    BuildContext context,
    CNDisplayLayout layout,
    CNVerticalBarEdge edge,
    EdgeInsets padding,
  ) {
    final width = MediaQuery.sizeOf(context).width;
    final strip = edge == CNVerticalBarEdge.left ? padding.left : padding.right;
    var inset = strip >= widget.height ? (strip - widget.height) / 2 : 0.0;
    // The system centres its status items (clock, Wi-Fi) on the camera, not
    // on the safe-area strip: line up with the narrowest occlusion at the top
    // of the strip when there is one.
    final stripLeft = edge == CNVerticalBarEdge.left ? 0.0 : width - strip;
    final stripRight = stripLeft + strip;
    final cameras =
        layout
            .regions(CNReservedRegionKind.occlusion)
            .map((r) => r.frame)
            .where(
              (f) =>
                  f.left >= stripLeft - 1 &&
                  f.right <= stripRight + 1 &&
                  f.top < padding.top + 44,
            )
            .toList()
          ..sort((a, b) => a.width.compareTo(b.width));
    if (strip > 0 && cameras.isNotEmpty) {
      final centre = cameras.first.center.dx;
      final fromEdge = edge == CNVerticalBarEdge.left ? centre : width - centre;
      inset = (fromEdge - widget.height / 2).clamp(0.0, double.infinity);
    }
    final left = edge == CNVerticalBarEdge.left
        ? inset
        : width - inset - widget.height;
    final right = left + widget.height;

    // Walk down from the top safe area past whatever sits in the column's
    // path. Only things starting before there's room for a button count, so
    // an occlusion further down the edge doesn't push the whole column.
    var top = padding.top;
    final above = [
      ?layout.statusBarFrame,
      for (final r in layout.regions(CNReservedRegionKind.occlusion)) r.frame,
    ]..sort((a, b) => a.top.compareTo(b.top));
    for (final rect in above) {
      if (rect.left < right &&
          rect.right > left &&
          rect.top < top + 44 &&
          rect.bottom > top) {
        top = rect.bottom;
      }
    }
    return CNVerticalBarColumn(
      edge: edge,
      inset: inset,
      width: widget.height,
      top: top + _topInset,
      bottom: padding.bottom,
    );
  }
}

/// Overrides the [MediaQuery] padding for [child]. Kept out of the scope's
/// own build so the scope depends only on padding and size, not on every
/// MediaQuery change (e.g. each frame of the keyboard animation).
class _CNPaddingOverride extends StatelessWidget {
  const _CNPaddingOverride({required this.padding, required this.child});

  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(padding: padding),
    child: child,
  );
}

class _CNNavigationBarScopeMarker extends InheritedWidget {
  const _CNNavigationBarScopeMarker({
    required this.state,
    required this.column,
    required super.child,
  });

  final _CNNavigationBarScopeState state;

  final CNVerticalBarColumn? column;

  @override
  bool updateShouldNotify(_CNNavigationBarScopeMarker oldWidget) =>
      !identical(state, oldWidget.state) || column != oldWidget.column;
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
