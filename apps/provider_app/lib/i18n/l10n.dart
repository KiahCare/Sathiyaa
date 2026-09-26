// Hindi, English and Gujarati.
//
// Why English is the key
// ----------------------
// The usual Flutter approach gives every string a name -- `addPhotoButton` --
// and keeps the English in an .arb file beside the other languages. That is
// the right shape for an app written with translation in mind from the start.
// These two apps were not: there are roughly eight hundred distinct
// user-facing strings already written, in place, across thirty screens.
//
// Naming eight hundred keys, and editing eight hundred call sites to use them,
// is a very large change in which every mistake is silent -- a wrong key shows
// a blank, or the wrong sentence, and only in one language, on one screen,
// which is exactly the kind of bug nobody finds before a user does.
//
// So the English sentence is the key:
//
//     Text(t('Add a photo'))
//
// which buys three things. A string that has not been translated yet falls
// back to its English automatically, so the app is never broken or blank,
// only partly translated. Screens can be converted a few at a time instead of
// all at once. And the call site still reads as the sentence it renders, so
// nobody has to look up what `addPhotoButton` says.
//
// The cost is that changing the English wording orphans its translations. That
// is what `flutter test test/i18n_test.dart` is for: it reports any translated
// key that no longer appears anywhere in the source.
//
// Interpolation
// -------------
// Dart interpolates before this function is ever called, so `'Hello $name'`
// arrives already expanded and can never match a key. Those strings take
// placeholders instead:
//
//     t('Booked for {name}', {'name': customer.name})
//
// Placeholders are substituted after the lookup, so they work identically in
// every language -- including ones that need them in a different order.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'strings_hi.dart';
import 'strings_gu.dart';

/// The three languages, in the order the picker shows them.
enum AppLanguage {
  english('en', 'English', 'English'),
  hindi('hi', 'हिन्दी', 'Hindi'),
  gujarati('gu', 'ગુજરાતી', 'Gujarati');

  const AppLanguage(this.code, this.nativeName, this.englishName);

  /// The ISO code, and what goes in storage.
  final String code;

  /// What the language calls itself. This is what the picker shows: somebody
  /// who only reads Gujarati cannot pick "Gujarati" from a list written in
  /// English, which is the whole problem a language picker exists to solve.
  final String nativeName;

  /// For anywhere the surrounding text is English.
  final String englishName;

  Locale get locale => Locale(code);

  static AppLanguage fromCode(String? code) => AppLanguage.values.firstWhere(
        (l) => l.code == code,
        orElse: () => AppLanguage.english,
      );
}

/// The current language, and the thing the whole app listens to.
///
/// A [ValueNotifier] rather than an InheritedWidget because every screen in
/// both apps is already built against plain globals (`Backend.instance`), and
/// a second, different way of reading app state would be its own kind of mess.
class Lang {
  Lang._();

  static const _key = 'sathiyaa.language';

  static final ValueNotifier<AppLanguage> current =
      ValueNotifier<AppLanguage>(AppLanguage.english);

  /// Read the saved choice before the first frame. Best-effort: a device with
  /// no usable storage should open in English, not fail to open.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      current.value = AppLanguage.fromCode(prefs.getString(_key));
    } catch (_) {
      current.value = AppLanguage.english;
    }
  }

  /// Change the language and remember it. Rebuilds the app through [current].
  static Future<void> set(AppLanguage lang) async {
    current.value = lang;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, lang.code);
    } catch (_) {
      // The choice still applies for this run; it just will not survive a
      // restart. Better than refusing to change language at all.
    }
  }
}

/// Every translation, by language code. English is absent on purpose: the key
/// *is* the English, so a missing entry falls through to it.
const Map<String, Map<String, String>> _tables = {
  'hi': hiStrings,
  'gu': guStrings,
};

/// Translate [english], substituting any `{placeholder}` in [args].
///
/// Deliberately a bare top-level function rather than `L.of(context).x`: it
/// needs no BuildContext, so it works in a dialog builder, a `switch` that
/// picks a label, a model's `toString`, and the several places in these apps
/// that build strings outside the widget tree.
String t(String english, [Map<String, Object?>? args]) {
  final table = _tables[Lang.current.value.code];
  var out = table?[english] ?? english;

  if (args != null) {
    for (final entry in args.entries) {
      out = out.replaceAll('{${entry.key}}', '${entry.value}');
    }
  }
  return out;
}

/// Wraps the app so that changing the language rebuilds everything below it.
///
/// [builder] receives the locale so it can be handed to MaterialApp, which is
/// what makes Flutter's own widgets -- date pickers, the text selection menu,
/// "Cancel" on a system dialog -- follow the choice too.
///
/// Why there is also a restart
/// ---------------------------
/// Rebuilding gets most of the way, but not all of it. A screen that captured
/// a string in a `late final` field, or built a list of labels once in
/// initState, keeps the words it had when it was first created -- a rebuild
/// re-runs `build`, not `initState`. Those screens stay in the old language
/// until they are disposed and made again, which for the shell around the
/// bottom navigation bar means never.
///
/// [LanguageScope.restart] re-keys the subtree, so every widget below is
/// disposed and constructed afresh. That is a restart in every way that
/// matters here, and unlike a real one it needs no plugin and loses no
/// session -- the language, the token and the server choice are all read back
/// from storage.
class LanguageScope extends StatefulWidget {
  const LanguageScope({super.key, required this.builder});

  final Widget Function(BuildContext context, Locale locale) builder;

  /// Rebuilds the entire app from scratch. Safe to call from anywhere below
  /// the scope; does nothing if there is no scope above the caller.
  static void restart(BuildContext context) {
    context.findAncestorStateOfType<_LanguageScopeState>()?._restart();
  }

  @override
  State<LanguageScope> createState() => _LanguageScopeState();
}

class _LanguageScopeState extends State<LanguageScope> {
  /// Changing this throws away the whole widget tree below and builds a new
  /// one. It is the restart.
  Key _generation = UniqueKey();

  void _restart() => setState(() => _generation = UniqueKey());

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: Lang.current,
      builder: (context, lang, _) => KeyedSubtree(
        key: _generation,
        child: widget.builder(context, lang.locale),
      ),
    );
  }
}
