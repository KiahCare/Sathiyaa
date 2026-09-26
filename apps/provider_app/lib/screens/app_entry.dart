import 'package:flutter/material.dart';

import '../backend.dart';
import '../service_area.dart';
import 'home_shell.dart';

/// The one door into the app, so the service-area check cannot be walked
/// around by whichever screen happens to navigate next.
///
/// Registration, sign-in and a restored session all finish here rather than at
/// [HomeShell] directly. Three call sites pushing HomeShell meant three places
/// to remember the gate, and the one that got forgotten would be the one that
/// mattered.
///
/// A carer outside the launch city is a different case from a family outside
/// it: they keep the account, and they are the first people Sathiyaa contacts
/// when it opens a city, because a city with no carers cannot be opened at
/// all.
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
      // The fallback is the same city the server would have named.
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Backend.instance.currentProvider;
    return ServiceAreaGate(
      bypass: !Backend.isLive,
      known: provider?.signupInServiceArea,
      area: _area,
      audience: 'provider',
      report: (place) => Backend.instance.reportSignupPlace(place),
      child: const HomeShell(),
    );
  }
}
