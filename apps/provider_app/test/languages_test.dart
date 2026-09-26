// Does the app ask what languages somebody speaks?
//
// For a long time it did not. The word "languages" appeared in exactly one
// place in this whole app -- `'languages': const ['English']` in the
// registration payload -- while the customer app filtered on the field, the
// matching query ran a real `JSON_CONTAINS` against it, and every carer's
// card printed it. So the filter worked perfectly and matched nobody, and
// every carer claimed English whatever they actually spoke.
//
// For elderly customers in India, being sent somebody you cannot talk to is
// close to the worst thing this product can do. So there is a test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sathiyaa_provider/languages.dart';
import 'package:sathiyaa_provider/mock_data.dart';
import 'package:sathiyaa_provider/models.dart';
import 'package:sathiyaa_provider/screens/auth_screens.dart';
import 'package:sathiyaa_provider/screens/profile_screen.dart';
import 'package:sathiyaa_provider/screens/organization/add_edit_employee_screen.dart';
import 'package:sathiyaa_provider/widgets/sathiyaa_ui.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await MockBackend.instance.openDemoAccount();
  });

  Widget harness(Widget child) => MaterialApp(home: child);

  /// Drags a lazy list until [target] is built, or gives up.
  ///
  /// ListView(children: [...]) builds only what is near the viewport, so a
  /// section below the fold is not in the tree at all -- find.byType returns
  /// nothing and the failure reads as "the feature is missing" rather than
  /// "scroll down".
  Future<void> revealBelowTheFold(WidgetTester tester, Finder target) async {
    for (var i = 0; i < 12 && target.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await tester.pump();
    }
    // Past the entry animations. Each section that scrolls into view starts a
    // staggered Future.delayed, and a delayed future that has not fired is a
    // pending timer -- which the binding asserts on at the end of the test,
    // and which pumpAndSettle does not drain because it schedules no frame.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  }

  group('the list itself', () {
    test('offers more than English', () {
      // The whole failure was one hardcoded value. A list of one would be the
      // same bug wearing a constant's name.
      expect(kLanguages.length, greaterThan(5));
      expect(kLanguages, contains('English'));
      expect(kLanguages, contains('Gujarati'));
      expect(kLanguages, contains('Hindi'));
    });

    test('has no duplicates, which would render two identical chips', () {
      expect(kLanguages.toSet().length, kLanguages.length);
    });

    test('starts a carer on English only', () {
      // Not the whole list: a pre-ticked list is a list nobody reads, and the
      // point of the field is that the carer says what is true rather than
      // accepting what was assumed.
      expect(kDefaultLanguages, ['English']);
    });
  });

  group('registration', () {
    testWidgets('does not ask -- the form is short on purpose', (tester) async {
      await tester.pumpWidget(harness(const RegisterScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(LanguagePicker), findsNothing,
          reason: 'the picker was taken off the registration form; if it is '
              'back, the profile prompt below is now a second place asking '
              'the same question');
    });

    testWidgets('and leaves nobody with an empty list', (tester) async {
      // Null would be stored as null, and JSON_CONTAINS against null matches
      // nothing -- a carer invisible to every language search rather than
      // only to the wrong ones. Not asking is fine; storing nothing is not.
      final p = MockBackend.instance.currentProvider!;
      expect(p.languages, isNotEmpty);
    });
  });

  group('the profile screen, which is where it is asked now', () {
    testWidgets('prompts a carer who has never answered', (tester) async {
      final p = MockBackend.instance.currentProvider!;
      p.languages = List<String>.from(kDefaultLanguages);
      p.languagesConfirmed = false;

      await tester.pumpWidget(harness(const ProfileScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Which languages do you speak?'), findsOneWidget,
          reason: 'a carer sitting on the English-only default has to be '
              'asked somewhere, or a family filtering for Gujarati never '
              'finds them and neither side learns why');
    });

    testWidgets('stops once they have', (tester) async {
      final p = MockBackend.instance.currentProvider!;
      p.languages = ['English', 'Gujarati'];
      p.languagesConfirmed = true;

      await tester.pumpWidget(harness(const ProfileScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Which languages do you speak?'), findsNothing,
          reason: 'somebody who has answered should not be asked again');
    });

    // A plain test, not testWidgets. MockBackend's methods await a real
    // Future.delayed to feel like a network call, and inside testWidgets the
    // clock is fake -- that future never completes and the test sits there
    // until the ten-minute timeout.
    test('and saving English only counts as an answer', () async {
      // "English only" and "never answered" are the same list, so without the
      // confirmation flag a carer who genuinely speaks only English would be
      // nagged forever.
      final back = MockBackend.instance;
      back.currentProvider!.languagesConfirmed = false;
      await back.setLanguages(List<String>.from(kDefaultLanguages));
      expect(back.currentProvider!.languagesConfirmed, isTrue);
    });
  });

  group('an organisation adding a carer', () {
    testWidgets('is asked the same question', (tester) async {
      await tester.pumpWidget(harness(const AddEditEmployeeScreen()));
      await tester.pumpAndSettle();
      await revealBelowTheFold(tester, find.byType(LanguagePicker));

      expect(find.byType(LanguagePicker), findsOneWidget,
          reason: 'an agency adding somebody has to say what they speak, or '
              'every carer it adds silently claims English');
    });

    testWidgets('an existing carer opens with the languages they had',
        (tester) async {
      final carer = Employee(
        id: 'EMP-TEST',
        name: 'Test Carer',
        gender: 'Female',
        mobile: '9998800999',
        address: 'Somewhere',
        languages: ['English', 'Tamil', 'Kannada'],
      );
      await tester.pumpWidget(harness(AddEditEmployeeScreen(employee: carer)));
      await tester.pumpAndSettle();
      await revealBelowTheFold(tester, find.byType(LanguagePicker));

      final picker = tester.widget<LanguagePicker>(find.byType(LanguagePicker));
      expect(picker.selected, containsAll(<String>['English', 'Tamil', 'Kannada']),
          reason: 'editing somebody should not quietly reset what they speak');
    });
  });

  group('the model', () {
    test('a carer defaults to English, not to nothing', () {
      // Null would be stored as null, and JSON_CONTAINS against null matches
      // nothing -- so a carer with no languages is invisible to every search
      // that names one.
      final e = Employee(
        id: 'E1', name: 'X', gender: 'Female', mobile: '9', address: 'Y',
      );
      expect(e.languages, isNotEmpty);
    });

    test('and so does a provider', () {
      final p = ProviderProfile(
        id: 'P1',
        kind: ProviderKind.freelancer,
        name: 'X',
        gender: 'Female',
        mobile: '9',
        address: 'Y',
        lat: 0,
        lng: 0,
      );
      expect(p.languages, isNotEmpty);
    });
  });

  test('a carer can correct their languages afterwards', () async {
    final back = MockBackend.instance;
    await back.setLanguages(['English', 'Hindi', 'Odia']);
    expect(back.currentProvider!.languages, containsAll(<String>['Hindi', 'Odia']));
  });
}
