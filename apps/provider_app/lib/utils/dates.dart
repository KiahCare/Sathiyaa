/// One way of writing a date, used by both apps.
///
/// "12/4/1958" is ambiguous: an Indian reader sees 12 April, an American reader
/// sees 4 December. On a health record — a surgery date, when a medicine was
/// started, when an insurance policy runs out — that ambiguity is not a style
/// question. Spelling the month out removes it, and costs three characters.
///
/// The month goes through t() for the same reason everything else does: a
/// screen in Gujarati with "12 Apr 1958" on it is a screen that is half
/// translated, and the date is on the health records, which is exactly where
/// somebody reading in their own language needs to not be guessing.
library;

import '../i18n/l10n.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "12 Apr 1958".
String prettyDate(DateTime d) =>
    '${d.day} ${t(_months[d.month - 1])} ${d.year}';

/// "12 Apr" — for a chart tick or a range where the year is already obvious.
String prettyDay(DateTime d) => '${d.day} ${t(_months[d.month - 1])}';
