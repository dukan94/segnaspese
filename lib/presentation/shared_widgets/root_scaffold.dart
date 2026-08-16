import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/responsive.dart';

/// Una voce di navigazione, condivisa tra bottom bar e [NavigationRail] così
/// le 4 destinazioni si dichiarano una sola volta invece di due (M26).
class _NavEntry {
  const _NavEntry(this.icon, this.selectedIcon, this.label);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const _navEntries = [
  _NavEntry(Icons.home_outlined, Icons.home, 'Home'),
  _NavEntry(Icons.bar_chart_outlined, Icons.bar_chart, 'Dashboard'),
  _NavEntry(Icons.savings_outlined, Icons.savings, 'Budget'),
  _NavEntry(Icons.apps_outlined, Icons.apps, 'Altro'),
];

/// Scaffold condiviso da tutte le tab principali (Home · Dashboard · Budget ·
/// Altro; le sezioni secondarie — Storico, Ricorrenze, Impostazioni — sono
/// raggruppate sotto "Altro"). Bottom navigation bar su finestra stretta
/// (Android, o Windows ridotta), [NavigationRail] su finestra larga — pattern
/// Material pensato per mouse (M26, refactor desktop richiesto da Mario il
/// 16 ago 2026: v. progettazione, sezione "Fondamenta layout
/// desktop-adattivo").
class RootScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const RootScaffold({super.key, required this.navigationShell});

  void _onSelect(int index) => navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      );

  @override
  Widget build(BuildContext context) {
    if (isWideWindow(context)) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _onSelect,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final e in _navEntries)
                  NavigationRailDestination(
                    icon: Icon(e.icon),
                    selectedIcon: Icon(e.selectedIcon),
                    label: Text(e.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: navigationShell),
          ],
        ),
      );
    }

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onSelect,
        destinations: [
          for (final e in _navEntries)
            NavigationDestination(
              icon: Icon(e.icon),
              selectedIcon: Icon(e.selectedIcon),
              label: e.label,
            ),
        ],
      ),
    );
  }
}
