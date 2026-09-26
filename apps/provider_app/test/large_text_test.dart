// Does the app survive the text size its users actually set?
//
// Carers read this between visits, often outdoors, often on a cheap phone
// with the font size turned up. Nothing clamps the scale, which is correct and
// accessible, and it means every fixed-height Container and every single-line
// Row has to survive text well beyond the size it was laid out against.
//
// The customer app had two rows that overflowed at 100% -- before anybody
// touched an accessibility setting -- so this is not a hypothetical.
//
// Flutter reports a layout that does not fit as an exception during the frame,
// which `tester.takeException()` returns. So an overflow is catchable here,
// before somebody's mother finds it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sathiyaa_provider/main.dart';
import 'package:sathiyaa_provider/mock_data.dart';

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

  for (final scale in _scales) {
    testWidgets('the app lays out at ${(scale * 100).round()}% text', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: const SathiyaaProviderApp(),
        ),
      );
      // Not pumpAndSettle: the dashboard polls the backend every 20 seconds,
      // so there is always a pending timer and settling never happens. A few
      // explicit frames is enough to lay out and to surface an overflow.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

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
        child: SathiyaaProviderApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });
}
