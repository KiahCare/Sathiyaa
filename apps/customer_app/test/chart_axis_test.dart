import 'package:flutter_test/flutter_test.dart';

import 'package:sathiyaa_customer/utils/chart_axis.dart';

/// The vitals graph's y-axis.
///
/// Worth its own test file because the bug it exists to prevent was visible on
/// screen and invisible in the code: fl_chart labels the exact minimum and
/// maximum of the data as well as its own round-number ticks, so three blood
/// pressure readings of 146, 138 and 128 came out as
/// "128 130 135 140 145 146" — 145 printed over 146, and 128 over 130.
///
/// Every case below is "the labels are round numbers a step apart", which is
/// the only property that makes a collision impossible.
void main() {
  /// Every label the axis will draw, which is what a person actually sees.
  List<double> ticks(({double min, double max, double step}) a) {
    final out = <double>[];
    for (var v = a.min; v <= a.max + 0.0001; v += a.step) {
      out.add(double.parse(v.toStringAsFixed(4)));
    }
    return out;
  }

  test('the readings that produced the overlap now give round labels', () {
    final a = niceAxis([146, 138, 128]);

    expect(a.min, lessThanOrEqualTo(128));
    expect(a.max, greaterThanOrEqualTo(146));
    expect(ticks(a), [125.0, 130.0, 135.0, 140.0, 145.0, 150.0]);
  });

  test('blood pressure drawn as two lines still gets one sensible scale', () {
    // Systolic 128–146 and diastolic 82–92 share an axis, so it has to cover
    // both without the step becoming so fine that the labels stack.
    final a = niceAxis([146, 138, 128, 92, 88, 82]);

    expect(a.min, lessThanOrEqualTo(82));
    expect(a.max, greaterThanOrEqualTo(146));
    expect(ticks(a), [80.0, 100.0, 120.0, 140.0, 160.0]);
  });

  test('bounds always contain the data', () {
    for (final series in [
      [97.0, 96.0],
      [74.0],
      [168.0, 141.0, 126.0],
      [0.5, 0.9],
      [1000.0, 1400.0, 2200.0],
    ]) {
      final a = niceAxis(series);
      for (final v in series) {
        expect(v, greaterThanOrEqualTo(a.min), reason: '$series clipped at the bottom');
        expect(v, lessThanOrEqualTo(a.max), reason: '$series clipped at the top');
      }
    }
  });

  test('every label sits exactly one step from the next', () {
    for (final series in [
      [146.0, 138.0, 128.0],
      [97.0, 96.0],
      [168.0, 141.0, 126.0],
      [1000.0, 1400.0, 2200.0],
    ]) {
      final a = niceAxis(series);
      final t = ticks(a);
      expect(t.length, greaterThanOrEqualTo(3), reason: '$series: too few gridlines to read');
      expect(t.length, lessThanOrEqualTo(7), reason: '$series: too many labels for 150px');
      for (var i = 1; i < t.length; i++) {
        expect(t[i] - t[i - 1], closeTo(a.step, 0.0001));
      }
    }
  });

  test('a flat series still gets an axis with height', () {
    // Three identical readings have no range to divide. Without the guard the
    // step is zero, the loop that draws gridlines never terminates, and the
    // chart is a single line through the middle of nothing.
    final a = niceAxis([120, 120, 120]);
    expect(a.max, greaterThan(a.min));
    expect(a.step, greaterThan(0));
    expect(ticks(a).length, greaterThanOrEqualTo(2));
  });

  test('a single reading does not crash the axis', () {
    final a = niceAxis([74]);
    expect(a.max, greaterThan(a.min));
    expect(74, greaterThanOrEqualTo(a.min));
    expect(74, lessThanOrEqualTo(a.max));
  });

  test('no readings at all is answered, not thrown', () {
    final a = niceAxis([]);
    expect(a.max, greaterThan(a.min));
    expect(a.step, greaterThan(0));
  });
}
