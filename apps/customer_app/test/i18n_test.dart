// Guards the one weakness of keying translations by their English sentence:
// change the English wording and its translations become unreachable, silently
// and in every language at once. Nothing throws, nothing looks wrong in
// development, and the screen simply reverts to English for the people who
// cannot read it.
//
// So this walks lib/ and reports any translated key that no longer appears in
// the source, and any key present in one language's table and missing from the
// other.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sathiyaa_customer/i18n/l10n.dart';
import 'package:sathiyaa_customer/i18n/strings_hi.dart';
import 'package:sathiyaa_customer/i18n/strings_gu.dart';

String _allSource() {
  final buf = StringBuffer();
  for (final f in Directory('lib').listSync(recursive: true)) {
    // Skip only the tables themselves -- every key appears in those by
    // definition. The picker screen under i18n/ uses keys like any other
    // screen and must be scanned, which an `i18n` path exclusion got wrong.
    final isTable = f.path.endsWith('strings_hi.dart') || f.path.endsWith('strings_gu.dart');
    if (f is File && f.path.endsWith('.dart') && !isTable) {
      buf.writeln(f.readAsStringSync());
    }
  }
  return _asRuntimeStrings(buf.toString());
}

/// Rewrites the source so the strings in it read as what Dart will hand to
/// `t()` at run time.
///
/// Two things stand between the two, and without both this check reported
/// perfectly good keys as orphans -- which is worse than not checking, because
/// a report full of false alarms stops being read:
///
///   'one ' 'two'   Dart concatenates adjacent literals at compile time, so
///                  this is the single key "one two". Long sentences in these
///                  files are written this way to stay inside the line length,
///                  so it is most of the long keys.
///
///   \'             an escaped apostrophe is one character at run time.
///
/// Both are undone here rather than re-done on the key, because the key is
/// already the runtime string and the source is the thing in an odd shape.
String _asRuntimeStrings(String source) => source
    // Join adjacent literals: a closing quote, whitespace, an opening quote.
    // A comma or a colon between them means they are separate strings, and
    // neither matches this.
    .replaceAll(RegExp(r"'\s*'"), '')
    .replaceAll(RegExp(r'"\s*"'), '')
    .replaceAll(r"\'", "'")
    .replaceAll(r'\"', '"')
    .replaceAll(r'\$', r'$');

void main() {
  group('translation tables', () {
    test('Hindi and Gujarati cover exactly the same keys', () {
      final onlyHi = hiStrings.keys.where((k) => !guStrings.containsKey(k)).toList();
      final onlyGu = guStrings.keys.where((k) => !hiStrings.containsKey(k)).toList();

      expect(onlyHi, isEmpty,
          reason: 'translated to Hindi but not Gujarati:\n  ${onlyHi.join("\n  ")}');
      expect(onlyGu, isEmpty,
          reason: 'translated to Gujarati but not Hindi:\n  ${onlyGu.join("\n  ")}');
    });

    test('nothing is translated to itself', () {
      // Almost always a copy-paste that was never actually translated.
      for (final table in [hiStrings, guStrings]) {
        for (final e in table.entries) {
          expect(e.value, isNot(e.key), reason: '"${e.key}" is unchanged');
        }
      }
    });

    test('no translation is blank', () {
      for (final table in [hiStrings, guStrings]) {
        for (final e in table.entries) {
          expect(e.value.trim(), isNotEmpty, reason: 'empty translation for "${e.key}"');
        }
      }
    });

    test('every translated key still appears in the source', () {
      final source = _allSource();
      // `source` has already been normalised to the runtime form, so the key
      // is compared as it is -- quoted, so "Pay" cannot be satisfied by the
      // word Pay appearing inside a longer sentence. Either quote style: a
      // sentence containing an apostrophe is usually written with double
      // quotes rather than escaped, and this check used to report every one
      // of those as an orphan.
      final orphans = hiStrings.keys
          .where((k) => !source.contains("'$k'") && !source.contains('"$k"'))
          .toList();

      expect(orphans, isEmpty,
          reason: 'These are translated but no longer in any screen. Either the '
              'English wording changed (update the key) or the string is gone '
              '(delete it from both tables):\n  ${orphans.join("\n  ")}');
    });

    test('placeholders match between languages', () {
      final re = RegExp(r'\{(\w+)\}');
      for (final key in hiStrings.keys) {
        final inKey = re.allMatches(key).map((m) => m[1]).toSet();
        for (final table in [hiStrings, guStrings]) {
          final inValue = re.allMatches(table[key]!).map((m) => m[1]).toSet();
          expect(inValue, inKey,
              reason: 'placeholders differ for "$key" — a dropped one renders '
                  'as a literal {name} on screen');
        }
      }
    });
  });

  group('t()', () {
    setUp(() => Lang.current.value = AppLanguage.english);

    test('English returns the key unchanged', () {
      expect(t('Bookings'), 'Bookings');
    });

    test('a translated string comes back translated', () {
      Lang.current.value = AppLanguage.hindi;
      expect(t('Bookings'), 'बुकिंग');
      Lang.current.value = AppLanguage.gujarati;
      expect(t('Bookings'), 'બુકિંગ');
    });

    test('an untranslated string falls back to English rather than blank', () {
      Lang.current.value = AppLanguage.hindi;
      const untranslated = 'A sentence nobody has translated yet';
      expect(t(untranslated), untranslated);
    });

    test('placeholders are substituted', () {
      expect(t('Booked for {name}', {'name': 'Anita'}), 'Booked for Anita');
    });

    test('a placeholder with no argument is left alone, not blanked', () {
      expect(t('Booked for {name}'), 'Booked for {name}');
    });

    test('language codes round-trip', () {
      for (final l in AppLanguage.values) {
        expect(AppLanguage.fromCode(l.code), l);
      }
      expect(AppLanguage.fromCode('zz'), AppLanguage.english);
      expect(AppLanguage.fromCode(null), AppLanguage.english);
    });

    test('every language names itself in its own script', () {
      expect(AppLanguage.hindi.nativeName, 'हिन्दी');
      expect(AppLanguage.gujarati.nativeName, 'ગુજરાતી');
    });
  });
}
