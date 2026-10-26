import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart';

/// Shows [CNDisplayLayout] live: the vertical bar edge, the reserved regions
/// (drawn over the screen) and the safe area, under a [CNNavigationBarScope]
/// whose bar follows the edge, and a [CNTabBar] that moves into the bottom of
/// the vertical column when there is one. Open, close, fold and rotate the iPhone Duo
/// simulator (Xcode 27.1 Device Hub), or use Split View, to watch it change.
class DisplayLayoutDemoPage extends StatelessWidget {
  const DisplayLayoutDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CNNavigationBarScope(
      child: CNNavigationBarItems(
        leading: [
          CNNavigationBarGroup.icon(
            CNSymbol('chevron.backward'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
        trailing: [
          CNNavigationBarGroup(
            items: [
              CNNavigationBarItem(
                icon: CNSymbol('magnifyingglass'),
                label: 'Search',
                onPressed: () {},
              ),
              CNNavigationBarItem(
                icon: CNSymbol('ellipsis'),
                label: 'More',
                onPressed: () {},
              ),
            ],
          ),
          CNNavigationBarGroup.icon(
            CNSymbol('square.and.pencil'),
            tint: CupertinoColors.activeGreen,
            onPressed: () {},
          ),
        ],
        child: const _LayoutView(),
      ),
    );
  }
}

class _LayoutView extends StatefulWidget {
  const _LayoutView();

  @override
  State<_LayoutView> createState() => _LayoutViewState();
}

class _LayoutViewState extends State<_LayoutView> {
  int _tab = 0;

  static const _items = [
    CNTabBarItem(
      label: 'Chats',
      icon: CNSymbol('bubble.left.and.bubble.right'),
      badge: '3',
    ),
    CNTabBarItem(label: 'Calls', icon: CNSymbol('phone')),
    CNTabBarItem(label: 'Settings', icon: CNSymbol('gearshape')),
    CNTabBarItem(
      label: 'Profile',
      imageAsset: CNImageAsset('assets/profile.jpg', size: 28),
      originalColors: true,
    ),
  ];

  Widget _tabBar(CNVerticalBarColumn? column, EdgeInsets padding) {
    if (column == null) {
      return Positioned(
        left: 0,
        right: 0,
        bottom: padding.bottom,
        child: CNTabBar(
          items: _items,
          currentIndex: _tab,
          onTap: (i) => setState(() => _tab = i),
        ),
      );
    }
    // At the bottom of the vertical bar column, under the navigation buttons.
    return Positioned(
      left: column.edge == CNVerticalBarEdge.left ? column.inset : null,
      right: column.edge == CNVerticalBarEdge.right ? column.inset : null,
      bottom: column.bottom,
      child: CNTabBar(
        axis: Axis.vertical,
        items: _items,
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final column = CNNavigationBarScope.verticalColumnOf(context);
    final vertical = column != null;
    final padding = MediaQuery.paddingOf(context);
    return CupertinoPageScaffold(
      child: ValueListenableBuilder<CNDisplayLayout>(
        valueListenable: CNDisplayLayout.listenable,
        builder: (context, layout, _) => Stack(
          children: [
            // The scope's MediaQuery padding, so the column it adds is visible.
            Positioned.fill(
              child: Padding(
                padding: padding,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: CupertinoColors.systemBlue),
                  ),
                ),
              ),
            ),
            for (final region in layout.reservedRegions)
              Positioned.fromRect(
                rect: region.frame,
                child: ColoredBox(
                  color:
                      (region.kind == CNReservedRegionKind.division
                              ? CupertinoColors.systemRed
                              : CupertinoColors.systemOrange)
                          .withValues(alpha: region.isActive ? 0.45 : 0.15),
                ),
              ),
            SafeArea(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  vertical ? 16 : CNNavigationBar.defaultHeight + 16,
                  16,
                  16,
                ),
                children: [
                  Text(
                    'Display layout',
                    style: CupertinoTheme.of(
                      context,
                    ).textTheme.navLargeTitleTextStyle,
                  ),
                  const SizedBox(height: 12),
                  _row('Vertical bar edge', layout.verticalBarEdge?.name),
                  _row('Status bar', layout.statusBarFrame?.toString()),
                  _row('Safe area (with bar column)', padding.toString()),
                  for (final region in layout.reservedRegions)
                    _row(
                      '${region.kind.name}${region.isActive ? '' : ' (inactive)'}',
                      region.frame.toString(),
                    ),
                  if (layout.reservedRegions.isEmpty)
                    _row('Reserved regions', null),
                  _row('Selected tab', _items[_tab].label),
                  const SizedBox(height: 12),
                  const Text(
                    'Blue: safe area. Red: fold (division). Orange: camera '
                    '(occlusion). Faded regions are inactive. Needs an app '
                    'built with the iOS 27.1 SDK.',
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel,
                    ),
                  ),
                ],
              ),
            ),
            _tabBar(column, padding),
          ],
        ),
      ),
    );
  }

  Widget _row(String title, String? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(
          value ?? 'none',
          style: const TextStyle(color: CupertinoColors.secondaryLabel),
        ),
      ],
    ),
  );
}
