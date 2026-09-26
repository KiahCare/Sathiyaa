// Notifications.
//
// The reference build shows a chat-style feed. There is no messaging service
// behind these apps, so rather than mock one, this screen derives its feed
// from the bookings the server actually returns: who accepted, what needs
// paying, which visit is next, what finished and still wants a rating.
//
// That means every line here corresponds to something real, and tapping one
// takes you to the thing it is about.

import 'package:flutter/material.dart';

import '../backend.dart';
import '../broadcasts.dart';
import '../models.dart';
import '../theme/sathiyaa_theme.dart';
import '../widgets/sathiyaa_ui.dart';
import '../i18n/l10n.dart';

enum NoteKind { notice, accepted, payDue, upcoming, rate, finished, searching }

class AppNotification {
  AppNotification({
    required this.kind,
    required this.title,
    required this.body,
    required this.when,
    this.booking,
  });

  final NoteKind kind;
  final String title;
  final String body;
  final DateTime when;
  final Booking? booking;

  bool get unread =>
      noticeUnread ||
      kind == NoteKind.accepted ||
      kind == NoteKind.payDue ||
      kind == NoteKind.rate;

  /// Set for a broadcast this phone has not opened before. Every other kind
  /// works out "unread" from the booking's state; a notice cannot, because
  /// the server remembers it instead.
  bool noticeUnread = false;

  (IconData, Color, Color) get look => switch (kind) {
        NoteKind.notice => (Icons.campaign_rounded, SC.blue, SC.blueTint),
        NoteKind.accepted => (Icons.verified_rounded, SC.green, SC.greenTint),
        NoteKind.payDue => (Icons.payments_rounded, SC.amber, SC.amberTint),
        NoteKind.upcoming => (Icons.event_available_rounded, SC.blueBright, SC.blueTint),
        NoteKind.rate => (Icons.star_rounded, SC.gold, SC.goldTint),
        NoteKind.finished => (Icons.check_circle_rounded, SC.inkSoft, const Color(0xFFF2F4F6)),
        NoteKind.searching => (Icons.radar_rounded, SC.blueLink, SC.blueTint),
      };
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  int _filter = 0;
  bool _loading = true;
  String? _error;
  List<AppNotification> _all = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final bookings = await Backend.instance.allBookings();
      // Messages an admin has broadcast. Best effort on top of the feed: an
      // older server with no /broadcasts route should show the bookings
      // rather than an error page.
      var notices = const <Broadcast>[];
      try {
        notices = await Backend.instance.loadBroadcasts();
      } catch (_) {
        // Leave the feed as it was.
      }
      if (!mounted) return;
      setState(() {
        _all = [..._noticesOf(notices), ..._derive(bookings)]
          ..sort((a, b) => b.when.compareTo(a.when));
        _error = null;
        _loading = false;
      });

      // Opening this screen is what reading them is. Fire and forget: a
      // failure here means the badge is wrong for a while, which is not worth
      // interrupting anybody over.
      if (notices.any((n) => !n.read)) {
        Backend.instance.markBroadcastsRead().catchError((_) {});
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  List<AppNotification> _noticesOf(List<Broadcast> notices) => [
        for (final n in notices)
          AppNotification(
            kind: NoteKind.notice,
            title: n.title,
            body: n.message,
            when: n.sentAt,
          )..noticeUnread = !n.read,
      ];

  List<AppNotification> _derive(List<Booking> bookings) {
    final out = <AppNotification>[];
    for (final b in bookings) {
      final who = b.providerName ?? Backend.instance.cachedProvider(b.providerId)?.name ?? 'A companion';
      switch (b.status) {
        case BookingStatus.searching:
          out.add(AppNotification(
            kind: NoteKind.searching,
            title: t('Looking for a companion'),
            body: b.providersNotified == null
                ? 'Your ${b.serviceType.label.toLowerCase()} request has gone out. We will tell you the moment somebody accepts.'
                : 'Your request went to ${b.providersNotified} ${b.providersNotified == 1 ? 'provider' : 'providers'}. Waiting for the first to accept.',
            when: b.startDate,
            booking: b,
          ));
        case BookingStatus.pendingPayment:
          out.add(AppNotification(
            kind: NoteKind.accepted,
            title: t('{name} accepted your request', {'name': who}),
            body: 'Confirm the booking to lock it in.',
            when: b.startDate,
            booking: b,
          ));
          out.add(AppNotification(
            kind: NoteKind.payDue,
            title: t('Confirmation needed'),
            body: b.paymentDeadline == null
                ? 'Review and confirm your booking.'
                : t('Confirm before {time} or the request is released.',
                    {'time': _time(b.paymentDeadline!)}),
            when: b.paymentDeadline ?? b.startDate,
            booking: b,
          ));
        case BookingStatus.confirmed:
        case BookingStatus.providerOnWay:
          out.add(AppNotification(
            kind: NoteKind.upcoming,
            title: t('Visit confirmed with {name}', {'name': who}),
            body: '${b.serviceType.label} · ${_date(b.startDate)} at ${b.timeFrom}.',
            when: b.startDate,
            booking: b,
          ));
        case BookingStatus.inProgress:
          out.add(AppNotification(
            kind: NoteKind.upcoming,
            title: t('{name} has started the visit', {'name': who}),
            body: t('Started at {time}.', {
                'time': b.serviceStartedAt == null ? b.timeFrom : _time(b.serviceStartedAt!)
              }),
            when: b.serviceStartedAt ?? b.startDate,
            booking: b,
          ));
        case BookingStatus.completed:
          if (b.customerRating == null) {
            out.add(AppNotification(
              kind: NoteKind.rate,
              title: t('How was {name}?', {'name': who}),
              body: 'Leave a rating — it helps the next family choose.',
              when: b.serviceEndedAt ?? b.endDate,
              booking: b,
            ));
          } else {
            out.add(AppNotification(
              kind: NoteKind.finished,
              title: t('Visit completed'),
              body: '$who · ${b.totalHours == null ? '' : '${b.totalHours!.toStringAsFixed(1)} hours · '}₹${b.amountDue.toStringAsFixed(0)}',
              when: b.serviceEndedAt ?? b.endDate,
              booking: b,
            ));
          }
        case BookingStatus.cancelled:
          out.add(AppNotification(
            kind: NoteKind.finished,
            title: t('Booking cancelled'),
            body: b.cancellationFee == null || b.cancellationFee == 0
                ? 'No cancellation fee was charged.'
                : 'Cancellation fee ₹${b.cancellationFee!.toStringAsFixed(0)}.',
            when: b.cancelledAt ?? b.endDate,
            booking: b,
          ));
      }
    }
    out.sort((a, b) => b.when.compareTo(a.when));
    return out;
  }

  String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _date(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]}';
  }

  List<AppNotification> get _visible => switch (_filter) {
        1 => _all.where((n) => n.unread).toList(),
        2 => _all.where((n) => n.booking?.status == BookingStatus.completed).toList(),
        _ => _all,
      };

  @override
  Widget build(BuildContext context) {
    final unread = _all.where((n) => n.unread).length;

    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          BrandHeader(
            curved: false,
            child: BrandBar(
              title: t('Notifications'),
              subtitle: unread == 0 ? 'You are all caught up' : '$unread need your attention',
              onBack: () => Navigator.of(context).pop(),
              actions: [
                HeaderIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: t('Check again'),
                  onTap: _load,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FilterChipRow(
            labels: const ['All', 'Needs action', 'Completed'],
            index: _filter,
            counts: {1: unread},
            onChanged: (i) => setState(() => _filter = i),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: SC.blueBright,
              child: _body(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(SC.gutter),
        children: [InlineError(message: _error!, onRetry: _load)],
      );
    }
    if (_loading && _all.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(SC.gutter),
        child: LoadingCards(count: 4, height: 84),
      );
    }
    final items = _visible;
    if (items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(SC.gutter),
        children: [
          EmptyState(
            icon: Icons.notifications_none_rounded,
            title: _filter == 1 ? 'Nothing needs you right now' : 'No notifications yet',
            message: _filter == 1
                ? 'Anything waiting on you — a booking to confirm, a companion to rate — shows up here.'
                : 'Once you book care, updates about it appear here.',
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(SC.gutter, 10, SC.gutter, 32),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 11),
      itemBuilder: (context, i) => _tile(items[i]),
    );
  }

  Widget _tile(AppNotification n) {
    final (icon, fg, bg) = n.look;
    return SCard(
      padding: const EdgeInsets.all(15),
      onTap: n.booking == null ? null : () => Navigator.of(context).pop(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, color: fg, size: 22),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(n.title,
                          style: ST.h3.copyWith(fontSize: 15),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (n.unread)
                      Container(
                        width: 9,
                        height: 9,
                        margin: const EdgeInsets.only(left: 8, top: 4),
                        decoration: const BoxDecoration(color: SC.gold, shape: BoxShape.circle),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(n.body, style: ST.body.copyWith(fontSize: 13.5)),
                if (n.booking != null) ...[
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      StatusChip(n.booking!.status.label, tone: _tone(n.booking!.status), dense: true),
                      const SizedBox(width: 8),
                      Text(n.booking!.id, style: ST.small.copyWith(fontSize: 11)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  ChipTone _tone(BookingStatus s) => switch (s) {
        BookingStatus.completed => ChipTone.good,
        BookingStatus.cancelled => ChipTone.bad,
        BookingStatus.pendingPayment => ChipTone.warn,
        BookingStatus.inProgress => ChipTone.info,
        _ => ChipTone.neutral,
      };
}
