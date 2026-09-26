import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'backend.dart';
import 'i18n/l10n.dart';
import 'services/device_info.dart';
import 'theme/sathiyaa_theme.dart';
import 'screens/splash_and_auth.dart';
import 'screens/app_entry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Once, before anything renders. Cached for the life of the process — a
  // phone does not change model while the app is open.
  await DeviceInfo.load();
  // Restores whether the last run was on demo data or a live server, and the
  // saved server address, before anything renders.
  await Backend.load();
  // The chosen language, before the first frame — so somebody who picked
  // Gujarati does not see a flash of English every time they open the app.
  await Lang.load();
  runApp(const SathiyaaCustomerApp());
}

class SathiyaaCustomerApp extends StatelessWidget {
  const SathiyaaCustomerApp({super.key});

  @override
  Widget build(BuildContext context) {
    // LanguageScope rebuilds everything below it when the language changes, so
    // the picker takes effect immediately rather than on the next restart.
    return LanguageScope(
      builder: (context, locale) => MaterialApp(
        title: t('Sathiyaa Customer'),
        debugShowCheckedModeBanner: false,
        theme: buildSathiyaaTheme(),
        locale: locale,
        // Flutter's own widgets too -- the date picker's month names, the
        // text-selection menu, the back button's tooltip. Without these the
        // app would be in Gujarati and every system control still in English.
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

/// Decides the first screen: Welcome for a brand-new device, straight to the
/// Home shell if a customer is already "logged in" in the mock store (mirrors
/// the seeded-session convenience of the web prototype so testers land
/// somewhere useful immediately, with a way to start the register/login flow
/// from Welcome too).
/// Decides the first screen from the session restored at startup.
///
/// Three states, not two. Somebody who signed in but never got past the Terms
/// gate — app closed mid-registration — must resume at that gate; sending them
/// to Welcome would have them try to register again and be told their mobile
/// is already taken.
class RootRouter extends StatelessWidget {
  const RootRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final customer = Backend.instance.currentCustomer;
    if (customer == null) return const WelcomeScreen();
    if (!customer.termsAccepted) return const RegisterScreen(startAtTerms: true);
    return const AppEntry();
  }
}
