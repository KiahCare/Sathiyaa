// The provider's Jobs tab.
//
// Three buckets: requests waiting on an answer, work that is accepted or
// running, and everything finished. Rebuilt on the design system, with the
// counts on the tabs — "Requests 2" is the reason a carer opens the app.
//
// There is no push notification in this build, so the screen re-checks every
// twenty seconds and says when it last looked. Without that a provider has to
// close and reopen the app to find out a request arrived, which is exactly
// what somebody does when they think an app is broken.

import 'dart:async';
import 'package:flutter/material.dart';

import '../models.dart';
import '../backend.dart';
import '../theme/sathiyaa_theme.dart';
import '../widgets/sathiyaa_ui.dart';
import '../widgets/motion.dart';
import 'booking_detail_screen.dart';
import '../i18n/l10n.dart';

enum JobBucket { requests, upcoming, history }

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  JobBucket _bucket = JobBucket.requests;

  Timer? _poll;
  bool _refreshing = false;
  DateTime? _lastRefreshed;
  String? _refreshError;

  static const _pollEvery = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(_pollEvery, (_) => _refresh(silent: true));
    // Don't wait twenty seconds to show what is already there.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_refreshing) return;
    if (!silent && mounted) setState(() => _refreshing = true);
    try {
      await Backend.instance.refresh();
      if (!mounted) return;
      setState(() {
        _lastRefreshed = DateTime.now();
        _refreshError = null;
        _refreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // A silent poll that fails should not shout; a tap that fails should.
        _refreshError =
            silent ? _refreshError : 'Could not reach the server. Pull down to try again.';
        _refreshing = false;
      });
    }
  }

  String get _lastRefreshedLabel {
    if (_lastRefreshed == null) return t('Checking for new requests…');
    final secs = DateTime.now().difference(_lastRefreshed!).inSeconds;
    if (secs < 30) return t('Up to date · checks every 20 seconds');
    if (secs < 120) return t('Updated a minute ago');
    return t('Updated {count} minutes ago', {'count': (secs / 60).floor()});
  }

  List<ProviderBooking> _inBucket(JobBucket b) {
    final all = Backend.instance.myBookings;
    return switch (b) {
      JobBucket.requests => all.where((x) => x.status == BookingStatus.requested).toList(),
      JobBucket.upcoming => all
          .where((x) =>
              x.status == BookingStatus.accepted || x.status == BookingStatus.inProgress)
          .toList(),
      JobBucket.history => all
          .where((x) =>
              x.status == BookingStatus.completed || x.status == BookingStatus.cancelled)
          .toList(),
    };
  }

  ChipTone _tone(BookingStatus s) => switch (s) {
        BookingStatus.completed => ChipTone.good,
        BookingStatus.cancelled => ChipTone.bad,
        BookingStatus.inProgress => ChipTone.info,
        BookingStatus.accepted => ChipTone.good,
        BookingStatus.requested => ChipTone.warn,
      };

  @override
  Widget build(BuildContext context) {
    final locationOff = !(Backend.instance.currentProvider?.locationOn ?? false);
    final requests = _inBucket(JobBucket.requests).length;
    final upcoming = _inBucket(JobBucket.upcoming).length;

    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          BrandHeader(
            curved: false,
            child: BrandBar(
              title: t('Jobs'),
              subtitle: _refreshError ?? _lastRefreshedLabel,
              actions: [
                HeaderIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: t('Check for new requests'),
                  onTap: _refreshing ? null : () => _refresh(),
                ),
              ],
            ),
          ),
          if (locationOff)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(SC.gutter, 14, SC.gutter, 0),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFFFCE9EA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF2C7CA)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_off_rounded, size: 18, color: SC.redDeep),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t('Location sharing is off. Turn it on from Home before you can accept a request.'),
                      style: const TextStyle(
                          color: SC.redDeep,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(SC.gutter, 14, SC.gutter, 4),
            child: SegmentedTabs(
              tabs: const ['Requests', 'Upcoming', 'History'],
              index: _bucket.index,
              badges: {0: requests, 1: upcoming},
              onChanged: (i) => setState(() => _bucket = JobBucket.values[i]),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _refresh(),
              color: SC.blueBright,
              child: FadeSwitch(child: _body()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    final items = _inBucket(_bucket);

    if (items.isEmpty) {
      // Still scrollable, so pull-to-refresh works here too — an empty
      // Requests tab is exactly where somebody reaches for it.
      return ListView(
        key: ValueKey('empty-${_bucket.name}'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(SC.gutter, 24, SC.gutter, 0),
        children: [
          EmptyState(
            icon: switch (_bucket) {
              JobBucket.requests => Icons.inbox_rounded,
              JobBucket.upcoming => Icons.event_available_rounded,
              JobBucket.history => Icons.history_rounded,
            },
            title: switch (_bucket) {
              JobBucket.requests => 'No requests waiting',
              JobBucket.upcoming => 'Nothing coming up',
              JobBucket.history => 'No finished visits yet',
            },
            message: switch (_bucket) {
              JobBucket.requests =>
                'When a family near you asks for care you can give, it lands here. '
                    'Go on duty from Home so they can find you.',
              JobBucket.upcoming =>
                'Requests you accept move here, with the address and the customer’s '
                    'number once the job is yours.',
              JobBucket.history =>
                'Completed and cancelled visits are kept here with the hours worked '
                    'and what was paid.',
            },
          ),
          const SizedBox(height: 14),
          Center(child: Text(t('Pull down to check again'), style: ST.small)),
        ],
      );
    }

    return ListView.builder(
      key: ValueKey('list-${_bucket.name}-${items.length}'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(SC.gutter, 14, SC.gutter, 110),
      itemCount: items.length,
      itemBuilder: (context, i) => Padding(
        padding: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 12),
        child: FadeInUp(index: i, child: _card(items[i])),
      ),
    );
  }

  Widget _card(ProviderBooking b) {
    final isRequest = b.status == BookingStatus.requested;
    final running = b.status == BookingStatus.inProgress;

    return SCard(
      padding: EdgeInsets.zero,
      onTap: () async {
        await push(context, BookingDetailScreen(bookingId: b.id));
        if (mounted) setState(() {});
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 15, 15, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(b.id, style: ST.label)),
                    StatusChip(b.status.label, tone: _tone(b.status), dense: true),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (running)
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: SC.greenTint,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(child: LivePulse(size: 8)),
                      )
                    else
                      InitialsAvatar(name: b.customerName, size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(b.customerName,
                              style: ST.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 3),
                          Text('${b.serviceType.label} · ${_date(b.startDate)}',
                              style: ST.small),
                          const SizedBox(height: 2),
                          Text('${b.timeFrom} – ${b.timeTo}', style: ST.small),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: SC.inkFaint),
                  ],
                ),
                if (isRequest) ...[
                  const SizedBox(height: 11),
                  Row(
                    children: [
                      const Icon(Icons.place_rounded, size: 14, color: SC.inkFaint),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          // Until the job is accepted the server sends the
                          // area only, not the full address — one request goes
                          // out to many strangers.
                          b.customerAddress.isEmpty ? 'Nearby' : b.customerAddress,
                          style: ST.small,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (b.status == BookingStatus.completed && b.totalHours != null) ...[
                  const SizedBox(height: 10),
                  Text(t('{hours} hours worked',
                          {'hours': b.totalHours!.toStringAsFixed(1)}),
                      style: ST.small),
                ],
              ],
            ),
          ),
          if (isRequest)
            Container(
              padding: const EdgeInsets.fromLTRB(15, 11, 15, 11),
              decoration: const BoxDecoration(
                color: SC.sunkTint,
                border: Border(top: BorderSide(color: SC.hairline)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GradientButton(
                      label: t('Open request'),
                      icon: Icons.open_in_new_rounded,
                      height: 44,
                      onPressed: () async {
                        await push(context, BookingDetailScreen(bookingId: b.id));
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _date(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) return t('Today');
    if (diff == 1) return t('Tomorrow');
    return '${d.day} ${m[d.month - 1]}';
  }
}
