import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Regression checks for CNNavigationBar hit testing.
///
/// The glass buttons only take touches inside the frames the native bar
/// reports; everything else falls through to Flutter. Several lifecycle paths
/// used to leave those frames missing, so the buttons stopped responding:
/// a full-screen native modal (QuickLook, share sheet), or a page without bar
/// buttons pushed and popped quickly (a camera screen). "Run checks" replays
/// each path and hit-tests both capsules afterwards.
class NavigationBarHitTestPage extends StatelessWidget {
  const NavigationBarHitTestPage({super.key});

  @override
  Widget build(BuildContext context) {
    void exit() => Navigator.of(context).pop();

    return CNNavigationBarScope(
      child: Navigator(
        onGenerateRoute: (_) => CupertinoPageRoute(builder: (_) => _ChecksPage(onExit: exit)),
      ),
    );
  }
}

class _Result {
  const _Result(this.name, this.leading, this.trailing, this.middleFree, {this.skipped = false});

  final String name;
  final bool leading;
  final bool trailing;

  /// The empty middle of the bar must not take touches (page titles there
  /// must stay tappable) — guards against the bar over-blocking.
  final bool middleFree;
  final bool skipped;

  bool get passed => skipped || (leading && trailing && middleFree);
}

class _ChecksPage extends StatefulWidget {
  const _ChecksPage({required this.onExit});

  final VoidCallback onExit;

  @override
  State<_ChecksPage> createState() => _ChecksPageState();
}

class _ChecksPageState extends State<_ChecksPage> {
  static const _modalChannel = MethodChannel('cn_example/full_screen_modal');

  final List<_Result> _results = [];
  bool _running = false;
  int _taps = 0;

  Future<void> _wait(int ms) => Future.delayed(Duration(milliseconds: ms));

  /// Whether a tap at the centre of the leading / trailing capsule lands on
  /// the bar's native view (instead of falling through to Flutter).
  ({bool leading, bool trailing, bool middleFree}) _probe() {
    final view = View.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final width = MediaQuery.sizeOf(context).width;
    bool hits(Offset position) {
      final result = HitTestResult();
      WidgetsBinding.instance.hitTestInView(result, position, view.viewId);

      return result.path.any((entry) => entry.target is RenderUiKitView);
    }

    const centerY = CNNavigationBar.defaultHeight / 2;
    return (
      leading: hits(Offset(16 + 22, top + centerY)),
      trailing: hits(Offset(width - 16 - 22, top + centerY)),
      middleFree: !hits(Offset(width / 2, top + centerY)),
    );
  }

  void _record(String name) {
    final probe = _probe();
    setState(() => _results.add(_Result(name, probe.leading, probe.trailing, probe.middleFree)));
  }

  Future<void> _pushAndPop(String name, int holdMs, {bool lockOrientation = false}) async {
    final navigator = Navigator.of(context);
    navigator.push(
      CupertinoPageRoute(builder: (_) => _NoButtonsPage(lockOrientation: lockOrientation)),
    );
    await _wait(holdMs);
    navigator.pop();
    await _wait(1500);
    if (mounted) _record(name);
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _results.clear();
    });
    _record('Baseline');
    await _pushAndPop('Page without buttons, popped after 150 ms', 150);
    await _pushAndPop('Page without buttons, popped after 600 ms', 600);
    await _pushAndPop('Page without buttons, popped after 1.5 s (bar view rebuilt)', 1500);
    await _pushAndPop('Portrait-locked page, popped after 150 ms', 150, lockOrientation: true);
    try {
      await _modalChannel.invokeMethod('present');
      await _wait(1000);
      if (mounted) _record('Full-screen native modal');
    } on MissingPluginException {
      setState(
        () => _results.add(
          const _Result('Full-screen native modal', false, false, false, skipped: true),
        ),
      );
    }
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final failed = _results.where((r) => !r.passed).length;

    return CNNavigationBarItems(
      leading: [
        CNNavigationBarGroup.icon(
          const CNSymbol('chevron.left', size: 17),
          onPressed: widget.onExit,
        ),
      ],
      trailing: [
        CNNavigationBarGroup.icon(
          const CNSymbol('plus', size: 19),
          onPressed: () => setState(() => _taps++),
        ),
      ],
      child: CupertinoPageScaffold(
        child: ListView(
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top + CNNavigationBar.defaultHeight + 8,
            bottom: 32,
          ),
          children: [
            CupertinoListSection.insetGrouped(
              header: const Text('Navigation bar hit testing'),
              footer: Text(
                'Each check replays a lifecycle path, then hit-tests the ‹ and + capsules '
                '(must hit the bar) and the empty middle (must fall through to the page). '
                'Manual check: + taps so far: $_taps.',
              ),
              children: [
                CupertinoListTile(
                  title: Text(_running ? 'Running…' : 'Run checks'),
                  trailing: _running ? const CupertinoActivityIndicator() : null,
                  onTap: _running ? null : _run,
                ),
              ],
            ),
            if (_results.isNotEmpty)
              CupertinoListSection.insetGrouped(
                header: Text(
                  _running
                      ? 'Results'
                      : failed == 0
                      ? 'All passed'
                      : '$failed failed',
                ),
                children: [
                  for (final r in _results)
                    CupertinoListTile(
                      title: Text(r.name, maxLines: 2),
                      subtitle: Text(
                        r.skipped
                            ? 'skipped (no native channel)'
                            : '‹ ${r.leading ? 'ok' : 'DEAD'}   + ${r.trailing ? 'ok' : 'DEAD'}   '
                                  'middle ${r.middleFree ? 'free' : 'BLOCKED'}',
                      ),
                      trailing: Icon(
                        r.passed
                            ? CupertinoIcons.check_mark_circled_solid
                            : CupertinoIcons.xmark_circle_fill,
                        color: r.passed ? CupertinoColors.systemGreen : CupertinoColors.systemRed,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// A page that declares no bar buttons (like a camera screen); optionally
/// locks portrait while it is up, as camera screens often do.
class _NoButtonsPage extends StatefulWidget {
  const _NoButtonsPage({required this.lockOrientation});

  final bool lockOrientation;

  @override
  State<_NoButtonsPage> createState() => _NoButtonsPageState();
}

class _NoButtonsPageState extends State<_NoButtonsPage> {
  @override
  void initState() {
    super.initState();
    if (widget.lockOrientation) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  @override
  void dispose() {
    if (widget.lockOrientation) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const CupertinoPageScaffold(child: Center(child: Text('No bar buttons')));
  }
}
