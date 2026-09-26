// The approval chip.
//
// A provider who had been approved saw a red "Not approved" chip on their
// dashboard and a grey one with a raw status string on their profile. Both
// screens matched on `'active'`; the real backend sends `'approved'`, so both
// fell through to their default arm. The router had already been corrected for
// exactly this mismatch — these two had not, and nothing caught it because
// nothing tested it.

import 'package:flutter_test/flutter_test.dart';
import 'package:sathiyaa_provider/utils/approval.dart';
import 'package:sathiyaa_provider/widgets/sathiyaa_ui.dart' show ChipTone;

void main() {
  group('approvalPresentation', () {
    test('the value the real backend sends reads as approved', () {
      final a = approvalPresentation('approved');
      expect(a.tone, ChipTone.good, reason: 'this is the bug: it was ChipTone.bad, shown in red');
      expect(a.label, 'Approved');
      expect(a.note, isNotEmpty);
    });

    test('the value the mock backend sends still reads as approved', () {
      expect(approvalPresentation('active').tone, ChipTone.good);
      expect(approvalPresentation('active').label, 'Approved');
    });

    test('case does not matter', () {
      for (final s in ['APPROVED', 'Approved', 'aPpRoVeD']) {
        expect(approvalPresentation(s).tone, ChipTone.good, reason: s);
      }
    });

    test('waiting and paused are warnings, not failures', () {
      expect(approvalPresentation('pending').tone, ChipTone.warn);
      expect(approvalPresentation('hold').tone, ChipTone.warn);
    });

    test('only a real refusal is red', () {
      expect(approvalPresentation('rejected').tone, ChipTone.bad);
      expect(approvalPresentation('blocked').tone, ChipTone.bad);
    });

    test('every state a provider can be in says something useful', () {
      for (final s in ['approved', 'active', 'pending', 'hold', 'rejected', 'blocked']) {
        expect(approvalPresentation(s).note, isNotEmpty, reason: '$s has no explanation');
        expect(approvalPresentation(s).label, isNotEmpty, reason: '$s has no label');
      }
    });

    test('an unknown status is neutral rather than alarming', () {
      final a = approvalPresentation('something-new');
      expect(a.tone, ChipTone.neutral);
      expect(a.label, 'something-new');
    });

    test('an empty status does not render as a blank chip', () {
      expect(approvalPresentation('').label, 'Unknown');
    });
  });
}
