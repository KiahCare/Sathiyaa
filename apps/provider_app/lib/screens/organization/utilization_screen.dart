import 'package:flutter/material.dart';

import '../../backend.dart';
import '../../theme/sathiyaa_theme.dart';
import '../../utils/money.dart';
import '../../widgets/motion.dart';
import '../../widgets/sathiyaa_ui.dart';
import '../../i18n/l10n.dart';

/// How each carer on the team is doing: visits completed, money still owed by
/// families, and what those families thought of them.
///
/// Rebuilt on the design system. It also gained an empty state — an
/// organisation that has not added anybody yet used to get a blank white
/// screen with no explanation of what this page is for.
class UtilizationScreen extends StatelessWidget {
  const UtilizationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final employees = Backend.instance.currentProvider!.employees;

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
                        Text(t('How the team is doing'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(t('Completed visits, money owed, and ratings'),
                            style: const TextStyle(color: Colors.white70, fontSize: 13.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: employees.isEmpty
                ? Center(
                    child: PagePad(
                      child: EmptyState(
                        icon: Icons.groups_rounded,
                        title: t('Nobody on the team yet'),
                        message: t('Add the carers who work for you and this page will show what each of them has completed, what families still owe, and how they were rated.'),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 30),
                    children: staggered([
                      for (final e in employees) _card(e.name, e.id),
                    ]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _card(String name, String id) {
    final stats = Backend.instance.utilizationFor(id);
    final done = stats['completedBookings'] as int;
    final owed = stats['pendingPayment'] as double;
    final rating = stats['avgCustomerRating'] as double;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InitialsAvatar(name: name, size: 42, radius: 13),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: ST.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      if (rating > 0)
                        StarRating(value: rating, size: 13, showValue: true)
                      else
                        Text(t('Not rated yet'), style: ST.small.copyWith(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _figure('Visits done', '$done',
                      tone: done > 0 ? SC.green : SC.inkFaint),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _figure('Families still owe', inr(owed),
                      tone: owed > 0 ? SC.amber : SC.inkFaint),
                ),
              ],
            ),
            if (owed > 0) ...[
              const SizedBox(height: 10),
              Text(
                t('Collected at the end of the visit. Anything still here is worth a phone call.'),
                style: ST.small.copyWith(fontSize: 12, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _figure(String label, String value, {required Color tone}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SC.sunkTint,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: ST.label.copyWith(color: SC.inkFaint, fontSize: 10.5)),
            const SizedBox(height: 5),
            Text(value, style: ST.figure.copyWith(fontSize: 21, color: tone)),
          ],
        ),
      );
}
