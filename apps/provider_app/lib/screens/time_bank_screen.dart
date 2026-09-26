// Impact.
//
// For somebody who gives their time free, this is the whole of what the app
// owes them — and the decision was that it should be nothing transactional.
// No points balance, no tier, no badge to collect. Points are still recorded
// in the Time Bank ledger for Sathiyaa's own reporting; they are simply not
// shown here as a score, because a score turns a gift into a transaction.
//
// What is shown instead is plain and true: hours given, people visited, and
// thank you. Paid providers see the same two numbers without the thank-you —
// it costs nothing and everybody likes seeing what they have done.

import 'package:flutter/material.dart';

import '../models.dart';
import '../backend.dart';
import '../theme/sathiyaa_theme.dart';
import '../widgets/sathiyaa_ui.dart';
import '../widgets/motion.dart';
import '../i18n/l10n.dart';

class TimeBankScreen extends StatelessWidget {
  const TimeBankScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Backend.instance.currentProvider;
    final volunteer = p?.noFees ?? false;

    final donated = Backend.instance.timeBank;
    final all = Backend.instance.myBookings
        .where((b) => b.status == BookingStatus.completed)
        .toList();

    // A volunteer's hours come from the ledger; a paid provider's from their
    // finished visits.
    final hours = volunteer
        ? donated.fold<double>(0, (s, e) => s + e.hours)
        : all.fold<double>(0, (s, b) => s + (b.totalHours ?? 0));
    final visits = volunteer ? donated.length : all.length;
    final people = volunteer
        ? donated.length // one ledger row per donated session
        : all.map((b) => b.customerId).toSet().length;

    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          BrandHeader(
            curved: false,
            child: BrandBar(
              title: t('Impact'),
              subtitle: volunteer ? 'The time you have given' : 'The care you have given',
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 110),
              children: [
                if (volunteer) FadeInUp(index: 0, child: _thanks(hours)),
                if (volunteer) const SizedBox(height: 14),
                FadeInUp(index: volunteer ? 1 : 0, child: _numbers(hours, visits, people)),
                const SizedBox(height: 22),
                SectionLabel(t('Visits')),
                if ((volunteer ? donated.length : all.length) == 0)
                  FadeInUp(
                    index: 2,
                    child: EmptyState(
                      icon: volunteer
                          ? Icons.favorite_border_rounded
                          : Icons.history_rounded,
                      title: volunteer ? 'Your first visit is ahead of you' : 'No finished visits yet',
                      message: volunteer
                          ? 'Each visit you finish will be listed here. Nothing is '
                              'billed, and nothing is owed to you — this page is just '
                              'a record of it.'
                          : 'Visits you complete will be listed here with the hours '
                              'you worked.',
                    ),
                  )
                else if (volunteer)
                  for (var i = 0; i < donated.length; i++)
                    Padding(
                      padding: EdgeInsets.only(bottom: i == donated.length - 1 ? 0 : 10),
                      child: FadeInUp(index: i + 2, child: _donatedRow(donated[i])),
                    )
                else
                  for (var i = 0; i < all.length; i++)
                    Padding(
                      padding: EdgeInsets.only(bottom: i == all.length - 1 ? 0 : 10),
                      child: FadeInUp(index: i + 1, child: _visitRow(all[i])),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The thank-you. Deliberately the first thing on the page, and deliberately
  /// not followed by a number they are accruing.
  Widget _thanks(double hours) {
    final warm = hours <= 0
        ? 'Thank you for offering your time.'
        : hours < 10
            ? 'Thank you. Somebody was not alone because of you.'
            : 'Thank you. That is a great deal of company you have given.';

    return DarkCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF14503C), Color(0xFF2E9E5B)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(t('You give your time free'),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(warm,
              style: const TextStyle(
                  color: Colors.white, fontSize: 19, height: 1.35, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            t('Nothing is charged to the families you visit, and nothing is owed to you. Sathiyaa keeps a record of every hour — that is all this page is.'),
            style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _numbers(double hours, int visits, int people) {
    return Row(
      children: [
        Expanded(child: _tile(Icons.schedule_rounded, hours.toStringAsFixed(1), 'hours given')),
        const SizedBox(width: 12),
        Expanded(
          child: _tile(Icons.groups_rounded, '$people',
              people == 1 ? 'person visited' : 'people visited'),
        ),
      ],
    );
  }

  Widget _tile(IconData icon, String value, String label) {
    return SCard(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: SC.blueBright),
          const SizedBox(height: 12),
          Text(value, style: ST.figure.copyWith(fontSize: 26)),
          const SizedBox(height: 3),
          Text(label, style: ST.small),
        ],
      ),
    );
  }

  Widget _donatedRow(TimeBankEntry e) {
    return SCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: SC.greenTint,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.favorite_rounded, color: SC.green, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.serviceType.label, style: ST.h3),
                const SizedBox(height: 3),
                Text(_date(e.date), style: ST.small),
              ],
            ),
          ),
          Text(t('{hours} h', {'hours': e.hours.toStringAsFixed(1)}),
              style: const TextStyle(
                  fontSize: 15.5, fontWeight: FontWeight.w800, color: SC.ink)),
        ],
      ),
    );
  }

  Widget _visitRow(ProviderBooking b) {
    return SCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          InitialsAvatar(name: b.customerName, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b.customerName,
                    style: ST.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text('${b.serviceType.label} · ${_date(b.startDate)}', style: ST.small),
              ],
            ),
          ),
          Text(t('{hours} h', {'hours': (b.totalHours ?? 0).toStringAsFixed(1)}),
              style: const TextStyle(
                  fontSize: 15.5, fontWeight: FontWeight.w800, color: SC.ink)),
        ],
      ),
    );
  }

  String _date(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }
}
