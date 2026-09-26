import 'dart:math' as math;

/// A y-axis a person can read: round bounds, a round step between them.
///
/// This exists because of a real and very visible bug. Left to itself, fl_chart
/// labels the exact minimum and maximum of the data *as well as* its own
/// round-number ticks — so three blood-pressure readings of 146, 138 and 128
/// produced an axis reading "128 130 135 140 145 146", with 145 printed on top
/// of 146 and 128 on top of 130. Two of the six labels were unreadable and the
/// whole thing looked like the chart had miscounted.
///
/// Rounding the bounds outwards to a whole step fixes it at the cause: every
/// label is then a round number, consecutive labels are exactly one step apart,
/// and no two can ever land close enough to overlap.
///
/// Kept out of the widget and public so the rule can be tested directly. It is
/// arithmetic with several edge cases — a flat series, a single reading, values
/// spanning two orders of magnitude — and none of those are things anyone will
/// notice by looking at one chart.
({double min, double max, double step}) niceAxis(List<double> values) {
  if (values.isEmpty) return (min: 0, max: 10, step: 5);

  var lo = values.reduce(math.min);
  var hi = values.reduce(math.max);

  // A flat series — three identical readings — has no range to divide, and
  // would otherwise ask for a step of zero and an axis of no height.
  if (hi - lo < 1) {
    lo -= 2;
    hi += 2;
  }

  // Four gaps is about right for a chart 150px tall: enough to read a level
  // off, few enough that the labels are not stacked up the side.
  final rough = (hi - lo) / 4;
  final magnitude = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
  final step = const [1.0, 2.0, 2.5, 5.0, 10.0]
      .map((m) => m * magnitude)
      .firstWhere((s) => s >= rough, orElse: () => 10 * magnitude);

  return (
    min: (lo / step).floorToDouble() * step,
    max: (hi / step).ceilToDouble() * step,
    step: step,
  );
}
