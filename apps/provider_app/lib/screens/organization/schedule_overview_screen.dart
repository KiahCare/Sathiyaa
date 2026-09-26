import 'package:flutter/material.dart';

import '../../backend.dart';
import '../../models.dart';
import '../../theme/sathiyaa_theme.dart';
import '../../utils/dates.dart';
import '../../widgets/motion.dart';
import '../../widgets/sathiyaa_ui.dart';
import '../booking_detail_screen.dart';
import '../../i18n/l10n.dart';

/// Organisation Head view: every carer's day, with a tap-through to the booking.
///
/// Rebuilt on the design system. Date navigation is now a strip you can step
/// through a day at a time rather than only a date picker behind an icon, since
/// "what about tomorrow" is the question this screen is usually opened with.
class ScheduleOverviewScreen extends StatefulWidget {
  const ScheduleOverviewScreen({super.key});
  @override
  State<ScheduleOverviewScreen> createState() => _ScheduleOverviewScreenState();
}

class _ScheduleOverviewScreenState extends State<ScheduleOverviewScreen> {
  DateTime date = DateTime.now();

  bool get _isToday {
    final n = DateTime.now();
    return date.year == n.year && date.month == n.month && date.day == n.day;
  }

  Future<void> _pick() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (picked != null && mounted) setState(() => date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final employees = Backend.instance.currentProvider!.employees;
    final bookings = Backend.instance.myBookings
        .where((b) =>
            b.startDate.year == date.year &&
            b.startDate.month == date.month &&
            b.startDate.day == date.day)
        .toList();
    final unassigned = bookings.where((b) => b.assignedEmployeeId == null).toList();

    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          BrandHeader(
            curved: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(SC.gutter, 0, SC.gutter, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(t("The team's day"),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w800)),
                      ),
                      if (!_isToday)
                        TextButton(
                          onPressed: () => setState(() => date = DateTime.now()),
                          style: TextButton.styleFrom(foregroundColor: Colors.white),
                          child: Text(t('Today')),
                        ),
                      HeaderIconButton(
                        icon: Icons.calendar_today_rounded,
                        tooltip: t('Pick a date'),
                        onTap: _pick,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _Arrow(
                        icon: Icons.chevron_left_rounded,
                        onTap: () => setState(
                            () => date = date.subtract(const Duration(days: 1))),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(prettyDate(date),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                      _Arrow(
                        icon: Icons.chevron_right_rounded,
                        onTap: () =>
                            setState(() => date = date.add(const Duration(days: 1))),
                      ),
                    ],
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
                        message: t('Add the carers who work for you and their day will be laid out here, one row each.'),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 30),
                    children: staggered([
                      if (unassigned.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(13),
                          margin: const EdgeInsets.only(bottom: 18),
                          decoration: BoxDecoration(
                            color: SC.amberTint,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFF0DCBC)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  size: 18, color: Color(0xFFA9670F)),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Text(
                                  unassigned.length == 1
                                      ? 'One visit today has nobody allocated to it.'
                                      : '${unassigned.length} visits today have nobody allocated to them.',
                                  style: ST.small.copyWith(
                                      color: const Color(0xFF8A5510), height: 1.4),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      for (final e in employees)
                        _employee(e, bookings.where((b) => b.assignedEmployeeId == e.id).toList()),
                    ]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _employee(Employee e, List<ProviderBooking> theirs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InitialsAvatar(name: e.name, size: 38, radius: 12),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(e.name,
                      style: ST.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                StatusChip(
                  theirs.isEmpty
                      ? 'Free'
                      : theirs.length == 1
                          ? '1 visit'
                          : '${theirs.length} visits',
                  tone: theirs.isEmpty ? ChipTone.neutral : ChipTone.info,
                  dense: true,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (theirs.isEmpty)
              Text(t('Free all day — nothing allocated.'),
                  style: ST.small.copyWith(height: 1.45))
            else
              for (final b in theirs) _visit(b),
          ],
        ),
      ),
    );
  }

  Widget _visit(ProviderBooking b) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PressableScale(
        onTap: () async {
          await push(context, BookingDetailScreen(bookingId: b.id));
          if (mounted) setState(() {});
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: SC.sunkTint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.customerName,
                        style: ST.bodyStrong.copyWith(fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text('${b.serviceType.label} · ${b.timeFrom}–${b.timeTo}',
                        style: ST.small.copyWith(fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(b.status.label, dense: true),
              const Icon(Icons.chevron_right_rounded, color: SC.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 22, color: Colors.white),
      ),
    );
  }
}
