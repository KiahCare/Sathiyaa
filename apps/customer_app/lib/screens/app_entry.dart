import 'package:flutter/material.dart';

import '../backend.dart';
import '../service_area.dart';
import 'home_shell.dart';

/// The one door into the app, so the service-area check cannot be walked
/// around by whichever screen happens to navigate next.
///
/// Registration, login and a restored session all finish here rather than at
/// [HomeShell] directly. That is the whole reason this file exists: three
/// call sites pushing HomeShell meant three places to remember the gate, and
/// the one that got forgotten would be the one that mattered.
///
/// The service area is fetched from the server so opening a new city does not
/// need a new APK. Until it answers — and if it never does — the built-in
/// Ahmedabad values are used, which is also what the server would have said.
class AppEntry extends StatefulWidget {
  const AppEntry({super.key});

  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> {
  ServiceArea _area = ServiceArea.fallback;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!Backend.isLive) return;
    try {
      final area = await Backend.instance.loadServiceArea();
      if (mounted) setState(() => _area = area);
    } catch (_) {
      // The fallback is already in place and is the same city. A welcome
      // screen is not the place to report a failed configuration fetch.
    }
  }

  @override
  Widget build(BuildContext context) {
    final customer = Backend.instance.currentCustomer;
    return ServiceAreaGate(
      // Demo mode has no server, and its carers are seeded into one city for
      // convenience rather than because anybody lives there.
      bypass: !Backend.isLive,
      known: customer?.signupInServiceArea,
      area: _area,
      audience: 'customer',
      report: (place) => Backend.instance.reportSignupPlace(place),
      child: const HomeShell(),
    );
  }
}
