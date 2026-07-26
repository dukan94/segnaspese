import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Scaffold condiviso da tutte le tab principali, con la bottom navigation
/// bar a 4 voci (Home · Dashboard · Budget · Altro). Le sezioni secondarie
/// (Storico, Ricorrenze, Impostazioni) sono raggruppate sotto "Altro".
class RootScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const RootScaffold({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.savings_outlined),
            selectedIcon: Icon(Icons.savings),
            label: 'Budget',
          ),
          NavigationDestination(
            icon: Icon(Icons.apps_outlined),
            selectedIcon: Icon(Icons.apps),
            label: 'Altro',
          ),
        ],
      ),
    );
  }
}
