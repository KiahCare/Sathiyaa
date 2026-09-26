// Does the app survive the text size its users actually set?
//
// This app is for older people. Android's Font size and Display size settings
// are the first thing many of them turn up, routinely to 150% and not rarely
// to 200% — that is the whole point of the setting existing. Nothing in this
// app clamps the scale, which is correct and accessible, and it means every
// fixed-height Container and every single-line Row has to survive text twice
// the size it was laid out against.
//
// Flutter reports a layout that does not fit as an exception during the frame,
// which `tester.takeException()` returns. So an overflow is catchable here,
// before somebody's mother finds it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sathiyaa_customer/main.dart';
import 'package:sathiyaa_customer/mock_data.dart';

/// 1.0 is the default. 1.3 is one notch up on most phones, 2.0 is the largest
/// Android offers without Display-size changes on top.
const _scales = [1.0, 1.3, 1.6, 2.0];

void main() {
  setUp(() async {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    // A real phone, not the 800x600 test default: overflow is a function of
    // the space available, so testing on a surface no phone has proves little.
    view.physicalSize = const Size(1080, 2400);
    view.devicePixelRatio = 3.0;
    SharedPreferences.setMockInitialValues({});
    await MockBackend.instance.openDemoAccount();
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  /// Lets the first screen finish arriving.
  ///
  /// Not pumpAndSettle: Home starts a 20-second `Timer.periodic` to poll for
  /// booking updates, so there is never a frame with nothing outstanding and
  /// settling is not a state this app reaches. A fixed number of frames past
  /// the entry animations is what "laid out" means here.
  Future<void> settleEnough(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  for (final scale in _scales) {
    testWidgets('the app lays out at ${(scale * 100).round()}% text', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: const SathiyaaCustomerApp(),
        ),
      );
      await settleEnough(tester);

      final e = tester.takeException();
      expect(
        e,
        isNull,
        reason: 'the first screen overflows at ${(scale * 100).round()}% text '
            'size — which is a setting this app\'s users are more likely to '
            'have on than off:\n$e',
      );
    });
  }

  testWidgets('the bottom navigation labels survive 200% text', (tester) async {
    // The nav bar is the single tightest row in the app: four labels, four
    // icons, one screen width, and now translated labels that can be longer
    // than the English they replaced.
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: SathiyaaCustomerApp(),
      ),
    );
    await settleEnough(tester);
    expect(tester.takeException(), isNull);
  });
}
