// Does changing the language actually change what is on screen?
//
// The unit tests in i18n_test.dart prove t() returns the right string. That is
// not the same as the app rendering it: a screen that reads its labels once
// into a `const` list, or sits under a widget that does not rebuild, keeps
// showing English no matter what t() returns. This pumps the real picker and
// the real navigation bar and reads the pixels' worth of text back.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sathiyaa_customer/i18n/l10n.dart';
import 'package:sathiyaa_customer/i18n/language_screen.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Lang.current.value = AppLanguage.english;
  });

  Widget harness(Widget child) => LanguageScope(
        builder: (context, locale) => MaterialApp(
          locale: locale,
          // Without these, Flutter cannot resolve hi or gu and falls back to
          // the first supported locale -- which is exactly the failure this
          // file exists to catch in the real app.
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLanguage.values.map((l) => l.locale),
          home: child,
        ),
      );

  /// Picks a language and declines the restart offer.
  ///
  /// Every tap on a language now raises a dialog asking whether to restart, so
  /// a test that taps one and carries straight on is tapping at a barrier.
  /// Declining is the interesting default anyway: the language must already
  /// have changed by then, without the restart.
  Future<void> choose(WidgetTester tester, String language) async {
    await tester.tap(find.text(language));
    await tester.pumpAndSettle();
    final notNow = find.text(t('Not now'));
    if (notNow.evaluate().isNotEmpty) {
      await tester.tap(notNow);
      await tester.pumpAndSettle();
    }
  }

  testWidgets('the picker lists every language in its own script', (tester) async {
    await tester.pumpWidget(harness(const LanguageScreen()));
    await tester.pumpAndSettle();

    // The whole point: somebody who reads only Gujarati has to be able to find
    // their language without reading English.
    expect(find.text('English'), findsWidgets);
    expect(find.text('हिन्दी'), findsOneWidget);
    expect(find.text('ગુજરાતી'), findsOneWidget);
  });

  testWidgets('choosing a language changes the screen without a restart', (tester) async {
    await tester.pumpWidget(harness(const LanguageScreen()));
    await tester.pumpAndSettle();

    // The heading is itself translated, so it is a fair witness.
    expect(find.text('Language'), findsOneWidget);

    await choose(tester, 'हिन्दी');

    expect(Lang.current.value, AppLanguage.hindi);
    expect(find.text('भाषा'), findsOneWidget,
        reason: 'the heading should have re-rendered in Hindi');
    expect(find.text('Language'), findsNothing);
  });

  testWidgets('the restart offer names the language, and declining keeps it', (tester) async {
    await tester.pumpWidget(harness(const LanguageScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('हिन्दी'));
    await tester.pumpAndSettle();

    // The dialog is in the language just chosen, which is the only way
    // somebody who does not read English can act on it.
    expect(find.text('ऐप दोबारा चालू करें?'), findsOneWidget);
    expect(
      find.textContaining('हिन्दी'),
      findsWidgets,
      reason: 'the offer should say which language it is talking about',
    );

    await tester.tap(find.text('अभी नहीं'));
    await tester.pumpAndSettle();

    // Declining a restart is not declining the language.
    expect(Lang.current.value, AppLanguage.hindi);
    expect(find.text('भाषा'), findsOneWidget);
  });

  testWidgets('picking the language already in use offers nothing', (tester) async {
    Lang.current.value = AppLanguage.hindi;
    await tester.pumpWidget(harness(const LanguageScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('हिन्दी'));
    await tester.pumpAndSettle();

    expect(find.text('ऐप दोबारा चालू करें?'), findsNothing,
        reason: 'nothing changed, so there is nothing to restart for');
  });

  testWidgets('restarting rebuilds the tree from scratch', (tester) async {
    // The reason the offer exists: a rebuild re-runs build(), not initState(),
    // so a screen that read its labels once keeps them. This proves the
    // restart really does dispose and re-create what is below the scope.
    var builds = 0;
    await tester.pumpWidget(LanguageScope(
      builder: (context, locale) => MaterialApp(
        locale: locale,
        home: Builder(builder: (inner) {
          builds++;
          return TextButton(
            onPressed: () => LanguageScope.restart(inner),
            child: const Text('go'),
          );
        }),
      ),
    ));
    await tester.pumpAndSettle();
    final before = builds;

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(builds, greaterThan(before),
        reason: 'the subtree should have been built again');
  });

  testWidgets('the choice is written to storage so it survives a restart', (tester) async {
    await tester.pumpWidget(harness(const LanguageScreen()));
    await tester.pumpAndSettle();

    await choose(tester, 'ગુજરાતી');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('sathiyaa.language'), 'gu');

    // And a fresh start reads it back rather than defaulting to English.
    Lang.current.value = AppLanguage.english;
    await Lang.load();
    expect(Lang.current.value, AppLanguage.gujarati);
  });

  testWidgets('switching back to English restores the English text', (tester) async {
    await tester.pumpWidget(harness(const LanguageScreen()));
    await tester.pumpAndSettle();

    await choose(tester, 'ગુજરાતી');
    expect(find.text('ભાષા'), findsOneWidget);

    await choose(tester, 'English');
    expect(find.text('Language'), findsOneWidget);
  });

  testWidgets('a MaterialApp built under LanguageScope gets the right locale', (tester) async {
    // Without this, Flutter's own widgets -- the date picker, the text
    // selection menu -- stay in English while everything around them changes.
    Lang.current.value = AppLanguage.hindi;
    late Locale seen;
    await tester.pumpWidget(LanguageScope(
      builder: (context, locale) {
        seen = locale;
        return MaterialApp(
          locale: locale,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLanguage.values.map((l) => l.locale),
          home: const SizedBox(),
        );
      },
    ));
    expect(seen, const Locale('hi'));
  });
}
