// Emergency SOS.
//
// Taken from the reference build, but with the part that matters in an actual
// emergency made real: the people to call and the address to read out are on
// screen immediately, in large type, without scrolling.
//
// Holding the button now raises a real alert. The server records it, tells the
// family on the account and the carer on any visit in progress, and reports
// back what actually went out.
//
// The honesty rule, which everything below obeys: **the alert is always
// recorded, and nothing is claimed that did not happen.** With no SMS provider
// configured the server says `simulated` and this screen says so in as many
// words. Telling somebody their family has been notified when no message left
// is worse than telling them nothing — it stops them picking up the phone
// themselves, which in that moment is the only thing that helps.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend.dart';
import '../models.dart';
import '../theme/sathiyaa_theme.dart';
import '../widgets/sathiyaa_ui.dart';
import '../i18n/l10n.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  double _hold = 0;
  bool _armed = false;
  bool _raising = false;

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(t('{what} copied — {value}',
              {'what': label, 'value': value}))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Backend.instance.currentCustomer;
    final family = c?.family ?? const <FamilyMember>[];
    final primary = (c?.addresses ?? const <Address>[]).isNotEmpty ? c!.addresses.first : null;

    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          BrandHeader(
            curved: false,
            child: BrandBar(
              title: t('Emergency'),
              subtitle: t('Who to call, right now'),
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 32),
              children: [
                _holdButton(),
                const SizedBox(height: 22),
                SectionLabel(t('Emergency services')),
                _contactTile(
                  name: 'Ambulance',
                  detail: 'National emergency number',
                  number: '108',
                  tone: SC.red,
                  icon: Icons.local_hospital_rounded,
                ),
                const SizedBox(height: 10),
                _contactTile(
                  name: 'Police',
                  detail: 'National emergency number',
                  number: '112',
                  tone: SC.navy,
                  icon: Icons.local_police_rounded,
                ),
                const SizedBox(height: 22),
                SectionLabel('Your family (${family.length})'),
                if (family.isEmpty)
                  EmptyState(
                    compact: true,
                    icon: Icons.group_add_rounded,
                    title: t('No emergency contacts yet'),
                    message:
                        t('Add family members in your profile so they appear here when you need them.'),
                    actionLabel: t('Add a contact'),
                    onAction: () => Navigator.of(context).pop(),
                  )
                else
                  ...family.map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _contactTile(
                          name: f.name,
                          detail: f.relationship,
                          number: f.contact,
                          tone: SC.blueBright,
                          icon: Icons.person_rounded,
                        ),
                      )),
                const SizedBox(height: 22),
                SectionLabel(t('Read this out')),
                SCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FieldLabel(t('Where you are')),
                      Text(
                        primary == null
                            ? 'No address saved on your profile yet.'
                            : [primary.line1, primary.city]
                                .where((s) => s.trim().isNotEmpty)
                                .join(', '),
                        style: ST.h3.copyWith(height: 1.4),
                      ),
                      if (c?.bloodGroup != null && c!.bloodGroup!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        FieldLabel(t('Blood group')),
                        Text(c.bloodGroup!, style: ST.h1),
                      ],
                      if ((c?.allergies ?? const []).isNotEmpty) ...[
                        const SizedBox(height: 16),
                        FieldLabel(t('Allergies')),
                        Text(c!.allergies.map((a) => a.name).join(', '), style: ST.bodyStrong),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _holdButton() {
    return GestureDetector(
      onLongPressStart: (_) async {
        setState(() => _armed = true);
        for (var i = 0; i <= 10 && _armed; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 110));
          if (!mounted || !_armed) return;
          setState(() => _hold = i / 10);
        }
        if (mounted && _armed) {
          HapticFeedback.heavyImpact();
          _raise();
        }
      },
      onLongPressEnd: (_) => setState(() {
        _armed = false;
        _hold = 0;
      }),
      child: Container(
        height: 168,
        decoration: BoxDecoration(
          gradient: SC.sosGradient,
          borderRadius: BorderRadius.circular(SC.rCard),
          boxShadow: const [
            BoxShadow(color: Color(0x40E33944), blurRadius: 26, offset: Offset(0, 10)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: _hold,
                  child: Container(color: Colors.white.withValues(alpha: 0.22)),
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.emergency_rounded, color: Colors.white, size: 44),
                  const SizedBox(height: 12),
                  Text(t('HOLD TO ALERT'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2)),
                  const SizedBox(height: 4),
                  Text(
                    _raising
                        ? 'Raising the alert…'
                        : _armed
                            ? 'Keep holding…'
                            : 'Press and hold for one second',
                    style: const TextStyle(color: Colors.white70, fontSize: 13.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Raises the alert, then says what happened.
  ///
  /// Location is best-effort: the saved address is sent when there is one, and
  /// an alert with nothing but the button press is still accepted. Refusing an
  /// emergency over a missing field would be indefensible.
  Future<void> _raise() async {
    if (_raising) return;
    setState(() => _raising = true);

    final c = Backend.instance.currentCustomer;
    final primary = Backend.instance.primaryAddress();

    SosResult? result;
    String? error;
    try {
      result = await Backend.instance.raiseSos(
        lat: primary?.lat,
        lng: primary?.lng,
        addressText: primary == null
            ? null
            : [primary.line1, primary.city].where((s) => s.trim().isNotEmpty).join(', '),
        note: c == null ? null : 'Raised from the app by ${c.name}.',
      );
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    }

    if (!mounted) return;
    setState(() {
      _raising = false;
      _armed = false;
      _hold = 0;
    });
    _showAlertSheet(result: result, error: error);
  }

  void _showAlertSheet({SosResult? result, String? error}) {
    // Three outcomes, three different things worth saying. The one thing that
    // is the same in all three: call somebody, now.
    final sent = result != null && result.anythingSent;
    final recorded = result != null;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SC.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: SC.hairlineCool,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: sent ? SC.greenTint : const Color(0xFFFCE9EA),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    sent ? Icons.check_rounded : Icons.warning_amber_rounded,
                    color: sent ? const Color(0xFF1F7A45) : SC.redDeep,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    sent ? 'Your family has been told' : 'Call someone now',
                    style: ST.h2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              error != null
                  ? 'The alert could not be sent: $error\n\nCall the number below '
                      'directly — do not wait for this.'
                  : sent
                      ? '${result.notifiedCount} ${result.notifiedCount == 1 ? 'person has' : 'people have'} '
                          'been sent a message with where you are. Call somebody as well.'
                      : recorded
                          ? 'The alert is recorded and Sathiyaa can see it. No SMS service '
                              'is connected on this build, so no message was sent to your '
                              'family — call the number below yourself.'
                          : 'Nothing was sent. Call the number below directly.',
              style: ST.body.copyWith(height: 1.5),
            ),
            if (recorded && result.recipients.isNotEmpty) ...[
              const SizedBox(height: 16),
              FieldLabel(t('Who this was for')),
              ...result.recipients.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(
                          r.notified ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          size: 15,
                          color: r.notified ? SC.green : SC.inkFaint,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            '${r.name}${r.relationship == null ? '' : ' · ${r.relationship}'}',
                            style: ST.small,
                          ),
                        ),
                        Text(r.number, style: ST.small.copyWith(fontSize: 12)),
                      ],
                    ),
                  )),
            ],
            const SizedBox(height: 18),
            GradientButton(
              label: t('Call 108 — Ambulance'),
              icon: Icons.call_rounded,
              onPressed: () {
                Navigator.of(context).pop();
                _copy('Ambulance', '108');
              },
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(t('Close')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contactTile({
    required String name,
    required String detail,
    required String number,
    required Color tone,
    required IconData icon,
  }) {
    return SCard(
      onTap: () => _copy(name, number),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: tone, size: 23),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: ST.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(detail, style: ST.small, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(number,
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800, color: tone, height: 1.1)),
              const SizedBox(height: 2),
              Text(t('tap to copy'), style: const TextStyle(fontSize: 10.5, color: SC.inkFaint)),
            ],
          ),
        ],
      ),
    );
  }
}
