// The booking, from request to rating.
//
// Four screens: waiting for somebody to accept, confirming once they have,
// tracking the visit, and rating it afterwards. Rebuilt on the design system;
// every backend call, timer and state transition is unchanged.
//
// The request fans out to every matching provider and whoever accepts first
// gets it, so the waiting screen deliberately talks about the provider that
// was *requested* rather than a confirmed one.

import 'dart:async';

import 'package:flutter/material.dart';

import '../backend.dart';
import '../models.dart';
import '../theme/sathiyaa_theme.dart';
import '../widgets/sathiyaa_ui.dart';
import '../widgets/motion.dart';
import '../widgets/osm_map.dart';
import 'home_shell.dart';
import 'payment_screen.dart';
import '../utils/dates.dart';
import '../i18n/l10n.dart';

/// The five stages of a booking, as the person who made it experiences them.
///
/// Every one is a status the server actually sets — searching, pendingPayment,
/// confirmed, inProgress, completed — rather than a stage invented to make a
/// nicer picture. That matters: the stepper exists to answer "what happens
/// next", and it can only answer honestly if it is reading the same thing the
/// rest of the screen is.
const _journeySteps = <JourneyStep>[
  JourneyStep('Requested', Icons.send_rounded),
  JourneyStep('Accepted', Icons.how_to_reg_rounded),
  JourneyStep('Paid', Icons.payments_rounded),
  JourneyStep('Visit', Icons.home_rounded),
  JourneyStep('Rated', Icons.star_rounded),
];

/// Where a booking sits on that journey, zero-based.
int _journeyIndex(BookingStatus status) => switch (status) {
      BookingStatus.searching => 0,
      BookingStatus.pendingPayment => 1,
      BookingStatus.confirmed => 2,
      BookingStatus.providerOnWay || BookingStatus.inProgress => 3,
      BookingStatus.completed => 4,
      // A cancelled booking has left the journey rather than reached the end of
      // it. Callers do not draw the stepper for one; this is only here so the
      // switch stays exhaustive.
      BookingStatus.cancelled => 0,
    };

/// The stepper for a booking, or nothing at all if it was cancelled.
Widget _journeyFor(Booking b) => b.status == BookingStatus.cancelled
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: JourneyStepper(steps: _journeySteps, current: _journeyIndex(b.status)),
      );

// ---------------------------------------------------------------------------
// 1 · REQUEST SENT, WAITING — THEN CONFIRM
// ---------------------------------------------------------------------------

class BookingConfirmScreen extends StatefulWidget {
  /// The carers being asked. One is the ordinary case — you opened somebody's
  /// profile and asked them. Several comes from picking a shortlist in search,
  /// and then the first to accept takes the visit.
  final List<String> providerIds;
  final BookingCriteria criteria;

  const BookingConfirmScreen({
    super.key,
    required this.providerIds,
    required this.criteria,
  });

  @override
  State<BookingConfirmScreen> createState() => _BookingConfirmScreenState();
}

class _BookingConfirmScreenState extends State<BookingConfirmScreen> {
  Booking? booking;
  Provider? provider;
  bool paying = false;
  String? error;
  Timer? ticker;
  Duration remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _create();
  }

  Future<void> _create() async {
    try {
      // Only meaningful when one carer was asked. With a shortlist there is no
      // "the provider" until somebody accepts, and the summary card below says
      // so rather than picking the first name off the list.
      if (widget.providerIds.length == 1) {
        final only = widget.providerIds.first;
        provider = Backend.instance.cachedProvider(only) ??
            await Backend.instance.providerById(only);
      }
      final b = await Backend.instance.createBooking(
        providerIds: widget.providerIds,
        type: widget.criteria.serviceType,
        start: widget.criteria.startDate,
        end: widget.criteria.endDate,
        timeFrom: widget.criteria.timeFrom,
        timeTo: widget.criteria.timeTo,
        forMember: widget.criteria.forMember,
      );
      if (!mounted) return;
      setState(() => booking = b);

      // One timer does both jobs: while the request is out to providers it
      // polls for an acceptance, and once one lands it counts down the
      // payment window.
      ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  int _sinceLastPoll = 0;

  Future<void> _tick() async {
    if (!mounted) return;
    final b = booking;
    if (b == null) return;

    if (b.status == BookingStatus.searching) {
      // Poll every three seconds rather than every tick — the customer is
      // waiting on another human, not on the network.
      _sinceLastPoll += 1;
      if (_sinceLastPoll >= 3) {
        _sinceLastPoll = 0;
        try {
          final fresh = await Backend.instance.refreshBooking(b.id);
          if (mounted) setState(() => booking = fresh);
        } catch (_) {
          // A blip while polling shouldn't tear the screen down.
        }
      }
      return;
    }

    final deadline = booking?.paymentDeadline;
    if (deadline == null) return;
    final left = deadline.difference(DateTime.now());
    setState(() => remaining = left.isNegative ? Duration.zero : left);
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  /// Hands off to the payment screen, which carries the method chooser, the
  /// bill breakdown and the confirmation. It calls payBookingCharge itself and
  /// returns true once the booking is paid; this screen only has to react.
  Future<void> pay() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => error = null);

    final paid = await navigator.push<bool>(
      SathiyaaPageRoute<bool>(page: PaymentScreen(booking: booking!), fromBottom: true),
    );
    if (!mounted || paid != true) return;

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeShell()),
      (r) => false,
    );
    messenger.showSnackBar(
      SnackBar(content: Text(t('Booking confirmed. Track it from Bookings.'))),
    );
  }

  Future<void> _cancelSearch() async {
    final navigator = Navigator.of(context);
    try {
      await Backend.instance.cancelBooking(booking!.id);
    } catch (_) {
      // Nothing was paid, so a failure here is not worth blocking the exit.
    }
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = provider;
    final b = booking;
    final waiting = b != null && b.status == BookingStatus.searching;
    final expired =
        remaining == Duration.zero && b?.status == BookingStatus.pendingPayment;

    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          BrandHeader(
            curved: false,
            child: BrandBar(
              title: waiting ? 'Looking for someone' : 'Confirm your booking',
              subtitle: waiting
                  ? 'Nothing is charged while you wait'
                  : 'One step left',
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
          Expanded(child: _body(p, b, waiting, expired)),
        ],
      ),
    );
  }

  Widget _body(Provider? p, Booking? b, bool waiting, bool expired) {
    if (error != null && b == null) {
      return ListView(
        padding: const EdgeInsets.all(SC.gutter),
        children: [
          InlineError(message: error!),
          const SizedBox(height: 14),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('Go back')),
            ),
          ),
        ],
      );
    }

    if (b == null) {
      return const Padding(
        padding: EdgeInsets.all(SC.gutter),
        child: SkeletonList(count: 2),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 28),
      children: staggered([
        if (error != null) ...[
          InlineError(message: error!),
          const SizedBox(height: 14),
        ],
        _journeyFor(b),
        if (waiting) _waitingCard(b) else _acceptedCard(b, expired),
        const SizedBox(height: 14),
        _summaryCard(p),
        const SizedBox(height: 22),
        if (waiting)
          OutlinedButton.icon(
            onPressed: _cancelSearch,
            icon: const Icon(Icons.close_rounded, size: 18),
            label: Text(t('Cancel this request')),
            style: OutlinedButton.styleFrom(foregroundColor: SC.redDeep),
          )
        else
          GradientButton(
            label: t('Review and pay'),
            icon: Icons.arrow_forward_rounded,
            busy: paying,
            onPressed: expired ? null : pay,
          ),
      ]),
    );
  }

  /// "Asked 3 carers you picked" reads differently from "asked 3 carers near
  /// you", and they are different promises: one is a shortlist the customer
  /// made, the other is whoever happened to be in range.
  String _askedHeadline(Booking b) {
    final n = b.providersNotified;
    if (n == null) return t('Waiting for someone to accept');
    if (b.chosenByCustomer) {
      return n == 1
          ? t('Asked the 1 carer you picked')
          : t('Asked the {count} carers you picked', {'count': n});
    }
    return n == 1
        ? t('Asked 1 carer near you')
        : t('Asked {count} carers near you', {'count': n});
  }

  /// "Lakshmi, Meera and Anjali" — with a tail once the list gets long enough
  /// that reading it all stops being useful.
  String _nameList(List<String> names) {
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names[0]} and ${names[1]}';
    if (names.length <= 4) {
      return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
    }
    return '${names.take(3).join(', ')} and ${names.length - 3} others';
  }

  Widget _waitingCard(Booking b) {
    return DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LivePulse(color: Color(0xFF6BE39A), size: 8),
              const SizedBox(width: 6),
              Text(t('REQUEST SENT'),
                  style: const TextStyle(
                      color: Color(0xFF6BE39A),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _askedHeadline(b),
            style: const TextStyle(
                color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800),
          ),
          // Naming them is the point of letting somebody choose. "Asked 3
          // carers" is a number; "Lakshmi, Meera and Anjali" is three people
          // you picked and can now wait for.
          if (b.askedNames.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _nameList(b.askedNames),
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, height: 1.45),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            t('The first to accept gets the visit. You are asked to pay only then — nothing is charged while you wait, and you can cancel free.'),
            style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.5),
          ),
          // Somebody who picked four carers and sees three asked would
          // otherwise sit waiting on a first choice who was never contacted.
          if (b.unavailableCount > 0) ...[
            const SizedBox(height: 10),
            Text(
              b.unavailableCount == 1
                  ? 'One of the carers you picked was already busy at that time, so they were not asked.'
                  : '${b.unavailableCount} of the carers you picked were already busy at that time, so they were not asked.',
              style: const TextStyle(color: Color(0xFFF2D49B), fontSize: 12.5, height: 1.45),
            ),
          ],
          if (Backend.isLive) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                children: [
                  const Icon(Icons.phone_android_rounded, size: 17, color: Colors.white70),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      t('Testing? Open the Sathiyaa Provider app and accept it there.'),
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _acceptedCard(Booking b, bool expired) {
    final mm = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    final urgent = remaining.inMinutes < 3;

    return SCard(
      border: expired ? SC.red : SC.green,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: expired ? const Color(0xFFFCE9EA) : SC.greenTint,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  expired ? Icons.timer_off_rounded : Icons.check_circle_rounded,
                  color: expired ? SC.redDeep : SC.green,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  expired ? 'The slot was released' : 'Somebody accepted',
                  style: ST.h3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (expired)
            Text(
              t('Nobody was charged. Search again and send a fresh request.'),
              style: ST.body,
            )
          else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: urgent ? const Color(0xFFFCE9EA) : SC.sunkTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text('$mm:$ss',
                      style: ST.figure.copyWith(
                        fontSize: 32,
                        color: urgent ? SC.redDeep : SC.ink,
                      )),
                  const SizedBox(height: 3),
                  Text(t('left to confirm'),
                      style: ST.small.copyWith(
                          color: urgent ? SC.redDeep : SC.inkFaint)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Confirming holds the slot. The booking fee is ₹'
              '${b.bookingCharge.toStringAsFixed(0)} — nothing is actually charged, '
              'no payment provider is connected yet.',
              style: ST.small.copyWith(height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryCard(Provider? p) {
    final c = widget.criteria;
    final rate = p?.noFees == true ? null : p?.hourlyRate;
    final estimate = rate == null ? 0.0 : rate * c.totalHours;

    return SCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(t('What you asked for')),
          // With a shortlist there is no single carer to name here yet, and
          // naming the first of them would be inventing an answer nobody has
          // given. The waiting card above lists who was actually asked.
          _row(
            Icons.person_rounded,
            widget.providerIds.length > 1 ? 'Asked' : 'Requested',
            widget.providerIds.length > 1
                ? '${widget.providerIds.length} carers — first to accept'
                : (p?.name ?? booking?.providerName ?? 'a carer'),
          ),
          _row(Icons.medical_services_rounded, 'Care', c.serviceType.label),
          _row(Icons.calendar_today_rounded, 'Dates',
              '${c.dateLabel} · ${c.days} day${c.days == 1 ? '' : 's'}'),
          _row(Icons.schedule_rounded, 'Hours',
              '${c.timeFrom} – ${c.timeTo} · ${c.totalHours.toStringAsFixed(1)}h total'),
          _row(Icons.place_rounded, 'At', c.locationLabel),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  rate == null
                      ? 'Given free'
                      : 'About ₹${estimate.toStringAsFixed(0)} for the care',
                  style: ST.h3.copyWith(color: rate == null ? SC.green : SC.ink),
                ),
              ),
              if (rate != null)
                Text('₹${rate.toStringAsFixed(0)}/hr', style: ST.small),
            ],
          ),
          if (rate != null) ...[
            const SizedBox(height: 4),
            Text(t('Billed on the hours actually worked, settled after the visit.'),
                style: ST.small),
          ],
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: SC.inkFaint),
          const SizedBox(width: 10),
          SizedBox(width: 74, child: Text(label, style: ST.small)),
          Expanded(child: Text(value, style: ST.bodyStrong.copyWith(fontSize: 13.5))),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2 · TRACKING THE VISIT
// ---------------------------------------------------------------------------

class TrackServiceScreen extends StatefulWidget {
  final Booking booking;
  const TrackServiceScreen({super.key, required this.booking});

  @override
  State<TrackServiceScreen> createState() => _TrackServiceScreenState();
}

class _TrackServiceScreenState extends State<TrackServiceScreen> {
  Timer? poll;
  late Booking booking = widget.booking;
  String? notice;

  @override
  void initState() {
    super.initState();
    poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final fresh = await Backend.instance.refreshBooking(booking.id);
      if (mounted) setState(() => booking = fresh);
    } catch (_) {
      // A transient failure while polling shouldn't blank the screen.
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _refresh();
    } catch (e) {
      if (mounted) {
        setState(() => notice = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final providerName = b.providerName ??
        Backend.instance.cachedProvider(b.providerId)?.name ??
        'Your carer';
    final canSimulate = Backend.instance.supportsSimulation;
    final started = b.serviceStartedAt;
    final here = b.status == BookingStatus.inProgress;
    final address = Backend.instance.primaryAddress();

    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          BrandHeader(
            curved: false,
            child: BrandBar(
              title: here ? 'Visit in progress' : 'On the way',
              subtitle: t('Checked every 5 seconds'),
              onBack: () => Navigator.of(context).pop(),
              actions: [
                HeaderIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: t('Check again'),
                  onTap: _refresh,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 28),
              children: staggered([
                _journeyFor(b),
                _statusCard(providerName, here, started),
                if (b.status == BookingStatus.inProgress && b.otp != null) ...[
                  const SizedBox(height: 14),
                  _otpCard(b.otp!),
                ],
                if (notice != null) ...[
                  const SizedBox(height: 14),
                  InlineError(message: notice!),
                ],
                if (address != null) ...[
                  const SizedBox(height: 22),
                  SectionLabel(t('Where they are going')),
                  OsmMap(
                    lat: address.lat,
                    lng: address.lng,
                    label: address.label,
                    height: 170,
                  ),
                ],
                if (canSimulate) ...[
                  const SizedBox(height: 22),
                  _simulationBlock(b),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(String providerName, bool here, DateTime? started) {
    return DarkCard(
      gradient: here
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF14503C), Color(0xFF2E9E5B)],
            )
          : SC.brandGradientDeep,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LivePulse(color: here ? Colors.white : const Color(0xFF6BE39A), size: 8),
              const SizedBox(width: 6),
              Text(here ? 'WITH YOU NOW' : 'ON THE WAY',
                  style: TextStyle(
                      color: here ? Colors.white : const Color(0xFF6BE39A),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 12),
          Text(providerName,
              style: const TextStyle(
                  color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            started != null
                ? 'Started at ${started.hour.toString().padLeft(2, '0')}:'
                    '${started.minute.toString().padLeft(2, '0')}.'
                : 'They will ask you for a code when they arrive.',
            style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _otpCard(String otp) {
    return SCard(
      border: SC.gold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(t('Read this out')),
          Text(t('Give these six digits to your carer so they can start.'),
              style: ST.body),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: SC.goldTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                otp,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 10,
                  color: Color(0xFF8A6317),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Demo shortcuts. On a live server the provider app does these — the
  /// buttons only exist where the backend says simulation is supported.
  Widget _simulationBlock(Booking b) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(t('Demo shortcuts')),
        Text(t('On a real server the carer does these from their own app.'),
            style: ST.small),
        const SizedBox(height: 12),
        if (b.status == BookingStatus.confirmed)
          OutlinedButton.icon(
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: Text(t('Simulate: carer starts the visit')),
            onPressed: () => _run(() => Backend.instance.startServiceSimulation(b.id)),
          ),
        if (b.status == BookingStatus.inProgress)
          OutlinedButton.icon(
            icon: const Icon(Icons.stop_rounded, size: 18),
            label: Text(t('Simulate: visit finished')),
            onPressed: () async {
              final navigator = Navigator.of(context);
              await Backend.instance.completeService(b.id);
              final fresh = await Backend.instance.refreshBooking(b.id);
              if (!mounted) return;
              navigator.pushReplacement(
                MaterialPageRoute(builder: (_) => ServiceSummaryScreen(booking: fresh)),
              );
            },
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 3 · AFTERWARDS
// ---------------------------------------------------------------------------

class ServiceSummaryScreen extends StatelessWidget {
  final Booking booking;
  const ServiceSummaryScreen({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final providerName = b.providerName ??
        Backend.instance.cachedProvider(b.providerId)?.name ??
        'your carer';

    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          BrandHeader(
            curved: false,
            child: BrandBar(
              title: t('Visit finished'),
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(SC.gutter, 26, SC.gutter, 28),
              children: staggered([
                const Center(child: SuccessCheck()),
                const SizedBox(height: 20),
                Text(t('Your visit with {name} is done.', {'name': providerName}),
                    textAlign: TextAlign.center, style: ST.h1),
                const SizedBox(height: 24),
                SCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionLabel(t('Summary')),
                      _row('Dates',
                          '${prettyDay(b.startDate)} – ${prettyDate(b.endDate)}'),
                      _row('Time', '${b.timeFrom} – ${b.timeTo}'),
                      _row('Hours worked', b.totalHours?.toStringAsFixed(1) ?? '—'),
                      const SizedBox(height: 10),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: Text(t('Total'), style: ST.h3)),
                          Text('₹${b.totalAmount?.toStringAsFixed(0) ?? '0'}',
                              style: ST.figure.copyWith(fontSize: 24)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (b.customerRating == null) ...[
                  const SizedBox(height: 22),
                  GradientButton(
                    label: t('Rate your carer'),
                    icon: Icons.star_rounded,
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => RateProviderScreen(booking: b)),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Expanded(child: Text(label, style: ST.body)),
          Text(value, style: ST.bodyStrong),
        ],
      ),
    );
  }
}

class RateProviderScreen extends StatefulWidget {
  final Booking booking;
  const RateProviderScreen({super.key, required this.booking});

  @override
  State<RateProviderScreen> createState() => _RateProviderScreenState();
}

class _RateProviderScreenState extends State<RateProviderScreen> {
  double rating = 5;
  final commentCtrl = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    commentCtrl.dispose();
    super.dispose();
  }

  static const _words = {
    1: 'Not good',
    2: 'Could be better',
    3: 'Fine',
    4: 'Good',
    5: 'Excellent',
  };

  @override
  Widget build(BuildContext context) {
    final who = widget.booking.providerName ??
        Backend.instance.cachedProvider(widget.booking.providerId)?.name ??
        'your carer';

    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          BrandHeader(
            curved: false,
            child: BrandBar(
              title: t('How was it?'),
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(SC.gutter, 26, SC.gutter, 28),
              children: staggered([
                _journeyFor(widget.booking),
                Center(child: InitialsAvatar(name: who, size: 78, radius: 24)),
                const SizedBox(height: 16),
                Text(who, textAlign: TextAlign.center, style: ST.h1),
                const SizedBox(height: 6),
                Text(
                  t('Your rating helps the next family choose.'),
                  textAlign: TextAlign.center,
                  style: ST.body,
                ),
                const SizedBox(height: 24),
                StarPicker(
                  value: rating.round(),
                  onChanged: (v) => setState(() => rating = v.toDouble()),
                  size: 44,
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(_words[rating.round()] ?? '',
                      style: ST.h3.copyWith(color: SC.gold)),
                ),
                const SizedBox(height: 26),
                FieldLabel(t('Anything you want to add')),
                TextField(
                  controller: commentCtrl,
                  maxLines: 4,
                  decoration: InputDecoration(hintText: t('Optional')),
                ),
                if (error != null) ...[
                  const SizedBox(height: 16),
                  InlineError(message: error!),
                ],
                const SizedBox(height: 24),
                GradientButton(
                  label: t('Send rating'),
                  icon: Icons.send_rounded,
                  busy: busy,
                  onPressed: busy ? null : _submit,
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final navigator = Navigator.of(context);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await Backend.instance
          .rateProvider(widget.booking.id, rating, commentCtrl.text.trim());
      if (!mounted) return;
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (r) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }
}
