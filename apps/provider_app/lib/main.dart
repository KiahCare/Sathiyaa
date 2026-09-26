import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'backend.dart';
import 'i18n/l10n.dart';
import 'services/device_info.dart';
import 'theme/sathiyaa_theme.dart';
import 'screens/auth_screens.dart';
import 'screens/app_entry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Once, before anything renders. Cached for the life of the process — a
  // phone does not change model while the app is open.
  await DeviceInfo.load();
  // Restores whether the last run was on demo data or a live server, the saved
  // server address, and this device's stable id (the backend binds an account
  // to one device).
  await Backend.load();
  // The chosen language, before the first frame -- so somebody who picked
  // Gujarati does not see a flash of English every time they open the app.
  await Lang.load();
  runApp(const SathiyaaProviderApp());
}

class SathiyaaProviderApp extends StatelessWidget {
  const SathiyaaProviderApp({super.key});

  @override
  Widget build(BuildContext context) {
    // LanguageScope rebuilds everything below it when the language changes,
    // so the picker takes effect immediately rather than on the next restart.
    return LanguageScope(
      builder: (context, locale) => MaterialApp(
        title: t('Sathiyaa Provider'),
        debugShowCheckedModeBanner: false,
        theme: buildSathiyaaTheme(),
        locale: locale,
        // Flutter's own widgets too -- the date picker a carer uses for their
        // date of birth, the text-selection menu, the back button's tooltip.
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLanguage.values.map((l) => l.locale),
        home: const RootRouter(),
      ),
    );
  }
}

/// Decides the first screen from the session restored at startup.
///
/// Being signed in is enough to get in. A provider awaiting approval still
/// needs to reach the app — to see that they are pending, finish their profile
/// and upload documents — and the dashboard shows their approval status. The
/// approval gate is on *appearing in customer search*, not on opening the app.
///
/// (This used to require `approvalStatus == 'active'`, a value the real backend
/// never returns: it uses pending / approved / hold / rejected. Against a live
/// server an approved provider was sent back to Welcome.)
class RootRouter extends StatelessWidget {
  const RootRouter({super.key});

  @override
  Widget build(BuildContext context) {
    return Backend.instance.currentProvider == null ? const WelcomeScreen() : const AppEntry();
  }
}
