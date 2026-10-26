import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Screen edge where the system places vertical bars.
enum CNVerticalBarEdge {
  /// The left edge of the screen.
  left,

  /// The right edge of the screen.
  right,
}

/// Kind of a [CNReservedRegion].
enum CNReservedRegionKind {
  /// Splits the screen in two, e.g. the fold of iPhone Duo's inner display.
  division,

  /// Covers part of the screen, e.g. the inner display's FaceTime camera.
  occlusion,
}

/// A screen area reserved by the hardware (iOS 27.1 `UIView.ReservedRegion`).
@immutable
class CNReservedRegion {
  /// Creates a reserved region.
  const CNReservedRegion({
    required this.kind,
    required this.frame,
    this.margins = EdgeInsets.zero,
    required this.isActive,
  });

  /// Whether the region divides or occludes the screen.
  final CNReservedRegionKind kind;

  /// Frame in global logical pixels, including [margins].
  final Rect frame;

  /// Margins kept around the reserved area for interactive content.
  final EdgeInsets margins;

  /// Whether the region currently applies. A fold is inactive (and has zero
  /// width) while the device lies flat.
  final bool isActive;

  @override
  bool operator ==(Object other) =>
      other is CNReservedRegion &&
      other.kind == kind &&
      other.frame == frame &&
      other.margins == margins &&
      other.isActive == isActive;

  @override
  int get hashCode => Object.hash(kind, frame, margins, isActive);

  @override
  String toString() =>
      'CNReservedRegion(${kind.name}, $frame, active: $isActive)';
}

/// Display layout that foldable iPhones (iPhone Duo) add on top of the safe
/// area: where vertical bars go and which regions the hardware reserves.
///
/// Native bars move to a side edge on these devices; Flutter-drawn bars don't,
/// so read [verticalBarEdge] to lay them out the same way, and
/// [reservedRegions] to keep controls off the fold and camera.
///
/// ```dart
/// ValueListenableBuilder<CNDisplayLayout>(
///   valueListenable: CNDisplayLayout.listenable,
///   builder: (context, layout, _) => layout.verticalBarEdge == null
///       ? const TopBar()
///       : SideBar(edge: layout.verticalBarEdge!),
/// )
/// ```
///
/// Requires an app built with the iOS 27.1 SDK; elsewhere (older iOS, macOS,
/// other platforms) the layout stays [empty].
@immutable
class CNDisplayLayout {
  /// Creates a display layout.
  const CNDisplayLayout({
    this.verticalBarEdge,
    this.reservedRegions = const [],
    this.statusBarFrame,
  });

  /// No vertical bars and no reserved regions.
  static const empty = CNDisplayLayout();

  /// Edge where the system puts vertical bars, or null while bars stay
  /// horizontal (any device without them, the inner display in portrait).
  final CNVerticalBarEdge? verticalBarEdge;

  /// All reserved regions, inactive ones included.
  final List<CNReservedRegion> reservedRegions;

  /// Frame of the status bar in global logical pixels, if visible.
  final Rect? statusBarFrame;

  /// The reserved regions of [kind]; only active ones unless
  /// [includeInactive].
  Iterable<CNReservedRegion> regions(
    CNReservedRegionKind kind, {
    bool includeInactive = false,
  }) => reservedRegions.where(
    (r) => r.kind == kind && (includeInactive || r.isActive),
  );

  /// The current layout, updated when the device opens, closes, folds or
  /// rotates, and in Split View. Listening starts the native observer.
  static ValueListenable<CNDisplayLayout> get listenable {
    _DisplayLayoutChannel.ensureStarted();
    return _DisplayLayoutChannel.notifier;
  }

  /// The latest known layout (see [listenable]).
  static CNDisplayLayout get current => listenable.value;

  static CNDisplayLayout _decode(Object? raw) {
    if (raw is! Map) return empty;
    final edge = switch (raw['verticalBarEdge']) {
      'left' => CNVerticalBarEdge.left,
      'right' => CNVerticalBarEdge.right,
      _ => null,
    };
    final regions = <CNReservedRegion>[
      for (final r in (raw['reservedRegions'] as List? ?? const []).cast<Map>())
        CNReservedRegion(
          kind: r['kind'] == 'division'
              ? CNReservedRegionKind.division
              : CNReservedRegionKind.occlusion,
          frame: _rect(r['frame'])!,
          margins: _insets(r['margins']),
          isActive: r['active'] == true,
        ),
    ];
    return CNDisplayLayout(
      verticalBarEdge: edge,
      reservedRegions: regions,
      statusBarFrame: _rect(raw['statusBarFrame']),
    );
  }

  static Rect? _rect(Object? raw) {
    if (raw is! Map) return null;
    double v(String key) => (raw[key] as num).toDouble();
    return Rect.fromLTWH(v('x'), v('y'), v('w'), v('h'));
  }

  static EdgeInsets _insets(Object? raw) {
    if (raw is! Map) return EdgeInsets.zero;
    double v(String key) => (raw[key] as num?)?.toDouble() ?? 0;
    return EdgeInsets.fromLTRB(v('l'), v('t'), v('r'), v('b'));
  }

  @override
  bool operator ==(Object other) =>
      other is CNDisplayLayout &&
      other.verticalBarEdge == verticalBarEdge &&
      listEquals(other.reservedRegions, reservedRegions) &&
      other.statusBarFrame == statusBarFrame;

  @override
  int get hashCode => Object.hash(
    verticalBarEdge,
    Object.hashAll(reservedRegions),
    statusBarFrame,
  );

  @override
  String toString() =>
      'CNDisplayLayout(verticalBarEdge: ${verticalBarEdge?.name}, '
      'reservedRegions: $reservedRegions, statusBarFrame: $statusBarFrame)';
}

class _DisplayLayoutChannel {
  static const _channel = MethodChannel('cupertino_native/display_layout');
  static final notifier = ValueNotifier<CNDisplayLayout>(CNDisplayLayout.empty);
  static bool _started = false;

  static void ensureStarted() {
    if (_started) return;
    _started = true;
    // Only the iOS plugin reports a layout.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'layoutChanged') {
        notifier.value = CNDisplayLayout._decode(call.arguments);
      }
    });
    _channel
        .invokeMethod<Object?>('start')
        .then((raw) => notifier.value = CNDisplayLayout._decode(raw))
        .catchError((_) => CNDisplayLayout.empty);
  }
}
