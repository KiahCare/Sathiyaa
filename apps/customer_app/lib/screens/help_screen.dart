// Help.
//
// The reference build gives Help a whole tab, which is right for an app whose
// users are often elderly: when something confuses them the answer should be
// one tap away, not buried in a menu. Everything here is either a real answer
// or a real contact — no dead links.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend.dart';
import '../theme/sathiyaa_theme.dart';
import '../widgets/sathiyaa_ui.dart';
import 'legal_content.dart';
import 'server_settings_screen.dart';
import '../i18n/l10n.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  int? _open;

  static const _faqs = <(String, String)>[
    (
      'How do I book somebody?',
      'Open the Companion tab, choose the kind of care, the dates and the hours you '
          'need, then search. You will see everyone available near you. Pick the ones '
          'you like and send them a request — several can be asked at once, and the '
          'first to accept gets the visit.'
    ),
    (
      'When do I pay?',
      'Nothing is charged while you are waiting. Once somebody accepts, you confirm '
          'the booking and pay the booking fee. The care itself is settled with your '
          'companion at the end, and they record what you handed over.'
    ),
    (
      'What if nobody accepts?',
      'The request stays open and keeps looking. If it finds nobody it expires on its '
          'own and you are not charged anything. Widening the hours or the date usually '
          'helps most.'
    ),
    (
      'Can I book for my mother or father?',
      'Yes. Add them under Family in your profile, and pick their name in the '
          '"Services for" box when you book. The visit goes to their address, and you '
          'stay in control of the booking.'
    ),
    (
      'How do I know the person is genuine?',
      'Every companion is approved by Sathiyaa before they can appear in search. We '
          'check their ID, their police verification and, for nurses, their medical '
          'certificate. The tick on their photo means all of that is on file.'
    ),
    (
      'Can I cancel?',
      'Yes, from the booking itself. If you cancel well before the start there is no '
          'fee. Closer to the time a part of the fee is kept — the app tells you the '
          'exact amount before you confirm the cancellation.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SC.paper,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          BrandHeader(
            child: BrandBar(
              title: t('Help'),
              subtitle: t('Answers, and a person to call'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _callCard(),
                const SizedBox(height: 22),
                SectionLabel(t('Common questions')),
                ...List.generate(_faqs.length, (i) => _faq(i)),
                const SizedBox(height: 22),
                SectionLabel(t('About')),
                _linkTile(
                  Icons.description_rounded,
                  'Terms and privacy policy',
                  () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LegalContentScreen()),
                  ),
                ),
                const SizedBox(height: 10),
                _linkTile(
                  Icons.dns_rounded,
                  Backend.isLive ? 'Connected to the live server' : 'Running on demo data',
                  () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ServerSettingsScreen()),
                  ),
                  tone: Backend.isLive ? SC.green : SC.amber,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _callCard() {
    return DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SUPPORT',
              style: TextStyle(
                  color: SC.gold, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
          const SizedBox(height: 10),
          Text(t('Talk to somebody'),
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(t('Every day, 8 AM to 8 PM. We answer in Hindi, English and Kannada.'),
              style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.45)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _darkAction(Icons.call_rounded, '1800 123 4567', () {
                  Clipboard.setData(const ClipboardData(text: '18001234567'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(t('Support number copied — 1800 123 4567'))),
                  );
                }),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _darkAction(Icons.mail_rounded, 'Email us', () {
                  Clipboard.setData(const ClipboardData(text: 'help@sathiyaa.in'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(t('Email copied — help@sathiyaa.in'))),
                  );
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _darkAction(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(SC.rField),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SC.rField),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _faq(int i) {
    final (q, a) = _faqs[i];
    final open = _open == i;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        onTap: () => setState(() => _open = open ? null : i),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(q, style: ST.h3)),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(Icons.expand_more_rounded, color: SC.inkFaint),
                ),
              ],
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 10, right: 6),
                child: Text(a, style: ST.body),
              ),
              crossFadeState: open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 180),
            ),
          ],
        ),
      ),
    );
  }

  Widget _linkTile(IconData icon, String label, VoidCallback onTap, {Color tone = SC.blueBright}) {
    return SCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: tone, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: ST.bodyStrong)),
          const Icon(Icons.chevron_right_rounded, color: SC.inkFaint),
        ],
      ),
    );
  }

}
