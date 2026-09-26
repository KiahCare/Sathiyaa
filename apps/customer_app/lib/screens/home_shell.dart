import 'package:flutter/material.dart';

import '../i18n/l10n.dart';
import '../theme/sathiyaa_theme.dart';
import '../widgets/sathiyaa_ui.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'appointments_screen.dart';
import 'help_screen.dart';

/// Four tabs, matching the reference: Home, Companion, Bookings, Help.
///
/// Profile is reached from the avatar in the header rather than taking a tab
/// of its own — it is visited rarely, and the fourth slot earns more as Help.
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
      HomeScreen(onGoToTab: _go),
      const SearchScreen(),
      const AppointmentsScreen(),
      const HelpScreen(),
    ];

    return Scaffold(
      backgroundColor: SC.paper,
      extendBody: true,
      // IndexedStack keeps every tab alive, so scroll position and in-flight
      // loads survive a switch.
      //
      // It must NOT be wrapped in an AnimatedSwitcher: the switcher keeps the
      // outgoing subtree mounted for the length of the transition, so two
      // full-width IndexedStacks get laid out and painted at once. On screen
      // that read as the old tab refusing to go away, and as two copies of the
      // page side by side. The pill bar animates its own selection, which is
      // the feedback a tab switch actually needs.
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: PillNavBar(
        index: index,
        onChanged: _go,
        // Not const: the labels change with the language.
        items: [
          NavItem(Icons.home_rounded, t('Home')),
          NavItem(Icons.search_rounded, t('Companion')),
          NavItem(Icons.event_note_rounded, t('Bookings')),
          NavItem(Icons.support_agent_rounded, t('Help')),
        ],
      ),
    );
  }
}
