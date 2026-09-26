import 'package:flutter/material.dart';

import '../backend.dart';
import '../models.dart';
import '../theme/sathiyaa_theme.dart';
import '../utils/dates.dart';
import '../widgets/motion.dart';
import '../widgets/sathiyaa_ui.dart';
import '../i18n/l10n.dart';

/// Cancellation, with the fee shown before the customer commits. The tiers come
/// straight from the requirements doc; the same rule drives the preview here
/// and — against a live server — the server's own calculation, which is what
/// the confirmation then reports.
///
/// Rebuilt on the design system. The one change of substance is the button: it
/// used to say "Cancel this booking" whatever the cost, so the number the
/// customer was agreeing to was on a different part of the screen from the
/// press that agreed to it. Now it says what it will cost them.
class BookingCancelScreen extends StatefulWidget {
  final Booking booking;
  const BookingCancelScreen({super.key, required this.booking});

  @override
  State<BookingCancelScreen> createState() => _BookingCancelScreenState();
}

class _BookingCancelScreenState extends State<BookingCancelScreen> {
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final providerName =
        b.providerName ?? Backend.instance.cachedProvider(b.providerId)?.name ?? 'your carer';
    final quote = Backend.instance.quoteCancellation(b);
    final hours = quote.hoursBeforeStart;
    final free = quote.feeAmount <= 0;

    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          BrandHeader(
            curved: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, SC.gutter, 16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.chevron_left_rounded,
                        color: Colors.white, size: 30),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('Cancel this booking'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(t('Here is what it costs before you decide'),
                            style: const TextStyle(color: Colors.white70, fontSize: 13.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 26),
              children: staggered([
                SectionLabel(t('What you booked')),
                SCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(providerName, style: ST.h3),
                      const SizedBox(height: 6),
                      _line(Icons.medical_services_rounded, b.serviceType.label),
                      const SizedBox(height: 7),
                      _line(Icons.event_rounded,
                          '${prettyDate(b.startDate)} · ${b.timeFrom}–${b.timeTo}'),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: hours < 0 ? SC.amberTint : SC.sunkTint,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Text(
                          hours < 0
                              ? 'This visit has already started.'
                              : 'Starts in ${_hoursWord(hours)}.',
                          style: ST.small.copyWith(
                              color: hours < 0 ? const Color(0xFF8A5510) : SC.inkSoft),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SectionLabel(t('What cancelling costs')),
                SCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(quote.rule, style: ST.small.copyWith(height: 1.45)),
                      const SizedBox(height: 14),
                      _money('Booking charge you paid',
                          b.bookingChargePaid ? b.bookingCharge : 0),
                      _money('Cancellation fee', quote.feeAmount,
                          tone: quote.feeAmount > 0 ? SC.red : null),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: DashedDivider(),
                      ),
                      _money('Back to you', quote.refundAmount, big: true),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SC.red,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      textStyle: const TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w800),
                    ),
                    onPressed: busy ? null : _cancel,
                    child: busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(free
                            ? 'Cancel — no fee'
                            : 'Cancel and pay ₹${quote.feeAmount.toStringAsFixed(0)}'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: busy ? null : () => Navigator.pop(context, false),
                    style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    child: Text(t('Keep my booking')),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// "in 3 hours" is fine; "in 0.4 hours" is not how anyone speaks.
  String _hoursWord(double h) {
    if (h < 1) return '${(h * 60).round()} minutes';
    if (h < 24) return '${h.toStringAsFixed(h < 10 ? 1 : 0)} hours';
    final days = h / 24;
    return days < 2 ? 'about a day' : '${days.toStringAsFixed(0)} days';
  }

  Widget _line(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 16, color: SC.inkFaint),
          const SizedBox(width: 9),
          Expanded(child: Text(text, style: ST.body)),
        ],
      );

  Widget _money(String label, double amount, {bool big = false, Color? tone}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(label,
                style: big ? ST.bodyStrong : ST.small.copyWith(fontSize: 13.5)),
          ),
          Text('₹${amount.toStringAsFixed(0)}',
              style: (big ? ST.figure.copyWith(fontSize: 20) : ST.bodyStrong)
                  .copyWith(color: tone ?? (big ? SC.green : SC.ink))),
        ],
      ),
    );
  }

  Future<void> _cancel() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    try {
      final result = await Backend.instance.cancelBooking(widget.booking.id);
      if (!mounted) return;
      navigator.pop(true);
      messenger.showSnackBar(SnackBar(
        content: Text(
            'Booking cancelled. ₹${result.refundAmount.toStringAsFixed(0)} comes back to you.'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }
}
