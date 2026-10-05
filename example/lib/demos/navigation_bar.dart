import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart';

/// Morphing glass navigation bar demo.
///
/// One [CNNavigationBarScope] sits above a nested [Navigator], so the glass
/// buttons stay on screen and morph as you go Chats -> chat -> info and back
/// (tap the back button or swipe from the left edge). Each screen also has
/// switches that change its buttons in place.
class NavigationBarDemoPage extends StatelessWidget {
  const NavigationBarDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    void exitDemo() => Navigator.of(context).pop();
    return CNNavigationBarScope(
      child: Navigator(
        onGenerateRoute: (_) => CupertinoPageRoute(builder: (_) => _ChatsPage(onExit: exitDemo)),
      ),
    );
  }
}

const _chats = <(String, String, Color)>[
  ('yophone: ', 'Hi: Please confirm by Friday', Color(0xFFFF6B4A)),
  ('Design team', 'New glass mockups are up', Color(0xFF5E5CE6)),
  ('Mom', 'Call me when you can', Color(0xFF34C759)),
  ('Flutter devs', 'PR #72 is merged', Color(0xFF0A84FF)),
  ('Weekend trip', 'Who is driving?', Color(0xFFFF9F0A)),
  ('Karine', 'Thanks!', Color(0xFFBF5AF2)),
];

/// Space a page leaves for the floating bar under the status bar.
const double _barHeight = CNNavigationBar.defaultHeight;

// ---------------------------------------------------------------------------
// Screen 1: chat list
// ---------------------------------------------------------------------------

class _ChatsPage extends StatefulWidget {
  const _ChatsPage({required this.onExit});

  final VoidCallback onExit;

  @override
  State<_ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<_ChatsPage> {
  bool _selecting = false;
  bool _hideCamera = false;

  void _showMenu() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              setState(() => _selecting = true);
            },
            child: const Text('Select chats'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.of(sheetContext).pop();
              widget.onExit();
            },
            child: const Text('Exit demo'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final leading = _selecting
        ? [
            CNNavigationBarGroup(
              items: [
                CNNavigationBarItem(
                  label: 'Done',
                  onPressed: () => setState(() => _selecting = false),
                ),
              ],
            ),
          ]
        : [CNNavigationBarGroup.icon(const CNSymbol('ellipsis'), onPressed: _showMenu)];

    final trailing = _selecting
        ? [
            CNNavigationBarGroup(
              items: [
                CNNavigationBarItem(icon: const CNSymbol('archivebox'), onPressed: () {}),
                CNNavigationBarItem(
                  icon: const CNSymbol('trash', color: CupertinoColors.systemRed),
                  onPressed: () {},
                ),
              ],
            ),
          ]
        : [
            if (!_hideCamera) CNNavigationBarGroup.icon(const CNSymbol('camera'), onPressed: () {}),
            CNNavigationBarGroup.icon(
              const CNSymbol('plus', size: 19),
              tint: CupertinoColors.systemGreen,
              onPressed: () {},
            ),
          ];

    return CNNavigationBarItems(
      leading: leading,
      trailing: trailing,
      child: CupertinoPageScaffold(
        child: ListView(
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + _barHeight, bottom: 32),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text('Chats', style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
            ),
            const _FakeSearchField(),
            CupertinoListSection.insetGrouped(
              header: const Text('Change the bar on this screen'),
              children: [
                _SwitchTile(
                  title: 'Selection mode',
                  value: _selecting,
                  onChanged: (v) => setState(() => _selecting = v),
                ),
                _SwitchTile(
                  title: 'Hide camera button',
                  value: _hideCamera,
                  onChanged: (v) => setState(() => _hideCamera = v),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('Tap a chat to push a new screen'),
              children: [
                for (final chat in _chats)
                  CupertinoListTile(
                    leading: _Avatar(name: chat.$1, color: chat.$3, size: 32),
                    title: Text(chat.$1),
                    subtitle: Text(chat.$2),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () => Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (_) => _ChatPage(name: chat.$1, color: chat.$3),
                      ),
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

// ---------------------------------------------------------------------------
// Screen 2: a chat
// ---------------------------------------------------------------------------

class _ChatPage extends StatefulWidget {
  const _ChatPage({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  State<_ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<_ChatPage> {
  bool _phoneInCapsule = false;
  bool _separatePhone = false;
  bool _search = false;
  bool _tintVideo = false;

  void _openInfo() {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => _InfoPage(name: widget.name, color: widget.color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return CNNavigationBarItems(
      leading: [
        CNNavigationBarGroup.icon(
          const CNSymbol('chevron.left', size: 19),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      trailing: [
        if (_search)
          CNNavigationBarGroup.icon(
            const CNSymbol('magnifyingglass'),
            id: 'search',
            onPressed: () {},
          ),
        if (_separatePhone)
          CNNavigationBarGroup.icon(const CNSymbol('phone'), id: 'phone', onPressed: () {}),
        CNNavigationBarGroup(
          id: 'call',
          tint: _tintVideo ? CupertinoColors.systemGreen : null,
          items: [
            CNNavigationBarItem(icon: const CNSymbol('video'), onPressed: () {}),
            if (_phoneInCapsule)
              CNNavigationBarItem(icon: const CNSymbol('phone'), onPressed: () {})
            else
              CNNavigationBarItem(icon: const CNSymbol('chevron.down', size: 12), onPressed: () {}),
          ],
        ),
      ],
      child: CupertinoPageScaffold(
        child: Stack(
          children: [
            ListView(
              padding: EdgeInsets.only(top: top + _barHeight + 8, bottom: 32),
              children: [
                const _Bubble(text: 'Please confirm attendance by Friday 🙏', incoming: true),
                const _Bubble(text: 'Confirmed, see you there', incoming: false),
                CupertinoListSection.insetGrouped(
                  header: const Text('Change the bar on this screen'),
                  children: [
                    _SwitchTile(
                      title: 'Phone inside the video capsule',
                      value: _phoneInCapsule,
                      onChanged: (v) => setState(() => _phoneInCapsule = v),
                    ),
                    _SwitchTile(
                      title: 'Separate phone button',
                      value: _separatePhone,
                      onChanged: (v) => setState(() => _separatePhone = v),
                    ),
                    _SwitchTile(
                      title: 'Search button',
                      value: _search,
                      onChanged: (v) => setState(() => _search = v),
                    ),
                    _SwitchTile(
                      title: 'Tint the call capsule',
                      value: _tintVideo,
                      onChanged: (v) => setState(() => _tintVideo = v),
                    ),
                  ],
                ),
                CupertinoListSection.insetGrouped(
                  children: [
                    CupertinoListTile(
                      title: const Text('Open group info'),
                      trailing: const CupertinoListTileChevron(),
                      onTap: _openInfo,
                    ),
                  ],
                ),
              ],
            ),
            // Title row: lives in the page (so it slides with the push) and
            // sits in the transparent middle of the bar, which lets taps
            // through to it.
            Positioned(
              top: top,
              left: 16 + 44 + 10,
              right: 120,
              height: _barHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openInfo,
                child: Row(
                  children: [
                    _Avatar(name: widget.name, color: widget.color, size: 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '2 online',
                            style: TextStyle(
                              fontSize: 12,
                              color: CupertinoColors.secondaryLabel.resolveFrom(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen 3: group info
// ---------------------------------------------------------------------------

class _InfoPage extends StatefulWidget {
  const _InfoPage({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  State<_InfoPage> createState() => _InfoPageState();
}

class _InfoPageState extends State<_InfoPage> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    return CNNavigationBarItems(
      leading: [
        CNNavigationBarGroup.icon(
          const CNSymbol('chevron.left', size: 19),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      trailing: [
        _editing
            ? CNNavigationBarGroup(
                tint: CupertinoColors.systemBlue,
                items: [
                  CNNavigationBarItem(
                    label: 'Done',
                    onPressed: () => setState(() => _editing = false),
                  ),
                ],
              )
            : CNNavigationBarGroup(
                items: [
                  CNNavigationBarItem(icon: const CNSymbol('qrcode'), onPressed: () {}),
                  CNNavigationBarItem(
                    icon: const CNSymbol('ellipsis'),
                    onPressed: () => setState(() => _editing = true),
                  ),
                ],
              ),
      ],
      child: CupertinoPageScaffold(
        child: ListView(
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + _barHeight, bottom: 32),
          children: [
            Center(
              child: _Avatar(name: widget.name, color: widget.color, size: 96),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                widget.name,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'Group · 10 members',
                style: TextStyle(color: CupertinoColors.secondaryLabel.resolveFrom(context)),
              ),
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('Change the bar on this screen'),
              footer: const Text('The ••• button also turns on edit mode.'),
              children: [
                _SwitchTile(
                  title: 'Edit mode',
                  value: _editing,
                  onChanged: (v) => setState(() => _editing = v),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              children: [
                CupertinoListTile(
                  title: const Text('Open another chat'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (_) => _ChatPage(name: _chats[1].$1, color: _chats[1].$3),
                    ),
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

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({required this.title, required this.value, required this.onChanged});

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      title: Text(title),
      trailing: CupertinoSwitch(value: value, onChanged: onChanged),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.color, required this.size});

  final String name;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        name.characters.first.toUpperCase(),
        style: TextStyle(
          color: CupertinoColors.white,
          fontSize: size * 0.45,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _FakeSearchField extends StatelessWidget {
  const _FakeSearchField();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.search,
              size: 18,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
            const SizedBox(width: 8),
            Text(
              'Search',
              style: TextStyle(color: CupertinoColors.secondaryLabel.resolveFrom(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.incoming});

  final String text;
  final bool incoming;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: incoming ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: incoming
              ? CupertinoColors.secondarySystemFill.resolveFrom(context)
              : CupertinoColors.systemGreen.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: incoming ? CupertinoColors.label.resolveFrom(context) : CupertinoColors.white,
          ),
        ),
      ),
    );
  }
}
