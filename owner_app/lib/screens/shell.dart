import 'package:flutter/material.dart';

import '../widgets/glass.dart';

import 'calendar/calendar_screen.dart';
import 'history/history_screen.dart';
import 'home/home_screen.dart';
import 'menu/menu_screen.dart';
import 'settings/settings_screen.dart';

/// Tabs Home, Calendar, Menu, History. Swipe left/right to move between them;
/// the glass lens in the tab bar follows the swipe. Settings top-right.
class Shell extends StatefulWidget {
  const Shell({super.key});

  static void goTo(BuildContext context, int tab) =>
      context.findAncestorStateOfType<_ShellState>()?.setTab(tab);

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final _pages = PageController();
  int _tab = 0;

  static const _titles = ['Home', 'Calendar', 'Menu', 'History'];
  static const _items = [
    GlassNavItem(Icons.home_outlined, Icons.home, 'Home'),
    GlassNavItem(Icons.calendar_month_outlined, Icons.calendar_month, 'Calendar'),
    GlassNavItem(Icons.menu_book_outlined, Icons.menu_book, 'Menu'),
    GlassNavItem(Icons.receipt_long_outlined, Icons.receipt_long, 'History'),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  bool get _reduceMotion => MediaQuery.of(context).disableAnimations;

  /// Fractional page position (e.g. 1.4 while swiping from Calendar to Menu).
  double get _position =>
      _pages.hasClients && _pages.position.haveDimensions ? (_pages.page ?? _tab.toDouble()) : _tab.toDouble();

  void setTab(int t) {
    if (!_pages.hasClients) return;
    if (_reduceMotion) {
      _pages.jumpToPage(t);
    } else {
      _pages.animateToPage(t, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    }
  }

  /// Dragging the lens along the tab bar scrolls the pages with it.
  void _dragTo(double fraction) {
    if (!_pages.hasClients) return;
    final max = (_items.length - 1).toDouble();
    _pages.jumpTo(fraction.clamp(0, max) * _pages.position.viewportDimension);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      // Content scrolls under the floating glass tab bar.
      extendBody: true,
      body: BackdropGroup(
        child: PageView(
          controller: _pages,
          onPageChanged: (i) => setState(() => _tab = i),
          children: const [
            _KeepAlive(child: HomeScreen()),
            _KeepAlive(child: CalendarScreen()),
            _KeepAlive(child: MenuScreen()),
            _KeepAlive(child: HistoryScreen()),
          ],
        ),
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: _pages,
        builder: (context, _) => GlassNavBar(
          position: _position,
          items: _items,
          onTap: setTab,
          onDrag: _dragTo,
          onDragEnd: () => setTab(_position.round()),
        ),
      ),
    );
  }
}

/// Keeps a tab's state (scroll position, loaded data) when it slides off screen.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
