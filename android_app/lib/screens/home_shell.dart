import 'package:flutter/material.dart';

import '../data/app_state.dart';
import 'add_expense.dart';
import 'expenses.dart';
import 'reports.dart';
import 'settings.dart';

/// Bottom navigation with the four tabs: Add, Expenses, Reports, Settings.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.app});
  final AppState app;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          AddExpenseScreen(app: widget.app),
          ExpensesScreen(app: widget.app),
          ReportsScreen(app: widget.app),
          SettingsScreen(app: widget.app),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.add_circle_outline),
              selectedIcon: Icon(Icons.add_circle),
              label: 'Add'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Expenses'),
          NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart),
              label: 'Reports'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings'),
        ],
      ),
    );
  }
}
