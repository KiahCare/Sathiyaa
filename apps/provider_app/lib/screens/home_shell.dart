import 'package:flutter/material.dart';

import '../i18n/l10n.dart';
import '../theme/sathiyaa_theme.dart';
import '../widgets/sathiyaa_ui.dart';
import 'dashboard_screen.dart';
import 'bookings_screen.dart';
import 'calendar_screen.dart';
import 'time_bank_screen.dart';

/// Four tabs, matching the customer app.
///
/// Profile moved out of the bar and onto the avatar in the header — it is
/// visited rarely, and a five-slot pill bar crushes every label.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  void _go(int i) => setState(() => index = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(onGoToTab: _go),
      const BookingsScreen(),
      const CalendarScreen(),
      const TimeBankScreen(),
    ];

    return Scaffold(
      backgroundColor: SC.paper,
      extendBody: true,
      // Not wrapped in an AnimatedSwitcher: that keeps the outgoing subtree
      // mounted and paints two full-width stacks at once.
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: PillNavBar(
        index: index,
        onChanged: _go,
        // Not const: the labels change with the language.
        items: [
          NavItem(Icons.home_rounded, t('Home')),
          NavItem(Icons.event_note_rounded, t('Jobs')),
          NavItem(Icons.calendar_month_rounded, t('Calendar')),
          NavItem(Icons.favorite_rounded, t('Impact')),
        ],
      ),
    );
  }
}
