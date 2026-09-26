/// Rupees, grouped the Indian way.
///
/// 1,23,456 — not 123,456 and not 123.456. Getting this wrong is the kind of
/// detail that tells an Indian user the app was built for somewhere else.
library;

String inr(double v) {
  final neg = v < 0;
  final s = v.abs().round().toString();
  final sign = neg ? '-' : '';
  if (s.length <= 3) return '$sign₹$s';
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '$sign₹${parts.join(',')},$last3';
}
