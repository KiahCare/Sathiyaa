import 'package:flutter/material.dart';

import '../theme/sathiyaa_theme.dart';
import '../widgets/motion.dart';
import '../widgets/sathiyaa_ui.dart';
import '../i18n/l10n.dart';

/// Terms & Conditions and the Privacy Policy.
///
/// A summary, not the legal text — the full wording is the client's to supply
/// and ships in the production build. What is here is the part a person
/// actually needs before agreeing: what they are charged, what happens if they
/// cancel, what is collected and who sees it. A wall of unread clauses is not
/// consent; a short, true summary with the full text behind it is closer.
class LegalContentScreen extends StatefulWidget {
  const LegalContentScreen({super.key});

  @override
  State<LegalContentScreen> createState() => _LegalContentScreenState();
}

class _LegalContentScreenState extends State<LegalContentScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          BrandHeader(
            curved: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, SC.gutter, 14),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.chevron_left_rounded,
                        color: Colors.white, size: 30),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('Terms & Privacy'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(t('The short version, in plain words'),
                            style: const TextStyle(color: Colors.white70, fontSize: 13.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(SC.gutter, 16, SC.gutter, 0),
            child: SegmentedTabs(
              tabs: const ['Terms', 'Privacy'],
              index: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
          Expanded(
            child: FadeSwitch(
              child: _tab == 0
                  ? _terms(const ValueKey('terms'))
                  : _privacy(const ValueKey('privacy')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _terms(Key key) => ListView(
        key: key,
        padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 32),
        children: staggered([
          _point(
            Icons.receipt_long_rounded,
            'What you are charged',
            'An annual registration fee that keeps your account active, and a '
                'small confirmation charge on each booking. The care itself is '
                'settled with your carer when the visit ends — not taken up front.',
          ),
          _point(
            Icons.event_busy_rounded,
            'If you cancel',
            'Cancelling well ahead costs nothing. Closer to the visit a fee '
                'applies, because your carer has already set the time aside. The '
                'exact amount is shown on screen before you confirm, every time.',
          ),
          _point(
            Icons.verified_user_rounded,
            'Who comes to your door',
            'Every carer is checked before families can find them: identity, '
                'police verification, and a medical certificate for clinical '
                'work. A visit starts only when the OTP you hold is entered.',
          ),
          _point(
            Icons.report_problem_rounded,
            'What we ask of you',
            'Accurate details — your address, your health record, who to call in '
                'an emergency. A carer arriving at the wrong door, or unaware of '
                'an allergy, is the one risk this app cannot design away.',
          ),
          const SizedBox(height: 8),
          _footnote(),
        ]),
      );

  Widget _privacy(Key key) => ListView(
        key: key,
        padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 32),
        children: staggered([
          _point(
            Icons.folder_shared_rounded,
            'What we collect',
            'Your profile, your health record, and your location while a visit '
                'is running. Nothing else, and nothing you have not entered or '
                'agreed to.',
          ),
          _point(
            Icons.visibility_rounded,
            'Who sees it',
            'The carer on a confirmed booking sees what they need to do the job '
                'safely — your name, address, and the health details relevant to '
                'the care. Sathiyaa staff see it when you ask for help.',
          ),
          _point(
            Icons.block_rounded,
            'What we never do',
            'Your data is not sold, and it is not passed to advertisers.',
          ),
          _point(
            Icons.my_location_rounded,
            'Location',
            'Asked for only when you set your address or when a visit is under '
                'way, so you can see your carer on the way. You can refuse, and '
                'the rest of the app still works.',
          ),
          const SizedBox(height: 8),
          _footnote(),
        ]),
      );

  Widget _point(IconData icon, String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: SC.blueTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 19, color: SC.blueBright),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: ST.h3),
                    const SizedBox(height: 6),
                    Text(body, style: ST.small.copyWith(height: 1.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _footnote() => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: SC.sunkTint,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.gavel_rounded, size: 17, color: SC.inkFaint),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                t('This is a summary. The full legal text ships with the production app and is what binds either of us.'),
                style: ST.small.copyWith(fontSize: 12, height: 1.45),
              ),
            ),
          ],
        ),
      );
}
