// The customer's Home tab.
//
// A gradient greeting header carrying the person's name, a mood check-in,
// the SOS card, and then whatever actually needs their attention — an active
// visit, a provider waiting to be rated, the next appointment. Every block is
// driven by real data and disappears when it has nothing to say, so the
// screen is never padded out with cards that do nothing.

import 'dart:async';
import 'package:flutter/material.dart';

import '../backend.dart';
import '../models.dart';
import '../theme/sathiyaa_theme.dart';
import '../widgets/sathiyaa_ui.dart';
import '../widgets/motion.dart';
import '../widgets/common.dart' show avatarImage;
import 'profile_screen.dart';
import 'notifications_screen.dart';
import 'sos_screen.dart';
import '../utils/dates.dart';
import '../i18n/l10n.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onGoToTab});

  /// Lets the Home tab hand the user to another tab (Companion / Bookings).
  final void Function(int index)? onGoToTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Booking> _bookings = const [];
  bool _loading = true;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    // No push channel yet, so anything that can change underneath the user
    // re-checks on a timer as well as on pull-to-refresh.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _load(quiet: true));
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
        _bookings = b;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Booking? get _active {
    for (final b in _bookings) {
      if (b.status == BookingStatus.inProgress) return b;
    }
    return null;
  }

  Booking? get _nextUp {
    final upcoming = _bookings
        .where((b) =>
            b.status == BookingStatus.confirmed ||
            b.status == BookingStatus.pendingPayment ||
            b.status == BookingStatus.searching)
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  Booking? get _awaitingRating {
    for (final b in _bookings) {
      if (b.status == BookingStatus.completed && b.customerRating == null) return b;
    }
    return null;
  }


  @override
  Widget build(BuildContext context) {
    final customer = Backend.instance.currentCustomer;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        color: SC.blueBright,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _header(customer)),
            SliverToBoxAdapter(
              child: PagePad(
                top: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FadeInUp(index: 0, child: _sosCard()),
                    const SizedBox(height: 14),
                    FadeSwitch(child: _content()),
                    const SizedBox(height: 16),
                    FadeInUp(index: 4, child: _quickActions()),
                    const SizedBox(height: 96),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The middle of the screen, which swaps between loading, error, empty and
  /// the real cards. Keyed so the cross-fade knows the state actually changed.
  Widget _content() {
    if (_error != null) {
      return KeyedSubtree(
        key: const ValueKey('error'),
        child: InlineError(message: _error!, onRetry: _load),
      );
    }
    if (_loading && _bookings.isEmpty) {
      return const KeyedSubtree(
        key: ValueKey('loading'),
        child: SkeletonList(count: 2, lines: 1),
      );
    }
    if (_bookings.isEmpty) {
      return KeyedSubtree(
        key: const ValueKey('empty'),
        child: EmptyState(
          icon: Icons.volunteer_activism_rounded,
          title: t('No care booked yet'),
          message: t('Find a companion or nurse near you and send them a request. You only pay once somebody accepts.'),
          actionLabel: t('Find a companion'),
          onAction: () => widget.onGoToTab?.call(1),
        ),
      );
    }

    final cards = <Widget>[
      if (_active != null) _activeVisitCard(_active!),
      if (_awaitingRating != null) _rateCard(_awaitingRating!),
      if (_nextUp != null) _nextUpCard(_nextUp!),
    ];

    return Column(
      key: ValueKey('cards-${_bookings.length}-${_active?.id}-${_nextUp?.status}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          FadeInUp(index: i + 1, child: cards[i]),
        ],
      ],
    );
  }

  // ---- header ---------------------------------------------------------

  Widget _header(Customer? customer) {
    return BrandHeader(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(SC.gutter, 6, SC.gutter, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SathiyaaLogo(size: 46),
                const SizedBox(width: 12),
                // Expanded rather than Text + Spacer. A Spacer only gives away
                // space that is left over, and this row has a 46px badge, a
                // 44px avatar and an icon button in it -- on a 360dp phone
                // there is none left over, so the title had nowhere to go and
                // the row overflowed by 18px at default text size, before
                // anybody touched their accessibility settings. At 200% it
                // overflowed by 202px.
                Expanded(
                  child: Text(t('Sathiyaa'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3)),
                ),
                HeaderIconButton(
                  icon: Icons.notifications_none_rounded,
                  badge: _bookings.isNotEmpty,
                  tooltip: t('Notifications'),
                  onTap: () => push(context, const NotificationsScreen()),
                ),
                const SizedBox(width: 10),
                PressableScale(
                  onTap: () => push(context, const ProfileScreen()),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2),
                    ),
                    child: InitialsAvatar(
                      name: customer?.name ?? '?',
                      size: 44,
                      radius: 22,
                      image: avatarImage(customer?.photoUrl),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            _name(customer?.name),
            const SizedBox(height: 26),
          ],
        ),
      ),
    );
  }

  /// The name, and only the name.
  ///
  /// A long Indian name at a fixed 30px wraps into two cramped lines under the
  /// logo, so the size steps down instead — the block keeps its shape whether
  /// the person is "Anita Rao" or "Lakshmi Venkataraman Iyer".
  Widget _name(String? name) {
    final n = (name == null || name.trim().isEmpty) ? 'Welcome' : name.trim();
    final size = n.length > 22
        ? 27.0
        : n.length > 16
            ? 31.0
            : 36.0;

    return Text(
      n,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: ST.display.copyWith(fontSize: size, height: 1.1),
    );
  }

  // ---- cards ----------------------------------------------------------

  Widget _sosCard() {
    return PressableScale(
      onTap: () => push(context, const SosScreen(), fromBottom: true),
      child: Container(
        decoration: BoxDecoration(
          gradient: SC.sosGradient,
          borderRadius: BorderRadius.circular(SC.rCard),
          boxShadow: const [
            BoxShadow(color: Color(0x33E33944), blurRadius: 18, offset: Offset(0, 6)),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.emergency_rounded, color: Colors.white, size: 27),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('EMERGENCY SOS'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4)),
                  const SizedBox(height: 2),
                  Text(t('Alert your family and companion'),
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(SC.rPill),
              ),
              child: Text(t('Open'),
                  style:
                      const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeVisitCard(Booking b) {
    final who = b.providerName ?? Backend.instance.cachedProvider(b.providerId)?.name;
    return DarkCard(
      onTap: () => widget.onGoToTab?.call(2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LivePulse(color: Color(0xFF6BE39A), size: 8),
              const SizedBox(width: 6),
              Text(t('VISIT IN PROGRESS'),
                  style: const TextStyle(
                      color: Color(0xFF6BE39A),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 10),
          Text(who ?? 'Your companion',
              style: const TextStyle(
                  color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('${b.serviceType.label} · ${b.timeFrom} – ${b.timeTo}',
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _rateCard(Booking b) {
    final who = b.providerName ?? Backend.instance.cachedProvider(b.providerId)?.name;
    return SCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: SC.goldTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.rate_review_rounded, color: SC.gold, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(t('Rate {name}', {'name': who ?? t('your companion')}),
                      style: ST.h3)),
            ],
          ),
          const SizedBox(height: 12),
          Text(t('How satisfied are you with the care you received?'), style: ST.body),
          const SizedBox(height: 10),
          StarPicker(
            value: 0,
            onChanged: (v) async {
              try {
                await Backend.instance.rateProvider(b.id, v.toDouble(), '');
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(t('Thank you for the feedback.'))));
                _load();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _nextUpCard(Booking b) {
    final who = b.providerName ?? Backend.instance.cachedProvider(b.providerId)?.name;
    final needsPay = b.status == BookingStatus.pendingPayment;
    final searching = b.status == BookingStatus.searching;

    return SCard(
      onTap: () => widget.onGoToTab?.call(2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Same reasoning as the header: "LOOKING FOR A COMPANION" is
              // long, the chip beside it is not optional, and a Spacer cannot
              // create room that does not exist.
              Expanded(
                child: Text(
                  searching
                      ? 'LOOKING FOR A COMPANION'
                      : needsPay
                          ? 'CONFIRM YOUR BOOKING'
                          : 'NEXT VISIT',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ST.label,
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(
                searching
                    ? 'Searching'
                    : needsPay
                        ? 'Action needed'
                        : 'Confirmed',
                tone: searching
                    ? ChipTone.info
                    : needsPay
                        ? ChipTone.warn
                        : ChipTone.good,
                dense: true,
              ),
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
              else
                InitialsAvatar(name: who ?? 'Companion', size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      searching ? '${b.serviceType.label} request sent' : (who ?? 'Your companion'),
                      style: ST.h3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      searching
                          ? (b.providersNotified == null
                              ? 'Waiting for someone to accept'
                              : 'Asked ${b.providersNotified} nearby ${b.providersNotified == 1 ? 'provider' : 'providers'}')
                          : '${b.serviceType.label} · ${_dayLabel(b.startDate)} · ${b.timeFrom}',
                      style: ST.small,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: SC.inkFaint),
            ],
          ),
          if (needsPay) ...[
            const SizedBox(height: 14),
            GradientButton(
              label: t('Review and confirm'),
              icon: Icons.verified_rounded,
              height: 50,
              onPressed: () => widget.onGoToTab?.call(2),
            ),
          ],
        ],
      ),
    );
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) return t('Today');
    if (diff == 1) return t('Tomorrow');
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${names[d.weekday - 1]} ${prettyDay(d)}';
  }

  Widget _quickActions() {
    final items = [
      (Icons.search_rounded, 'Find care', 1),
      (Icons.receipt_long_rounded, 'Bookings', 2),
      (Icons.support_agent_rounded, 'Help', 3),
    ];
    return Row(
      children: items.map((it) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: it == items.last ? 0 : 12),
            child: SCard(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
              onTap: () => widget.onGoToTab?.call(it.$3),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: SC.blueTint,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(it.$1, color: SC.blueBright, size: 21),
                  ),
                  const SizedBox(height: 9),
                  Text(it.$2,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700, color: SC.ink)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
