// Past, current and future bookings, each with the actions available at that
// stage — confirm, track, rate, or cancel. Cancelling quotes the fee before it
// commits (see BookingCancelScreen).
//
// Rebuilt on the design system. The three tabs are segmented controls carrying
// live counts rather than a plain TabBar, because "Current 2" answers the
// question the customer actually opened the screen with.

import 'dart:async';
import 'package:flutter/material.dart';

import '../backend.dart';
import '../models.dart';
import '../theme/sathiyaa_theme.dart';
import '../widgets/sathiyaa_ui.dart';
import '../widgets/motion.dart';
import 'booking_cancel_screen.dart';
import 'messages_screen.dart';
import 'booking_flow.dart';
import '../i18n/l10n.dart';

enum Bucket { current, future, past }

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  Bucket _bucket = Bucket.current;

  List<Booking> _all = const [];
  bool _loading = true;
  String? _error;
  DateTime? _lastChecked;
  Timer? _poll;

  /// No push channel yet, so a customer waiting for somebody to accept would
  /// otherwise have to close and reopen the app to find out anything happened.
  static const _pollEvery = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(_pollEvery, (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet && mounted) setState(() => _loading = true);
    try {
      final b = await Backend.instance.allBookings();
      if (!mounted) return;
      setState(() {
        _all = b;
        _error = null;
        _loading = false;
        _lastChecked = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // A silent poll that fails should not shout; a tap that fails should.
        _error = quiet ? _error : '$e'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  // ---- bucketing ------------------------------------------------------

  List<Booking> _inBucket(Bucket bucket) {
    final now = DateTime.now();
    switch (bucket) {
      case Bucket.current:
        return _all
            .where((b) =>
                b.status == BookingStatus.searching ||
                b.status == BookingStatus.confirmed ||
                b.status == BookingStatus.inProgress ||
                b.status == BookingStatus.providerOnWay ||
                b.status == BookingStatus.pendingPayment)
            .toList();
      case Bucket.past:
        return _all
            .where((b) =>
                b.status == BookingStatus.completed ||
                b.status == BookingStatus.cancelled ||
                b.endDate.isBefore(now))
            .toList();
      case Bucket.future:
        return _all
            .where((b) =>
                b.startDate.isAfter(now) &&
                b.status != BookingStatus.completed &&
                b.status != BookingStatus.cancelled)
            .toList();
    }
  }

  bool _cancellable(Booking b) =>
      b.status == BookingStatus.searching ||
      b.status == BookingStatus.pendingPayment ||
      b.status == BookingStatus.confirmed ||
      b.status == BookingStatus.providerOnWay;

  String _providerName(Booking b) {
    if (b.providerName != null && b.providerName!.isNotEmpty) return b.providerName!;
    final cached = Backend.instance.cachedProvider(b.providerId);
    if (cached != null) return cached.name;
    return b.providerId.isEmpty ? 'Looking for somebody' : 'Provider ${b.providerId}';
  }

  ChipTone _tone(BookingStatus s) => switch (s) {
        BookingStatus.completed => ChipTone.good,
        BookingStatus.cancelled => ChipTone.bad,
        BookingStatus.pendingPayment => ChipTone.warn,
        BookingStatus.inProgress || BookingStatus.providerOnWay => ChipTone.info,
        BookingStatus.confirmed => ChipTone.good,
        BookingStatus.searching => ChipTone.neutral,
      };

  // ---- build ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          BrandHeader(
            curved: false,
            child: BrandBar(
              title: t('Bookings'),
              subtitle: _lastChecked == null
                  ? 'Your care, past and upcoming'
                  : 'Checked at ${_hhmm(_lastChecked!)}',
              actions: [
                HeaderIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: t('Check again'),
                  onTap: () => _load(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(SC.gutter, 14, SC.gutter, 4),
            child: SegmentedTabs(
              tabs: const ['Current', 'Future', 'Past'],
              index: _bucket.index,
              badges: {
                0: _inBucket(Bucket.current).length,
                1: _inBucket(Bucket.future).length,
              },
              onChanged: (i) => setState(() => _bucket = Bucket.values[i]),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: SC.blueBright,
              child: FadeSwitch(child: _body()),
            ),
          ),
        ],
      ),
    );
  }

  String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Widget _body() {
    if (_loading && _all.isEmpty) {
      return const KeyedSubtree(
        key: ValueKey('loading'),
        child: Padding(
          padding: EdgeInsets.fromLTRB(SC.gutter, 14, SC.gutter, 0),
          child: SkeletonList(count: 3, lines: 2),
        ),
      );
    }

    if (_error != null && _all.isEmpty) {
      return ListView(
        key: const ValueKey('error'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(SC.gutter, 14, SC.gutter, 0),
        children: [InlineError(message: _error!, onRetry: () => _load())],
      );
    }

    final items = _inBucket(_bucket);

    if (items.isEmpty) {
      // Kept scrollable so pull-to-refresh still works — an empty list is
      // exactly where somebody reaches for it.
      return ListView(
        key: ValueKey('empty-${_bucket.name}'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(SC.gutter, 24, SC.gutter, 0),
        children: [
          EmptyState(
            icon: switch (_bucket) {
              Bucket.current => Icons.hourglass_empty_rounded,
              Bucket.future => Icons.event_available_rounded,
              Bucket.past => Icons.history_rounded,
            },
            title: switch (_bucket) {
              Bucket.current => 'Nothing happening right now',
              Bucket.future => 'Nothing booked ahead',
              Bucket.past => 'No completed visits yet',
            },
            message: switch (_bucket) {
              Bucket.current =>
                'Requests you are waiting on, and visits in progress, appear here.',
              Bucket.future =>
                'Bookings with a date further out will show up here once they are confirmed.',
              Bucket.past =>
                'Finished and cancelled bookings are kept here, with what was charged.',
            },
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(t('Pull down to check again'), style: ST.small),
          ),
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

  /// A thread exists from the moment somebody accepts until the visit is
  /// finished and settled. Before that there is nobody on the other end.
  bool _canMessage(Booking b) =>
      b.status == BookingStatus.confirmed ||
      b.status == BookingStatus.inProgress ||
      b.status == BookingStatus.completed;

  Widget _messageButton(Booking b) {
    final unread = b.unreadMessages;
    return OutlinedButton.icon(
      onPressed: () async {
        await push(context, MessagesScreen(booking: b));
        // The thread marks itself read on open, so the badge has to be
        // refreshed on the way back or it sits there saying otherwise.
        _load();
      },
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.chat_bubble_outline_rounded, size: 18),
          if (unread > 0)
            Positioned(
              right: -5,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 15),
                decoration: BoxDecoration(
                  color: SC.red,
                  borderRadius: BorderRadius.circular(SC.rPill),
                ),
                child: Text(
                  unread > 9 ? '9+' : '$unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800),
                ),
              ),
            ),
        ],
      ),
      label: Text(unread > 0 ? 'Messages ($unread new)' : 'Message'),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
    );
  }

  Widget _card(Booking b) {
    final searching = b.status == BookingStatus.searching;
    final needsPay = b.status == BookingStatus.pendingPayment;
    final live = b.status == BookingStatus.inProgress ||
        b.status == BookingStatus.providerOnWay;

    return SCard(
      padding: EdgeInsets.zero,
      onTap: () => _open(b),
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
                    if (searching)
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: SC.blueTint,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(child: LivePulse(color: SC.blueBright, size: 8)),
                      )
                    else if (live)
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
                      InitialsAvatar(name: _providerName(b), size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_providerName(b),
                              style: ST.h3,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 3),
                          Text('${b.serviceType.label} · ${_dates(b)}', style: ST.small),
                          const SizedBox(height: 2),
                          Text('${b.timeFrom} – ${b.timeTo}', style: ST.small),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: SC.inkFaint),
                  ],
                ),
                if (searching && b.providersNotified != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Asked ${b.providersNotified} nearby '
                    '${b.providersNotified == 1 ? 'provider' : 'providers'} — '
                    'the first to accept gets the visit.',
                    style: ST.small,
                  ),
                ],
                if (b.status == BookingStatus.cancelled && b.cancellationFee != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Cancellation fee ₹${b.cancellationFee!.toStringAsFixed(0)} · '
                    'refunded ₹${(b.refundAmount ?? 0).toStringAsFixed(0)}',
                    style: ST.small,
                  ),
                ],
                if (b.status == BookingStatus.completed && b.totalHours != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${b.totalHours!.toStringAsFixed(1)} hours worked · '
                    '₹${b.amountDue.toStringAsFixed(0)} '
                    '${b.amountReceived >= b.amountDue ? 'paid' : 'due'}',
                    style: ST.small,
                  ),
                ],
              ],
            ),
          ),
          if (needsPay || _cancellable(b) || _canMessage(b))
            Container(
              padding: const EdgeInsets.fromLTRB(15, 11, 15, 11),
              decoration: const BoxDecoration(
                color: SC.sunkTint,
                border: Border(top: BorderSide(color: SC.hairline)),
              ),
              child: Row(
                children: [
                  if (needsPay)
                    Expanded(
                      child: GradientButton(
                        label: t('Review and confirm'),
                        icon: Icons.verified_rounded,
                        height: 44,
                        onPressed: () => _open(b),
                      ),
                    )
                  else if (_canMessage(b))
                    Expanded(child: _messageButton(b))
                  else
                    Expanded(
                      child: Text(t('Free to cancel well before the start'), style: ST.small),
                    ),
                  if (_cancellable(b)) ...[
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: () async {
                        await push(context, BookingCancelScreen(booking: b));
                        _load();
                      },
                      style: TextButton.styleFrom(foregroundColor: SC.redDeep),
                      child: Text(t('Cancel')),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _dates(Booking b) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    String d(DateTime x) => '${x.day} ${m[x.month - 1]}';
    return b.startDate == b.endDate ? d(b.startDate) : '${d(b.startDate)} – ${d(b.endDate)}';
  }

  Future<void> _open(Booking b) async {
    switch (b.status) {
      case BookingStatus.confirmed:
      case BookingStatus.inProgress:
      case BookingStatus.providerOnWay:
      case BookingStatus.pendingPayment:
        await push(context, TrackServiceScreen(booking: b));
      case BookingStatus.completed:
        await push(
          context,
          b.customerRating == null
              ? RateProviderScreen(booking: b)
              : ServiceSummaryScreen(booking: b),
        );
      case BookingStatus.searching:
      case BookingStatus.cancelled:
        // Nothing to open — the card already says everything known about it.
        return;
    }
    _load();
  }
}
