// How an approval status reads on screen.
//
// Provider-only, and in its own file on purpose: sathiyaa_ui.dart is copied
// from customer_app by _builds/sync-design.ps1 on every APK build, so anything
// added to it here is deleted the next time somebody builds.
//
// This exists in one place because it was previously written out twice, in
// dashboard_screen and profile_screen, and both copies matched on `'active'`
// -- a value the real backend never sends. It returns pending / approved /
// hold / rejected. So an approved provider fell through to the default arm and
// was shown a red "Not approved" chip on the dashboard and a grey chip with a
// raw status string on their profile. The router had already been corrected
// for exactly this; these two had not.
//
// Both spellings are accepted, because the mock backend still uses `active`.

import '../i18n/l10n.dart';
import '../widgets/sathiyaa_ui.dart' show ChipTone;

typedef ApprovalPresentation = ({String label, ChipTone tone, String note});

/// Whether this status lets somebody take work.
///
/// Only an approved account does. It is written once, here, because the
/// question is asked on the dashboard, in the bookings list and on the
/// profile, and three copies of a status comparison is exactly how the
/// "active"/"approved" mismatch got in last time.
bool canTakeWork(String status) {
  final s = status.toLowerCase();
  return s == 'approved' || s == 'active';
}

ApprovalPresentation approvalPresentation(String status) {
  switch (status.toLowerCase()) {
    case 'approved':
    case 'active':
      return (
        label: t('Approved'),
        tone: ChipTone.good,
        note: t('Your documents are on file and families can find you.'),
      );
    case 'pending':
      return (
        label: t('Awaiting approval'),
        tone: ChipTone.warn,
        note: t('Sathiyaa is checking your documents. You will not appear in search until that is done.'),
      );
    case 'hold':
      return (
        label: t('On hold'),
        tone: ChipTone.warn,
        note: t('Sathiyaa has paused your account while something is checked. You will not appear in search until it is cleared.'),
      );
    case 'rejected':
      return (
        label: t('Not approved'),
        tone: ChipTone.bad,
        note: t('Your application was not accepted. Sathiyaa support can tell you why and what to do next.'),
      );
    case 'blocked':
      return (
        label: t('Blocked'),
        tone: ChipTone.bad,
        note: t('Your account cannot take work. Please contact Sathiyaa support.'),
      );
    default:
      return (
        label: status.isEmpty ? 'Unknown' : status,
        tone: ChipTone.neutral,
        note: '',
      );
  }
}
