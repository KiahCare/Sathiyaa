import 'package:flutter/material.dart';

import '../backend.dart';
import '../models.dart';
import '../theme/sathiyaa_theme.dart';
import '../utils/dates.dart';
import '../widgets/motion.dart';
import '../widgets/sathiyaa_ui.dart';
import '../i18n/l10n.dart';
import '../i18n/language_screen.dart';
import '../utils/approval.dart';
import '../languages.dart';
import 'auth_screens.dart';
import 'server_settings_screen.dart';

/// The provider's own profile.
///
/// Rebuilt on the design system, with three things corrected on the way:
///
///  * Log out set `currentProvider = null` directly instead of calling
///    `signOut()`. On a live server that left the auth token sitting in
///    storage — the screen said you were logged out and the session was not.
///  * The device id was printed as `PROV-000201-DEV-01`, a string this app
///    invents. The real one, which is what the server binds the account to and
///    what the admin console shows, was never on screen. It is now.
///  * The three checks said uploaded or not and left it there. A police
///    verification that ran out last month is not "uploaded" in any sense that
///    matters, so the dates are read and the state is named.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

/// What a document is, once its dates are taken into account.
enum _DocState { missing, expired, soon, valid }

class _ProfileScreenState extends State<ProfileScreen> {
  Future<void> _confirmLogOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: SC.surface,
        title: Text(t('Log out?'), style: ST.h2),
        content: Text(
          t('You will need your mobile number and your 6-digit PIN to sign back in.'),
          style: ST.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('Stay signed in')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: SC.redDeep),
            child: Text(t('Log out')),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _logOut();
  }

  Future<void> _logOut() async {
    final navigator = Navigator.of(context);
    await Backend.instance.signOut();
    if (!mounted) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (r) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Backend.instance.currentProvider!;
    final org = p.kind == ProviderKind.organization;

    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          BrandHeader(
            curved: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, SC.gutter, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.chevron_left_rounded,
                            color: Colors.white, size: 30),
                      ),
                      const Spacer(),
                      HeaderIconButton(
                        icon: Icons.translate_rounded,
                        tooltip: t('Language'),
                        onTap: () => push(context, const LanguageScreen()),
                      ),
                      const SizedBox(width: 8),
                      HeaderIconButton(
                        icon: Icons.dns_rounded,
                        tooltip: t('Server'),
                        onTap: () => push(context, const ServerSettingsScreen()),
                      ),
                      const SizedBox(width: 8),
                      // Beside language and server rather than at the foot of
                      // a long scroll. It asks first: the account is bound to
                      // this handset and signing back in needs the PIN.
                      HeaderIconButton(
                        icon: Icons.logout_rounded,
                        tooltip: t('Log out'),
                        onTap: _confirmLogOut,
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 0, 6),
                    child: Row(
                      children: [
                        InitialsAvatar(name: p.name, size: 66, radius: 21),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      height: 1.15)),
                              const SizedBox(height: 5),
                              Text('${p.id}  ·  ${org ? t('Organisation') : t('Freelancer')}',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 32),
              children: staggered([
                _statusRow(p),
                // Languages came off the registration form because every
                // field there costs somebody halfway through. That makes this
                // the only place it is asked, so it is asked properly: a
                // carer who has never touched it is sitting on the default of
                // English, a family filtering for Gujarati will not find
                // them, and neither side ever learns why.
                if (_languagesUntouched(p)) ...[
                  const SizedBox(height: 14),
                  _languagesPrompt(p),
                ],
                const SizedBox(height: 22),
                SectionLabel(t('About you')),
                SCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _kv(Icons.phone_rounded, 'Mobile', p.mobile),
                      _kv(Icons.mail_rounded, 'Email', p.email ?? 'Not given'),
                      _kv(Icons.place_rounded, 'Address', p.address),
                      const SizedBox(height: 12),
                      FieldLabel(t('What you do')),
                      if (p.expertise.isEmpty)
                        Text(t('Nothing selected yet.'), style: ST.small)
                      else
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [for (final e in p.expertise) SkillTag(e.label)],
                        ),
                      const SizedBox(height: 16),
                      FieldLabel(t('Your rate')),
                      if (p.noFees)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: SC.goldTint,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.volunteer_activism_rounded,
                                  size: 18, color: Color(0xFF8A6317)),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Text(
                                  t('You give your time free. Families are charged nothing for your visits.'),
                                  style: ST.small.copyWith(
                                      color: const Color(0xFF7A5612), height: 1.4),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('₹${p.hourlyRate?.toStringAsFixed(0) ?? '—'}',
                                style: ST.figure.copyWith(fontSize: 26)),
                            const SizedBox(width: 6),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(t('an hour'), style: ST.small),
                            ),
                          ],
                        ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: FieldLabel(t('Languages you speak'))),
                          PressableScale(
                            onTap: () => _editLanguages(p),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 7, left: 8),
                              child: Text(t('Edit'),
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: SC.blueLink)),
                            ),
                          ),
                        ],
                      ),
                      if (p.languages.isEmpty)
                        Text(t('Nothing selected yet.'), style: ST.small)
                      else
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [for (final l in p.languages) SkillTag(l)],
                        ),
                      const SizedBox(height: 16),
                      FieldLabel(t('When you work')),
                      _days(p.workPref),
                      const SizedBox(height: 8),
                      Text('${p.workPref.timeFrom} – ${p.workPref.timeTo}',
                          style: ST.bodyStrong),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                // Nobody runs a police check on a company, and an Aadhaar card
                // does not belong to one. This section used to be shown to
                // organisations as well, listing three documents an agency is
                // never asked for and will therefore never have -- three red
                // "Not given" rows that looked like a problem with the account
                // and could not be fixed. What verifies an agency is its
                // registration; what verifies the people it sends is each
                // carer's own paperwork, collected on the add-a-carer screen.
                if (org) ...[
                  SectionLabel(t('Your registration')),
                  SCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _doc('Registration certificate', p.registrationCertificate),
                        const SizedBox(height: 12),
                        _kv(Icons.receipt_long_rounded, 'GST',
                            (p.gstNumber?.isNotEmpty ?? false) ? p.gstNumber! : 'Not given'),
                        _kv(Icons.person_rounded, 'Contact',
                            (p.contactPerson?.isNotEmpty ?? false)
                                ? p.contactPerson!
                                : 'Not given'),
                        const SizedBox(height: 4),
                        Text(
                          t('Aadhaar, police verification and medical certificates belong to each carer, and are collected on the screen that adds them. A carer without them is not sent to anybody.'),
                          style: ST.small.copyWith(fontSize: 12, height: 1.45),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  SectionLabel(t('Your checks')),
                  SCard(
                    child: Column(
                      children: [
                        _doc('Aadhaar / work certificate', p.aadhar),
                        const SizedBox(height: 10),
                        _doc('Police verification', p.policeVerification),
                        const SizedBox(height: 10),
                        _doc('Medical certificate', p.medicalCertificate),
                        const SizedBox(height: 12),
                        Text(
                          t('Families see that you are checked, never the documents themselves. A medical certificate is required for clinical work.'),
                          style: ST.small.copyWith(fontSize: 12, height: 1.45),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                SectionLabel(t('This device')),
                SCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: SC.blueTint,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.smartphone_rounded,
                                size: 19, color: SC.blueBright),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(t('Your account is tied to this phone'),
                                style: ST.h3),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        t('Signing in from a second device is refused until Sathiyaa releases this one. It is what stops a verified account being passed around.'),
                        style: ST.small.copyWith(height: 1.45),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: SC.sunkTint,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t('DEVICE ID'),
                                style: ST.label.copyWith(color: SC.inkFaint)),
                            const SizedBox(height: 4),
                            SelectableText(
                              Backend.deviceId,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12.5,
                                height: 1.4,
                                color: SC.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(t('Sathiyaa support may ask you to read this out.'),
                          style: ST.small.copyWith(fontSize: 12)),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// Approval and rating — the two things a provider opens this screen to check.
  Widget _statusRow(ProviderProfile p) {
    final a = approvalPresentation(p.approvalStatus);
    final (label, tone, note) = (a.label, a.tone, a.note);

    return SCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusChip(label, tone: tone),
              const Spacer(),
              if (p.ratingCount > 0)
                StarRating(value: p.ratingAvg, count: p.ratingCount, size: 14),
            ],
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(note, style: ST.small.copyWith(height: 1.45)),
          ],
        ],
      ),
    );
  }

  /// True when a carer has never answered the language question.
  ///
  /// Exactly the default set, which is what registration writes when nobody
  /// is asked. Somebody who genuinely speaks only English will tick English
  /// and the set is the same -- so the banner offers a way to say "yes, only
  /// English" rather than nagging forever.
  bool _languagesUntouched(ProviderProfile p) =>
      !p.languagesConfirmed &&
      p.languages.length == kDefaultLanguages.length &&
      p.languages.toSet().containsAll(kDefaultLanguages);

  Widget _languagesPrompt(ProviderProfile p) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SC.amberTint,
        borderRadius: BorderRadius.circular(SC.rCard),
        border: Border.all(color: const Color(0xFFF0DCBC)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.translate_rounded, size: 19, color: Color(0xFFA9670F)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('Which languages do you speak?'),
                    style: ST.h3.copyWith(color: const Color(0xFF8A5510))),
                const SizedBox(height: 5),
                Text(
                  t('Families filter by this before they choose anybody. You are listed as English only until you say otherwise.'),
                  style: ST.small.copyWith(color: const Color(0xFF8A5510), height: 1.45),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    PressableScale(
                      onTap: () => _editLanguages(p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8A5510),
                          borderRadius: BorderRadius.circular(SC.rPill),
                        ),
                        child: Text(t('Choose languages'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    PressableScale(
                      onTap: () => _confirmEnglishOnly(p),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Text(t('English only'),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF8A5510))),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmEnglishOnly(ProviderProfile p) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Backend.instance.setLanguages(List<String>.from(kDefaultLanguages));
      if (!mounted) return;
      setState(() => p.languagesConfirmed = true);
      messenger.showSnackBar(SnackBar(content: Text(t('Saved. You are listed as English only.'))));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('$e'.replaceFirst('Exception: ', '')),
        backgroundColor: SC.redDeep,
      ));
    }
  }

  Widget _kv(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: SC.inkFaint),
            const SizedBox(width: 10),
            SizedBox(width: 62, child: Text(label, style: ST.small)),
            Expanded(child: Text(value, style: ST.bodyStrong.copyWith(fontSize: 14))),
          ],
        ),
      );

  /// Correcting the languages, from a sheet rather than a separate screen:
  /// it is one control, and a screen would be a back-stack entry for a change
  /// that takes two taps.
  Future<void> _editLanguages(ProviderProfile p) async {
    var picked = p.languages.toSet();
    final saved = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SC.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(SC.gutter, 14, SC.gutter, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: SC.hairlineCool,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(t('Languages you speak'), style: ST.h2),
                const SizedBox(height: 6),
                Text(
                  t('Families search by this. Pick every language you can hold a conversation in.'),
                  style: ST.small.copyWith(height: 1.45),
                ),
                const SizedBox(height: 16),
                LanguagePicker(
                  selected: picked,
                  onChanged: (set) => setSheet(() => picked = set),
                ),
                const SizedBox(height: 20),
                GradientButton(
                  label: t('Save'),
                  icon: Icons.check_rounded,
                  onPressed: picked.isEmpty
                      ? null
                      : () => Navigator.of(sheetContext).pop(picked),
                ),
                if (picked.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(t('Pick at least one language.'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: SC.red, fontSize: 12.5)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Backend.instance.setLanguages(saved.toList());
      if (!mounted) return;
      setState(() => p.languagesConfirmed = true);
      messenger.showSnackBar(SnackBar(content: Text(t('Languages saved.'))));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('$e'.replaceFirst('Exception: ', '')),
        backgroundColor: SC.redDeep,
      ));
    }
  }

  Widget _days(WorkPreference w) {
    const all = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Row(
      children: [
        for (final d in all) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: w.days.contains(d) ? SC.blueTint : SC.sunkTint,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                d.substring(0, 1),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: w.days.contains(d) ? SC.blue : SC.inkFaint,
                ),
              ),
            ),
          ),
          if (d != all.last) const SizedBox(width: 5),
        ],
      ],
    );
  }

  _DocState _stateOf(ProviderDocument d) {
    if (!d.uploaded) return _DocState.missing;
    final to = d.validTo;
    if (to == null) return _DocState.valid;
    final days = to.difference(DateTime.now()).inDays;
    if (days < 0) return _DocState.expired;
    if (days <= 30) return _DocState.soon;
    return _DocState.valid;
  }

  Widget _doc(String label, ProviderDocument d) {
    final state = _stateOf(d);
    final (icon, colour, word) = switch (state) {
      _DocState.valid => (Icons.check_circle_rounded, SC.green, 'On file'),
      _DocState.soon => (Icons.schedule_rounded, SC.amber, 'Expiring'),
      _DocState.expired => (Icons.error_rounded, SC.red, 'Expired'),
      _DocState.missing => (Icons.radio_button_unchecked_rounded, SC.inkFaint, 'Not given'),
    };

    final detail = switch (state) {
      _DocState.missing => 'Sathiyaa has not received this yet.',
      _DocState.expired => 'Ran out on ${prettyDate(d.validTo!)}. Send a new one.',
      _DocState.soon =>
        'Valid until ${prettyDate(d.validTo!)} — ${d.validTo!.difference(DateTime.now()).inDays} days left.',
      _DocState.valid =>
        d.validTo == null ? 'On file.' : 'Valid until ${prettyDate(d.validTo!)}.',
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: state == _DocState.valid ? SC.sunkTint : colour.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colour),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(label, style: ST.bodyStrong.copyWith(fontSize: 14)),
                    ),
                    Text(word,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: colour)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(detail, style: ST.small.copyWith(fontSize: 12, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
