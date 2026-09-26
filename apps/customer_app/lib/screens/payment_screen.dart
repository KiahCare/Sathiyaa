// Confirming and paying for a booking.
//
// Modelled on the reference build's payment screen, with one deliberate
// difference: that screen shows a single large total and a Pay button, which
// implies the whole visit is charged up front. It is not. Only the booking
// confirmation fee is taken now; the care itself is settled with the
// provider when the visit ends. Both numbers are on screen, and only one of
// them has a button next to it.
//
// NO PAYMENT PROVIDER IS CONNECTED. Choosing a method and continuing runs a
// short simulated authorisation and then calls the same
// payBookingCharge endpoint the app has always called. No money moves, and
// the screen says so before you commit to anything.

import 'dart:async';
import 'package:flutter/material.dart';

import '../backend.dart';
import '../models.dart';
import '../theme/sathiyaa_theme.dart';
import '../widgets/sathiyaa_ui.dart';
import '../widgets/motion.dart';
import '../utils/money.dart';
import '../i18n/l10n.dart';

enum PayMethod { upi, card, cash }

class UpiApp {
  const UpiApp(this.name, this.handle, this.color, this.glyph);
  final String name;
  final String handle;
  final Color color;
  final String glyph;
}

const kUpiApps = <UpiApp>[
  UpiApp('Google Pay', '@okaxis', Color(0xFF1A73E8), 'G'),
  UpiApp('PhonePe', '@ybl', Color(0xFF5F259F), 'P'),
  UpiApp('Paytm', '@paytm', Color(0xFF00BAF2), 'P'),
  UpiApp('BHIM UPI', '@upi', Color(0xFF00847F), 'B'),
];

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.booking});
  final Booking booking;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  PayMethod _method = PayMethod.upi;
  UpiApp _upiApp = kUpiApps.first;
  bool _busy = false;
  String? _error;

  Booking get b => widget.booking;

  double get _bookingFee => b.bookingCharge;
  double get _gst => _bookingFee * 0.18;
  double get _payNow => _bookingFee + _gst;

  /// What the visit itself is likely to come to, so the person is not
  /// surprised later. Settled with the provider at the end, not now.
  double? get _serviceEstimate {
    final rate = Backend.instance.cachedProvider(b.providerId)?.hourlyRate;
    if (rate == null || rate == 0) return null;
    final f = b.timeFrom.split(':');
    final t = b.timeTo.split(':');
    final mins = (int.parse(t[0]) * 60 + int.parse(t[1])) -
        (int.parse(f[0]) * 60 + int.parse(f[1]));
    final days = b.endDate.difference(b.startDate).inDays + 1;
    if (mins <= 0) return null;
    return rate * (mins / 60) * days;
  }

  Future<void> _pay() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    // A short pause so the simulated authorisation reads as an authorisation
    // rather than an instant no-op. Cash needs none.
    if (_method != PayMethod.cash) {
      await _showAuthorising();
      if (!mounted) return;
    }

    try {
      await Backend.instance.payBookingCharge(b.id);
      if (!mounted) return;
      await _showSuccess();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _showAuthorising() async {
    final label = switch (_method) {
      PayMethod.upi => 'Opening ${_upiApp.name}…',
      PayMethod.card => 'Authorising your card…',
      PayMethod.cash => '',
    };
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: SC.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SC.rCard)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(strokeWidth: 3, color: SC.blueBright),
              ),
              const SizedBox(height: 20),
              Text(label, style: ST.h3, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(t('Simulated — no payment provider is connected'),
                  style: ST.small, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _showSuccess() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: SC.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SC.rCard)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 32, 26, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SuccessCheck(),
              const SizedBox(height: 20),
              Text(t('Booking confirmed'), style: ST.h1, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                '${inr(_payNow)} received. Your companion has been told.',
                style: ST.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(t('Done')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Backend.instance.cachedProvider(b.providerId);
    final who = b.providerName ?? provider?.name ?? 'Your companion';

    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          BrandHeader(
            curved: false,
            child: BrandBar(
              title: t('Payment'),
              subtitle: t('Review and confirm'),
              onBack: _busy ? null : () => Navigator.of(context).pop(false),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 24),
              children: staggered([
                _serviceCard(),
                const SizedBox(height: 14),
                _providerCard(who, provider),
                const SizedBox(height: 22),
                SectionLabel(t('Payment method')),
                _methodTile(
                  PayMethod.upi,
                  Icons.account_balance_rounded,
                  'UPI',
                  'Google Pay, PhonePe, Paytm, BHIM',
                ),
                const SizedBox(height: 10),
                _methodTile(
                  PayMethod.card,
                  Icons.credit_card_rounded,
                  'Card',
                  'Credit or debit card',
                ),
                const SizedBox(height: 10),
                _methodTile(
                  PayMethod.cash,
                  Icons.payments_rounded,
                  'Cash on visit',
                  'Hand it to your companion when they arrive',
                ),
                if (_method == PayMethod.upi) ...[
                  const SizedBox(height: 14),
                  _upiChooser(),
                ],
                const SizedBox(height: 22),
                _billCard(),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  InlineError(message: _error!),
                ],
                const SizedBox(height: 16),
                _sandboxNote(),
                const SizedBox(height: 18),
                GradientButton(
                  label: _method == PayMethod.cash
                      ? 'Confirm booking'
                      : 'Pay ${inr(_payNow)}',
                  icon: _method == PayMethod.cash ? Icons.check_rounded : Icons.lock_rounded,
                  busy: _busy,
                  onPressed: _busy ? null : _pay,
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    b.paymentDeadline == null
                        ? 'You can cancel free of charge well before the visit.'
                        : 'Confirm before ${_hhmm(b.paymentDeadline!)} or the request is released.',
                    style: ST.small,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Widget _serviceCard() {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    String d(DateTime x) => '${x.day} ${months[x.month - 1]}';
    final range = b.startDate == b.endDate ? d(b.startDate) : '${d(b.startDate)} – ${d(b.endDate)}';

    return DarkCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.medical_services_rounded, color: Colors.white, size: 23),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: SC.gold.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(t('HOME CARE'),
                            style: const TextStyle(
                                color: SC.gold,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8)),
                      ),
                      const SizedBox(height: 6),
                      Text(b.serviceType.label,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.16)),
            child: Row(
              children: [
                Expanded(child: _pill(Icons.calendar_today_rounded, range)),
                const SizedBox(width: 10),
                Expanded(child: _pill(Icons.schedule_rounded, '${b.timeFrom} – ${b.timeTo}')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: Colors.white70),
          const SizedBox(width: 8),
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _providerCard(String who, Provider? p) {
    return SCard(
      child: Row(
        children: [
          InitialsAvatar(name: who, size: 54),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('YOUR COMPANION'), style: ST.label),
                const SizedBox(height: 4),
                Text(who, style: ST.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                if (p != null)
                  StarRating(value: p.ratingAvg, count: p.ratingCount, size: 14)
                else
                  Text(t('Accepted your request'), style: ST.small),
              ],
            ),
          ),
          if (p != null && p.noFees) StatusChip(t('No fee'), tone: ChipTone.good, dense: true),
        ],
      ),
    );
  }

  Widget _methodTile(PayMethod m, IconData icon, String title, String subtitle) {
    final on = _method == m;
    return PressableScale(
      onTap: _busy ? null : () => setState(() => _method = m),
      child: AnimatedContainer(
        duration: Dur.quick,
        curve: Ease.standard,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: on ? SC.blueTint : SC.surface,
          borderRadius: BorderRadius.circular(SC.rCard),
          border: Border.all(color: on ? SC.blueBright : SC.hairline, width: on ? 1.8 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: on ? Colors.white : SC.sunkTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 21, color: on ? SC.blueBright : SC.inkSoft),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: ST.h3.copyWith(fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: ST.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            AnimatedContainer(
              duration: Dur.quick,
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? SC.blueBright : Colors.transparent,
                border: Border.all(color: on ? SC.blueBright : SC.hairlineCool, width: 2),
              ),
              child: on
                  ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _upiChooser() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(t('Pay using')),
        Row(
          children: kUpiApps.map((a) {
            final on = _upiApp.name == a.name;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: a == kUpiApps.last ? 0 : 9),
                child: PressableScale(
                  onTap: _busy ? null : () => setState(() => _upiApp = a),
                  child: AnimatedContainer(
                    duration: Dur.quick,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: on ? Colors.white : SC.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: on ? a.color : SC.hairline, width: on ? 1.8 : 1),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: a.color.withValues(alpha: on ? 1 : 0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(a.glyph,
                              style: TextStyle(
                                  color: on ? Colors.white : a.color,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(height: 7),
                        Text(a.name.split(' ').first,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: on ? SC.ink : SC.inkFaint)),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _billCard() {
    final est = _serviceEstimate;
    return DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, color: SC.gold, size: 19),
              const SizedBox(width: 9),
              Text(t('Bill summary'),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          SummaryRow('Booking confirmation fee', inr(_bookingFee)),
          SummaryRow('GST (18%)', inr(_gst)),
          const SizedBox(height: 10),
          const DashedDivider(),
          const SizedBox(height: 10),
          SummaryRow('Payable now', inr(_payNow), emphasis: true),
          if (est != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(t('Care, paid after the visit'),
                          style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      Text(t('about {amount}', {'amount': inr(est)}),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t('Billed on the hours actually worked, and settled with your companion when they finish. Not charged today.'),
                    style: const TextStyle(color: Colors.white54, fontSize: 11.5, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sandboxNote() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: SC.amberTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF0DCBC)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFA9670F)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              t('Test mode. No payment provider is connected, so nothing is charged — choosing a method records the booking as paid so the rest of the journey can be tried end to end.'),
              style: ST.small.copyWith(color: const Color(0xFF8A5510), height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
