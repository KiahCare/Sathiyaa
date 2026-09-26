// The provider's Home tab.
//
// Rebuilt on the design system. The shape follows what a carer actually needs
// when they open the app: am I on duty, what is happening today, what have I
// earned. Everything else is one tap away rather than on the first screen.
//
// Location sharing stays at the top because the spec makes it a precondition
// for accepting work — you cannot take a job the app cannot place you at.

import 'dart:async';
import 'package:flutter/material.dart';

import '../models.dart';
import '../backend.dart';
import '../theme/sathiyaa_theme.dart';
import '../widgets/sathiyaa_ui.dart';
import '../utils/approval.dart';
import '../widgets/motion.dart';
import '../widgets/common.dart' show avatarImage;
import '../services/location_service.dart';
import 'broadcasts_screen.dart';
import 'profile_screen.dart';
import 'organization/employees_screen.dart';
import 'organization/utilization_screen.dart';
import 'organization/schedule_overview_screen.dart';
import '../i18n/l10n.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.onGoToTab});

  final void Function(int index)? onGoToTab;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String period = 'Today';

  int _unreadNotices = 0;

  bool _locationBusy = false;
  String? _locationNote;
  bool _locationError = false;
  Timer? _locationTimer;
  Timer? _poll;

  @override
  void initState() {
    super.initState();

    // Sharing survives the app being closed, so the reporting has to as well.
    //
    // location_on lives on the server. Somebody who turned it on last week
    // opens the app today with the switch showing ON — and until now nothing
    // started the timer, because the timer was only ever started by tapping
    // the switch. Their pin on the admin's tracking map sat at last week's
    // coordinates, looking exactly like a current position.
    if (Backend.instance.currentProvider?.locationOn == true) {
      _resumeLocationUpdates();
    }

    _loadUnread();

    // Today's work can change underneath the provider while they are looking
    // at it — a customer confirms, an org reassigns.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) async {
      try {
        await Backend.instance.refresh();
      } catch (_) {
        // A silent poll that fails should not shout.
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  /// Turning this on asks the phone for a real position.
  ///
  /// It used to flip a flag on the server and nothing else — the only place
  /// that ever reported a position sent the *customer's* coordinates, so a
  /// provider's pin on the tracking map was wherever their booking was, not
  /// where they were.
  Future<void> _setLocationSharing(bool on) async {
    setState(() {
      _locationBusy = true;
      _locationError = false;
      _locationNote = on ? 'Getting your location…' : null;
    });

    if (!on) {
      _locationTimer?.cancel();
      _locationTimer = null;
      await Backend.instance.setLocationOn(false);
      if (!mounted) return;
      setState(() {
        _locationBusy = false;
        _locationNote = null;
      });
      return;
    }

    final fix = await LocationService.current();
    if (!mounted) return;
    if (!fix.isOk) {
      setState(() {
        _locationBusy = false;
        _locationError = true;
        _locationNote = fix.error;
      });
      return;
    }

    await Backend.instance.setLocationOn(true);
    await Backend.instance.pingLocation(fix.lat!, fix.lng!);
    _startLocationUpdates();
    if (!mounted) return;
    setState(() {
      _locationBusy = false;
      _locationNote = fix.accuracyMetres == null
          ? 'Sharing your location'
          : 'Sharing your location · accurate to about ${fix.accuracyMetres!.round()} m';
    });
  }

  /// The badge on the notices bell. Silent on failure: an older server with
  /// no /broadcasts route should show no badge, not an error.
  Future<void> _loadUnread() async {
    try {
      final items = await Backend.instance.loadBroadcasts();
      if (!mounted) return;
      setState(() => _unreadNotices = items.where((b) => !b.read).length);
    } catch (_) {
      if (mounted) setState(() => _unreadNotices = 0);
    }
  }

  /// Picks reporting back up for a session that opened with sharing already
  /// on. Sends one fix straight away so the map is not two minutes stale, and
  /// says nothing if the phone refuses — the carer did not ask for anything
  /// here, so there is nothing to report back to them.
  Future<void> _resumeLocationUpdates() async {
    _startLocationUpdates();
    final fix = await LocationService.current();
    if (!mounted || !fix.isOk) return;
    try {
      await Backend.instance.pingLocation(fix.lat!, fix.lng!);
    } catch (_) {
      // The timer will try again in two minutes.
    }
  }

  /// A fresh position every couple of minutes while sharing is on. Often
  /// enough for the admin's tracking map to be worth looking at, rare enough
  /// not to flatten the battery.
  void _startLocationUpdates() {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      final fix = await LocationService.current(timeout: const Duration(seconds: 20));
      if (!mounted || !fix.isOk) return;
      try {
        await Backend.instance.pingLocation(fix.lat!, fix.lng!);
      } catch (_) {
        // A lost signal or a server hiccup must not take the timer down with
        // it: an uncaught throw inside Timer.periodic kills the whole
        // schedule, and sharing would silently stop for the rest of the day.
      }
    });
  }

  // ---- today's work ---------------------------------------------------

  List<ProviderBooking> get _today {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    return Backend.instance.bookingsOn(day);
  }

  ProviderBooking? get _running {
    for (final b in _today) {
      if (b.status == BookingStatus.inProgress) return b;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = Backend.instance.currentProvider!;
    final stats = Backend.instance.statsFor(period);
    final isOrg = p.kind == ProviderKind.organization;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await Backend.instance.refresh();
          if (mounted) setState(() {});
        },
        color: SC.blueBright,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            _header(p),
            Padding(
              padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 110),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // An organisation does not go on duty; its carers do. The
                  // duty switch is replaced by what an agency actually opens
                  // this screen to see.
                  if (isOrg)
                    FadeInUp(index: 0, child: _orgDutyCard(p))
                  else
                    FadeInUp(index: 0, child: _dutyCard(p)),
                  const SizedBox(height: 14),
                  if (_running != null) ...[
                    FadeInUp(index: 1, child: _runningCard(_running!)),
                    const SizedBox(height: 14),
                  ],
                  FadeInUp(index: 2, child: _todayCard()),
                  const SizedBox(height: 22),
                  // Instead of, not as well as. A volunteer used to get the
                  // earnings card -- with a large "₹0" at the top of it --
                  // followed by a card explaining that they are not paid.
                  // Nobody who gives their time free needs to be shown a
                  // running total of the money they did not make.
                  if (p.noFees) ...[
                    FadeInUp(index: 3, child: _contribution(stats)),
                    const SizedBox(height: 14),
                    FadeInUp(index: 4, child: _volunteerCard()),
                  ] else
                    FadeInUp(index: 3, child: _earnings(stats)),
                  if (isOrg) ...[
                    const SizedBox(height: 22),
                    FadeInUp(index: 5, child: _orgCard(p)),
                  ],
                  const SizedBox(height: 22),
                  FadeInUp(index: 6, child: _approvalCard(p)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- header ---------------------------------------------------------

  Widget _header(ProviderProfile p) {
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
                // Expanded, not Text + Spacer. A Spacer only hands out space
                // that is left over, and between a 46px badge and a 44px
                // avatar there is none on a narrow phone -- so the title had
                // nowhere to go and this row overflowed. The customer app's
                // header had the identical bug.
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
                // Notices from Sathiyaa. There was no way to read one at
                // all: the console could send to every carer and the message
                // arrived nowhere.
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    HeaderIconButton(
                      icon: Icons.campaign_rounded,
                      tooltip: t('From Sathiyaa'),
                      onTap: () async {
                        await push(context, const BroadcastsScreen());
                        if (mounted) _loadUnread();
                      },
                    ),
                    if (_unreadNotices > 0)
                      Positioned(
                        right: -1,
                        top: -1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          constraints: const BoxConstraints(minWidth: 17),
                          decoration: BoxDecoration(
                            color: SC.red,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: SC.navy, width: 1.5),
                          ),
                          child: Text(
                            _unreadNotices > 9 ? '9+' : '$_unreadNotices',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                  ],
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
                      name: p.name,
                      size: 44,
                      radius: 22,
                      image: avatarImage(p.photoUrl),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            _name(p.name),
            const SizedBox(height: 26),
          ],
        ),
      ),
    );
  }

  /// What stands in for the duty switch until the account is approved.
  ///
  /// It says the status, what it means, and what happens next, rather than
  /// offering a control that cannot work. The gradient is the deep one, so
  /// the screen still reads as off rather than as broken.
  Widget _blockedDutyCard(ProviderProfile p) {
    final a = approvalPresentation(p.approvalStatus);
    return DarkCard(
      gradient: SC.brandGradientDeep,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_clock_rounded, size: 15, color: Colors.white60),
              const SizedBox(width: 6),
              Text(a.label.toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 10),
          Text(t('You cannot go on duty yet'),
              style: const TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            a.note,
            style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.45),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 18, color: Colors.white70),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t('The switch turns on by itself once Sathiyaa approves your account.'),
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12.5, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The organisation's version of the duty card: how many of its carers are
  /// out, and how many cannot be sent anywhere because their paperwork is
  /// missing -- which is the thing an agency most needs to be told, and the
  /// thing nothing on this screen used to say.
  Widget _orgDutyCard(ProviderProfile p) {
    final total = p.employees.length;
    // "Ready" means allocatable: not blocked, and with the documents a family
    // is told every carer has. Counting merely-unblocked carers here put two
    // numbers that contradicted each other on the same card.
    final ready = p.employees
        .where((e) => e.status == EmployeeStatus.active && e.documentsComplete)
        .length;
    final unverified = p.employees
        .where((e) => e.status == EmployeeStatus.active && !e.documentsComplete)
        .length;
    final blocked = total - ready - unverified;

    return DarkCard(
      // The deep gradient when something needs attention, so the card reads
      // as "look at this" before a word of it has been read.
      gradient: unverified > 0 || total == 0 ? SC.brandGradientDeep : SC.brandGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (ready > 0) const LivePulse(color: Color(0xFF6BE39A), size: 8),
              if (ready > 0) const SizedBox(width: 6),
              Text(t('YOUR CARERS'),
                  style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            total == 0
                ? t('No carers added yet')
                : t('{ready} of {total} ready to work',
                    {'ready': ready, 'total': total}),
            style: const TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            total == 0
                ? t('Add the people who work for you. Each one needs their own Aadhaar and police verification before they can be sent to a family.')
                : unverified > 0
                    ? t('{count} cannot be sent to a family yet — their documents are missing or out of date.',
                        {'count': unverified})
                    : blocked > 0
                        ? t('Everyone else on your list is verified. {count} is blocked.',
                            {'count': blocked})
                        : t('Everyone on your list is verified and can be allocated.'),
            style: TextStyle(
              color: unverified > 0 ? const Color(0xFFFFD9A8) : Colors.white70,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => push(context, const EmployeesScreen()),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                  ),
                  icon: const Icon(Icons.groups_rounded, size: 18),
                  label: Text(total == 0 ? t('Add a carer') : t('Manage carers')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Same treatment as the customer app: the name carries the block alone and
  /// steps down in size rather than wrapping into a cramped second line.
  Widget _name(String name) {
    final n = name.trim().isEmpty ? 'Welcome' : name.trim();
    final size = n.length > 22
        ? 27.0
        : n.length > 16
            ? 31.0
            : 36.0;
    return Text(n,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: ST.display.copyWith(fontSize: size, height: 1.1));
  }

  // ---- cards ----------------------------------------------------------

  Widget _dutyCard(ProviderProfile p) {
    // Going on duty means being offered visits. An account that has not been
    // approved cannot be offered any, so the switch was a control that did
    // nothing -- it turned on, and then no request ever arrived, with nothing
    // on screen connecting the two.
    if (!canTakeWork(p.approvalStatus)) return _blockedDutyCard(p);
    final on = p.locationOn;
    return DarkCard(
      gradient: on ? SC.brandGradient : SC.brandGradientDeep,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (on) const LivePulse(color: Color(0xFF6BE39A), size: 8),
              if (on) const SizedBox(width: 6),
              Text(on ? 'ON DUTY' : 'OFF DUTY',
                  style: TextStyle(
                      color: on ? const Color(0xFF6BE39A) : Colors.white60,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 10),
          Text(on ? 'You are visible to families' : 'Ready to provide care?',
              style: const TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            _locationNote ??
                (on
                    ? 'Turn this off when you finish for the day.'
                    : 'Share your location to start receiving requests. Nobody can be '
                        'sent to you without it.'),
            style: TextStyle(
              color: _locationError ? const Color(0xFFFFB4B4) : Colors.white70,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(on ? 'Sharing location' : 'Go on duty',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              if (_locationBusy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                )
              else
                Switch(
                  value: on,
                  onChanged: (v) => _setLocationSharing(v),
                  activeThumbColor: Colors.white,
                  activeTrackColor: const Color(0xFF3FA871),
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: Colors.white24,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _runningCard(ProviderBooking b) {
    return SCard(
      onTap: () => widget.onGoToTab?.call(1),
      border: SC.green,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LivePulse(size: 8),
              const SizedBox(width: 6),
              Text(t('SERVICE RUNNING'),
                  style: const TextStyle(
                      color: SC.green,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              InitialsAvatar(name: b.customerName, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.customerName,
                        style: ST.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(t('{service} · started {time}', {
                      'service': b.serviceType.label,
                      'time': _hhmm(b.serviceStartedAt),
                    }),
                        style: ST.small),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: SC.inkFaint),
            ],
          ),
        ],
      ),
    );
  }

  String _hhmm(DateTime? d) => d == null
      ? '—'
      : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Widget _todayCard() {
    final today = _today;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          t("Today's work"),
          trailing: today.isEmpty
              ? null
              : TextButton(
                  onPressed: () => widget.onGoToTab?.call(1),
                  child: Text(t('View all')),
                ),
        ),
        if (today.isEmpty)
          EmptyState(
            compact: true,
            icon: Icons.event_available_rounded,
            title: t('Nothing scheduled today'),
            message: t('Requests near you appear under Jobs. Go on duty above so families can find you.'),
          )
        else
          for (var i = 0; i < today.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == today.length - 1 ? 0 : 10),
              child: _jobRow(today[i]),
            ),
      ],
    );
  }

  Widget _jobRow(ProviderBooking b) {
    return SCard(
      padding: const EdgeInsets.all(14),
      onTap: () => widget.onGoToTab?.call(1),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: SC.blueTint,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.schedule_rounded, color: SC.blueBright, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b.customerName, style: ST.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text('${b.serviceType.label} · ${b.timeFrom} – ${b.timeTo}', style: ST.small),
              ],
            ),
          ),
          StatusChip(b.status.label, tone: _tone(b.status), dense: true),
        ],
      ),
    );
  }

  ChipTone _tone(BookingStatus s) => switch (s) {
        BookingStatus.completed => ChipTone.good,
        BookingStatus.cancelled => ChipTone.bad,
        BookingStatus.inProgress => ChipTone.info,
        BookingStatus.accepted => ChipTone.good,
        BookingStatus.requested => ChipTone.warn,
      };

  Widget _earnings(DashboardStats stats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          t('Earnings'),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: SC.surface,
              borderRadius: BorderRadius.circular(SC.rPill),
              border: Border.all(color: SC.hairline),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: period,
                isDense: true,
                borderRadius: BorderRadius.circular(12),
                style: ST.bodyStrong.copyWith(fontSize: 13),
                icon: const Icon(Icons.expand_more_rounded, size: 18, color: SC.inkFaint),
                items: const ['Today', 'Week', 'Month', 'Quarter', 'Annual']
                    .map((e) => DropdownMenuItem(value: e, child: Text('  ${t(e)}')))
                    .toList(),
                onChanged: (v) => setState(() => period = v!),
              ),
            ),
          ),
        ),
        DarkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(period.toUpperCase(),
                  style: const TextStyle(
                      color: SC.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
              const SizedBox(height: 10),
              AnimatedFigure(
                value: stats.revenue,
                prefix: '₹',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 16),
              const DashedDivider(),
              const SizedBox(height: 14),
              Row(
                children: [
                  _miniStat('Visits', '${stats.appointments}'),
                  _miniStat('Hours', stats.hours.toStringAsFixed(1)),
                  _miniStat('Pending', '₹${stats.pending.toStringAsFixed(0)}'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniStat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11.5, height: 1.3)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  /// What the earnings card becomes for somebody who gives their time free.
  ///
  /// Same shape and the same period control, so the dashboard does not change
  /// layout depending on who is holding it -- but the headline is hours given
  /// rather than money, and there is no pending figure, because nothing is
  /// owed. It follows the Impact screen's rule: hours and people, never a
  /// score, because a score turns a gift into a transaction.
  Widget _contribution(DashboardStats stats) {
    final people = Backend.instance.myBookings
        .where((b) => b.status == BookingStatus.completed)
        .map((b) => b.customerId)
        .toSet()
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          t('Your contribution'),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: SC.surface,
              borderRadius: BorderRadius.circular(SC.rPill),
              border: Border.all(color: SC.hairline),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: period,
                isDense: true,
                borderRadius: BorderRadius.circular(12),
                style: ST.bodyStrong.copyWith(fontSize: 13),
                icon: const Icon(Icons.expand_more_rounded, size: 18, color: SC.inkFaint),
                items: const ['Today', 'Week', 'Month', 'Quarter', 'Annual']
                    .map((e) => DropdownMenuItem(value: e, child: Text('  ${t(e)}')))
                    .toList(),
                onChanged: (v) => setState(() => period = v!),
              ),
            ),
          ),
        ),
        DarkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(period.toUpperCase(),
                  style: const TextStyle(
                      color: SC.green,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
              const SizedBox(height: 10),
              AnimatedFigure(
                value: stats.hours,
                suffix: ' hrs',
                decimals: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(t('given, and nothing billed'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
              const SizedBox(height: 14),
              const DashedDivider(),
              const SizedBox(height: 14),
              Row(
                children: [
                  _miniStat('Visits', '${stats.appointments}'),
                  _miniStat('People', '$people'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Volunteers are not paid, so an earnings figure of zero would read as a
  /// problem rather than a choice. This says what they are building instead.
  Widget _volunteerCard() {
    return SCard(
      onTap: () => widget.onGoToTab?.call(3),
      border: SC.green,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: SC.greenTint,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.volunteer_activism_rounded, color: SC.green, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('You give your time free'), style: ST.h3),
                const SizedBox(height: 3),
                Text(t('Thank you. Nothing is billed for your visits.'),
                    style: ST.small),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: SC.inkFaint),
        ],
      ),
    );
  }

  Widget _orgCard(ProviderProfile p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(t('Organisation')),
        SCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: p.allocateViaOrg,
                activeThumbColor: SC.blueBright,
                title: Text(t('Allocate via organisation'), style: ST.bodyStrong),
                subtitle: Text(
                    t('When on, families see the organisation rather than individual staff'),
                    style: ST.small),
                onChanged: (v) async {
                  await Backend.instance.toggleAllocateViaOrg(v);
                  if (mounted) setState(() {});
                },
              ),
              const Divider(height: 22),
              _orgLink(Icons.groups_rounded, 'Staff', '${p.employees.length}',
                  () => push(context, const EmployeesScreen())),
              const SizedBox(height: 10),
              _orgLink(Icons.bar_chart_rounded, 'Utilisation report', null,
                  () => push(context, const UtilizationScreen())),
              const SizedBox(height: 10),
              _orgLink(Icons.calendar_view_week_rounded, 'Schedule overview', null,
                  () => push(context, const ScheduleOverviewScreen())),
            ],
          ),
        ),
      ],
    );
  }

  Widget _orgLink(IconData icon, String label, String? count, VoidCallback onTap) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: SC.sunkTint,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 19, color: SC.blueBright),
            const SizedBox(width: 11),
            Expanded(child: Text(label, style: ST.bodyStrong)),
            if (count != null) ...[
              StatusChip(count, tone: ChipTone.info, dense: true),
              const SizedBox(width: 8),
            ],
            const Icon(Icons.chevron_right_rounded, size: 19, color: SC.inkFaint),
          ],
        ),
      ),
    );
  }

  Widget _approvalCard(ProviderProfile p) {
    final a = approvalPresentation(p.approvalStatus);
    final (tone, title, body) = (a.tone, a.label, a.note);

    return SCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: SC.sunkTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.verified_user_rounded, size: 20, color: SC.inkSoft),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(title, style: ST.h3)),
                    StatusChip(title.toUpperCase(), tone: tone, dense: true),
                  ],
                ),
                const SizedBox(height: 6),
                Text(body, style: ST.small),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
