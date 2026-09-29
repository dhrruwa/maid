import 'package:flutter/material.dart';

import '../widgets/glass.dart';

import 'calendar/calendar_screen.dart';
import 'history/history_screen.dart';
import 'home/home_screen.dart';
import 'menu/menu_screen.dart';
import 'settings/settings_screen.dart';

/// Bottom navigation: Home, Calendar, Menu, History. Settings top-right.
class Shell extends StatefulWidget {
  const Shell({super.key});

  static void goTo(BuildContext context, int tab) =>
      context.findAncestorStateOfType<_ShellState>()?.setTab(tab);

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  final _visited = <int>{0};

  void setTab(int t) => setState(() {
        _tab = t;
        _visited.add(t);
      });

  static const _titles = ['Home', 'Calendar', 'Menu', 'History'];

  @override
  Widget build(BuildContext context) {
    final pages = [
      const HomeScreen(),
      const CalendarScreen(),
      const MenuScreen(),
      const HistoryScreen(),
    ];
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
      // Content scrolls under the frosted tab bar.
      extendBody: true,
      body: BackdropGroup(
        child: IndexedStack(
          index: _tab,
          children: [
            for (var i = 0; i < pages.length; i++) _visited.contains(i) ? pages[i] : const SizedBox.shrink(),
          ],
        ),
      ),
      bottomNavigationBar: GlassNavBar(
        index: _tab,
        onTap: setTab,
        items: const [
          GlassNavItem(Icons.home_outlined, Icons.home, 'Home'),
          GlassNavItem(Icons.calendar_month_outlined, Icons.calendar_month, 'Calendar'),
          GlassNavItem(Icons.menu_book_outlined, Icons.menu_book, 'Menu'),
          GlassNavItem(Icons.receipt_long_outlined, Icons.receipt_long, 'History'),
        ],
      ),
    );
  }
}
