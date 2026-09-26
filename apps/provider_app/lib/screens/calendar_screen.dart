import 'package:flutter/material.dart';

import '../backend.dart';
import '../models.dart';
import '../theme/sathiyaa_theme.dart';
import '../utils/dates.dart';
import '../widgets/motion.dart';
import '../widgets/sathiyaa_ui.dart';
import 'booking_detail_screen.dart';
import '../i18n/l10n.dart';

/// The provider's calendar: which days are booked, which have hours free, and
/// which are blocked. Blocking is done from here — blocked days are hidden from
/// customer search, so this is how a provider takes time off.
///
/// Rebuilt on the design system. Month navigation moved into the header where
/// it belongs, the grid reads at arm's length, and there is a way back to today
/// after you have paged three months ahead — there was not one before.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime selected = DateTime.now();

  static const _dayNames = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  void _shiftMonth(int delta) {
    setState(() => month = DateTime(month.year, month.month + delta));
  }

  bool get _onThisMonth {
    final now = DateTime.now();
    return month.year == now.year && month.month == now.month;
  }

  Future<void> _block() async {
    final messenger = ScaffoldMessenger.of(context);
    final range = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: selected, end: selected),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Block these dates',
    );
    if (range == null || !mounted) return;

    final reasonCtrl = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: SC.surface,
          title: Text(t('Take these days off?'), style: ST.h2),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Families will not find you in search from '
                '${prettyDay(range.start)} to ${prettyDay(range.end)}.',
                style: ST.body,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: reasonCtrl,
                decoration: InputDecoration(hintText: t('Reason (optional)')),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('Block')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      await Backend.instance
          .blockCalendar(from: range.start, to: range.end, reason: reasonCtrl.text.trim());
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      reasonCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final back = Backend.instance;
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = firstOfMonth.weekday - 1; // Monday-first grid
    final cells = leadingBlanks + daysInMonth;

    final dayBookings = back.bookingsOn(selected);
    final freeHours = back.freeHoursOn(selected);
    final blockedHere = back.calendarBlocks.where((b) => b.covers(selected)).toList();
    final works = back.worksOn(selected);

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
                        child: Text(t('My calendar'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w800)),
                      ),
                      if (!_onThisMonth)
                        TextButton(
                          onPressed: () => setState(() {
                            final now = DateTime.now();
                            month = DateTime(now.year, now.month);
                            selected = now;
                          }),
                          style: TextButton.styleFrom(foregroundColor: Colors.white),
                          child: Text(t('Today')),
                        ),
                      HeaderIconButton(
                        icon: Icons.event_busy_rounded,
                        tooltip: t('Block dates'),
                        onTap: _block,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _MonthArrow(
                          icon: Icons.chevron_left_rounded,
                          onTap: () => _shiftMonth(-1)),
                      Expanded(
                        child: Center(
                          child: Text('${t(_monthName(month.month))} ${month.year}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                      _MonthArrow(
                          icon: Icons.chevron_right_rounded,
                          onTap: () => _shiftMonth(1)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(SC.gutter, 16, SC.gutter, 30),
              children: [
                SCard(
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          for (final d in _dayNames)
                            Expanded(
                              child: Center(
                                child: Text(d,
                                    style: ST.label.copyWith(color: SC.inkFaint)),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      GridView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 7, childAspectRatio: 0.92),
                        itemCount: cells,
                        itemBuilder: (context, i) {
                          if (i < leadingBlanks) return const SizedBox();
                          final day =
                              DateTime(month.year, month.month, i - leadingBlanks + 1);
                          return _DayCell(
                            day: day,
                            isSelected: _sameDay(day, selected),
                            bookings: back.bookingsOn(day).length,
                            blocked: back.isBlocked(day),
                            works: back.worksOn(day),
                            onTap: () => setState(() => selected = day),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      const _Legend(),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SectionLabel(
                  prettyDate(selected),
                  trailing: blockedHere.isNotEmpty
                      ? StatusChip(t('Blocked'), tone: ChipTone.bad, dense: true)
                      : StatusChip(
                          works ? '${freeHours.toStringAsFixed(1)}h free' : 'Not a work day',
                          tone: works && freeHours > 0 ? ChipTone.good : ChipTone.neutral,
                          dense: true,
                        ),
                ),
                SCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final block in blockedHere) ...[
                        Container(
                          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFCE9EA),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.event_busy_rounded,
                                  size: 17, color: SC.redDeep),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Off ${prettyDay(block.from)} – ${prettyDay(block.to)}'
                                  '${block.reason.isEmpty ? '' : ' · ${block.reason}'}',
                                  style: ST.small.copyWith(
                                      color: SC.redDeep, height: 1.4),
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  await Backend.instance.unblockCalendar(block.id);
                                  if (mounted) setState(() {});
                                },
                                style: TextButton.styleFrom(
                                    foregroundColor: SC.redDeep,
                                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                                child: Text(t('Undo')),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (dayBookings.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            works
                                ? 'Nothing booked — the whole working window is free.'
                                : 'You do not work this day.',
                            style: ST.small.copyWith(height: 1.45),
                          ),
                        )
                      else
                        for (final b in dayBookings) _bookingRow(b),
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

  Widget _bookingRow(ProviderBooking b) {
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
              InitialsAvatar(name: b.customerName, size: 38, radius: 12),
              const SizedBox(width: 11),
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
              const Icon(Icons.chevron_right_rounded, color: SC.inkFaint),
            ],
          ),
        ),
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _monthName(int m) => const [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ][m - 1];
}

class _MonthArrow extends StatelessWidget {
  const _MonthArrow({required this.icon, required this.onTap});
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

class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool isSelected;
  final int bookings;
  final bool blocked;
  final bool works;
  final VoidCallback onTap;
  const _DayCell({
    required this.day,
    required this.isSelected,
    required this.bookings,
    required this.blocked,
    required this.works,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isToday = _CalendarScreenState._sameDay(day, DateTime.now());

    Color bg = Colors.transparent;
    Color ink = SC.ink;
    if (blocked) {
      bg = const Color(0xFFFCE9EA);
      ink = SC.redDeep;
    } else if (bookings > 0) {
      bg = SC.blueTint;
      ink = SC.blue;
    } else if (!works) {
      bg = SC.sunkTint;
      ink = SC.inkFaint;
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: Dur.quick,
        curve: Ease.enter,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isSelected ? SC.navy : bg,
          borderRadius: BorderRadius.circular(10),
          border: isToday && !isSelected
              ? Border.all(color: SC.gold, width: 1.6)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: isToday || isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : ink,
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 5,
              child: blocked
                  ? Icon(Icons.close_rounded,
                      size: 10, color: isSelected ? Colors.white70 : SC.red)
                  : bookings > 0
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            bookings.clamp(1, 3),
                            (_) => Container(
                              width: 4,
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 1.2),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.white : SC.blueBright,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        )
                      : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget chip(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 6),
            Text(label, style: ST.small.copyWith(fontSize: 11.5)),
          ],
        );
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        chip(SC.blueTint, 'Booked'),
        chip(const Color(0xFFFCE9EA), 'Blocked'),
        chip(SC.sunkTint, 'Not a work day'),
        chip(SC.gold, 'Today'),
      ],
    );
  }
}
