// One job, start to finish.
//
// This is the screen a carer actually works from, so it is laid out as the
// sequence it is: accept, travel, arrive and photograph, OTP, work, end,
// take payment, rate. A stepper at the top says where in that they are, and
// only the step they are on is expanded — the rest would be noise on a phone
// held in one hand at somebody's door.
//
// Every handler and every backend call here is unchanged from the version
// that was working; what changed is the chrome around them.

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../backend.dart';
import '../mock_data.dart';
import '../theme/sathiyaa_theme.dart';
import '../widgets/sathiyaa_ui.dart';
import '../widgets/motion.dart';
import '../widgets/common.dart' show DirectionsPanel;
import 'messages_screen.dart';
import '../i18n/l10n.dart';

class BookingDetailScreen extends StatefulWidget {
  final String bookingId;
  const BookingDetailScreen({super.key, required this.bookingId});

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  bool busy = false;
  final otpCtrl = TextEditingController();
  final amountCtrl = TextEditingController();

  ProviderBooking get b =>
      Backend.instance.myBookings.firstWhere((x) => x.id == widget.bookingId);

  @override
  void dispose() {
    otpCtrl.dispose();
    amountCtrl.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() f) async {
    setState(() => busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Which of the six steps the job is on. Drives the stepper and decides
  /// which block is open.
  int get _step {
    final booking = b;
    if (booking.status == BookingStatus.requested) return 0;
    if (booking.status == BookingStatus.accepted) {
      if (booking.faceVerifiedAt == null) return 1;
      return 2;
    }
    if (booking.status == BookingStatus.inProgress) return 3;
    if (booking.status == BookingStatus.completed) {
      return booking.paymentStatus == PaymentStatus.paid ? 5 : 4;
    }
    return 5;
  }

  static const _steps = [
    JourneyStep('Accept', Icons.check_rounded),
    JourneyStep('Arrive', Icons.photo_camera_rounded),
    JourneyStep('OTP', Icons.pin_rounded),
    JourneyStep('Working', Icons.timer_rounded),
    JourneyStep('Payment', Icons.payments_rounded),
    JourneyStep('Done', Icons.verified_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final booking = b;
    final isOrg = Backend.instance.currentProvider!.kind == ProviderKind.organization;
    final cancelled = booking.status == BookingStatus.cancelled;

    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          BrandHeader(
            curved: false,
            child: BrandBar(
              title: booking.customerName,
              subtitle: '${booking.serviceType.label} · ${booking.id}',
              onBack: () => Navigator.of(context).pop(),
              actions: [
                // Only once the job is theirs. Before that one request has
                // gone to several strangers, and there is nobody to talk to.
                if (booking.status != BookingStatus.requested)
                  HeaderIconButton(
                    icon: Icons.chat_bubble_outline_rounded,
                    tooltip: t('Messages'),
                    badge: booking.unreadMessages > 0,
                    onTap: () async {
                      await push(context, MessagesScreen(booking: booking));
                      // Opening the thread marks it read, so the dot has to be
                      // refreshed on the way back or it keeps saying otherwise.
                      if (mounted) setState(() {});
                    },
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 32),
              children: [
                if (!cancelled)
                  FadeInUp(
                    index: 0,
                    child: JourneyStepper(
                      title: t('This visit'),
                      steps: _steps,
                      current: _step,
                    ),
                  ),
                const SizedBox(height: 14),
                FadeInUp(index: 1, child: _whoAndWhere(booking)),
                const SizedBox(height: 14),
                if (booking.status == BookingStatus.requested)
                  FadeInUp(index: 2, child: _acceptBlock(booking)),
                if (booking.status == BookingStatus.accepted) ...[
                  if (isOrg) ...[
                    FadeInUp(index: 2, child: _orgBlock(booking)),
                    const SizedBox(height: 14),
                  ],
                  FadeInUp(index: 3, child: _onTheWayBlock(booking)),
                  const SizedBox(height: 14),
                  FadeInUp(index: 4, child: _arrivalBlock(booking)),
                  if (booking.faceVerifiedAt != null) ...[
                    const SizedBox(height: 14),
                    FadeInUp(index: 5, child: _otpBlock(booking)),
                  ],
                ],
                if (booking.status == BookingStatus.inProgress)
                  FadeInUp(index: 2, child: _workingBlock(booking)),
                if (booking.status == BookingStatus.completed) ...[
                  FadeInUp(index: 2, child: _paymentBlock(booking)),
                  if (booking.customerRatingByProvider == null) ...[
                    const SizedBox(height: 14),
                    FadeInUp(index: 3, child: _rateBlock(booking)),
                  ],
                ],
                if (cancelled)
                  FadeInUp(
                    index: 2,
                    child: EmptyState(
                      icon: Icons.event_busy_rounded,
                      title: t('This booking was cancelled'),
                      message: t('Nothing more to do here. It stays in your history.'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- the customer ---------------------------------------------------

  Widget _whoAndWhere(ProviderBooking booking) {
    final hasAddress = booking.customerAddress.isNotEmpty;
    final hasPhone = booking.customerMobile != null && booking.customerMobile!.isNotEmpty;
    final open = booking.status != BookingStatus.requested;

    return SCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 15, 15, 13),
            child: Row(
              children: [
                InitialsAvatar(name: booking.customerName, size: 52),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(booking.visitingName,
                          style: ST.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Text('${_date(booking.startDate)} · ${booking.timeFrom} – ${booking.timeTo}',
                          style: ST.small),
                    ],
                  ),
                ),
                StatusChip(booking.status.label, tone: _tone(booking.status), dense: true),
              ],
            ),
          ),
          // Booked by one person, for another. Said plainly and near the top,
          // because knocking and asking for the wrong name is the mistake this
          // whole field exists to prevent.
          if (booking.isForSomeoneElse)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(15, 0, 15, 13),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SC.amberTint,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF0DCBC)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 17, color: Color(0xFFA9670F)),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'You are visiting ${booking.forName}'
                          '${booking.forRelationship == null ? '' : ' (${booking.forRelationship})'}'
                          '${_ageSuffix(booking.forDateOfBirth)}.',
                          style: ST.bodyStrong.copyWith(
                              fontSize: 13.5, color: const Color(0xFF7A5612)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 26),
                    child: Text(
                      'Booked by ${booking.customerName}, who is the one paying '
                      'and getting the updates.',
                      style: ST.small.copyWith(
                          fontSize: 12, height: 1.4, color: const Color(0xFF8A5510)),
                    ),
                  ),
                  if (booking.forNotes != null && booking.forNotes!.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 26),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.push_pin_rounded,
                              size: 13, color: Color(0xFFA9670F)),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(booking.forNotes!,
                                style: ST.small.copyWith(
                                    fontSize: 12,
                                    height: 1.4,
                                    color: const Color(0xFF7A5612),
                                    fontStyle: FontStyle.italic)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (!open)
            // Before the job is theirs, one request has gone to several
            // strangers — so the server sends the area, not the doorstep.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(15, 11, 15, 12),
              decoration: const BoxDecoration(
                color: SC.sunkTint,
                border: Border(top: BorderSide(color: SC.hairline)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 15, color: SC.inkFaint),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasAddress
                          ? '${booking.customerAddress} — full address and phone number once you accept'
                          : 'Full address and phone number once you accept',
                      style: ST.small,
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.fromLTRB(15, 12, 15, 13),
              decoration: const BoxDecoration(
                color: SC.sunkTint,
                border: Border(top: BorderSide(color: SC.hairline)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasAddress)
                    _detail(Icons.place_rounded, booking.customerAddress),
                  if (hasPhone) ...[
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        const Icon(Icons.phone_rounded, size: 15, color: SC.inkFaint),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(booking.customerMobile!, style: ST.bodyStrong),
                        ),
                        TextButton.icon(
                          onPressed: () => _callCustomer(booking),
                          icon: const Icon(Icons.call_rounded, size: 16),
                          label: Text(t('Call')),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            minimumSize: Size.zero,
                          ),
                        ),
                      ],
                    ),
                    if (booking.customerCommMode != null &&
                        booking.customerCommMode!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 24, top: 2),
                        child: Text(
                          'Prefers ${booking.customerCommMode}'
                          '${booking.customerCommTimeframe == null ? '' : ' between ${booking.customerCommTimeframe}'}',
                          style: ST.small.copyWith(fontSize: 11.5),
                        ),
                      ),
                  ],
                  if (booking.customerBloodGroup != null &&
                      booking.customerBloodGroup!.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    _detail(Icons.bloodtype_rounded,
                        'Blood group ${booking.customerBloodGroup}'),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _detail(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: SC.inkFaint),
        const SizedBox(width: 9),
        Expanded(child: Text(text, style: ST.body.copyWith(fontSize: 13.5))),
      ],
    );
  }

  ChipTone _tone(BookingStatus s) => switch (s) {
        BookingStatus.completed => ChipTone.good,
        BookingStatus.cancelled => ChipTone.bad,
        BookingStatus.inProgress => ChipTone.info,
        BookingStatus.accepted => ChipTone.good,
        BookingStatus.requested => ChipTone.warn,
      };

  // ---- step blocks ----------------------------------------------------

  Widget _acceptBlock(ProviderBooking booking) {
    return SCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(t('Do you want this visit?')),
          Text(
            t('This request went to several carers nearby. The first to accept gets it.'),
            style: ST.body,
          ),
          const SizedBox(height: 16),
          GradientButton(
            label: t('Accept this visit'),
            icon: Icons.check_rounded,
            busy: busy,
            onPressed: busy
                ? null
                : () async {
                    await run(() => Backend.instance.acceptBooking(booking.id));
                    if (mounted) setState(() {});
                  },
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: busy
                ? null
                : () async {
                    final navigator = Navigator.of(context);
                    await run(() => Backend.instance.rejectBooking(booking.id));
                    if (mounted) navigator.pop();
                  },
            child: Text(t('Not this one')),
          ),
        ],
      ),
    );
  }

  Widget _orgBlock(ProviderBooking booking) {
    return SCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(t('Organisation')),
          OutlinedButton.icon(
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: Text(t('Transfer to another member of staff')),
            onPressed: busy ? null : () => _transfer(booking),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.cancel_outlined, size: 18),
            label: Text(t('Cancel this booking')),
            style: OutlinedButton.styleFrom(foregroundColor: SC.redDeep),
            onPressed: busy
                ? null
                : () async {
                    final navigator = Navigator.of(context);
                    await run(() => Backend.instance.orgCancel(booking.id));
                    if (mounted) navigator.pop();
                  },
          ),
        ],
      ),
    );
  }

  Future<void> _transfer(ProviderBooking booking) async {
    final emp = Backend.instance.currentProvider!.employees;
    final chosen = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        backgroundColor: SC.surface,
        title: Text(t('Transfer to'), style: ST.h2),
        children: emp
            .map((e) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, e.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        InitialsAvatar(name: e.name, size: 36),
                        const SizedBox(width: 12),
                        Expanded(child: Text(e.name, style: ST.bodyStrong)),
                      ],
                    ),
                  ),
                ))
            .toList(),
      ),
    );
    if (chosen == null) return;
    await run(() => Backend.instance.transferBooking(booking.id, chosen));
    if (mounted) setState(() {});
  }

  Widget _onTheWayBlock(ProviderBooking booking) {
    return SCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(t('On your way')),
          OutlinedButton.icon(
            icon: const Icon(Icons.directions_rounded, size: 18),
            label: Text(t('Show directions')),
            onPressed: () => _showDirections(booking),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.schedule_rounded, size: 18),
            label: Text(booking.runningLateSent
                ? 'Running late — ${booking.runningLateEta} sent'
                : 'Tell them you are running late'),
            onPressed: booking.runningLateSent ? null : () => _runningLateSheet(booking),
          ),
        ],
      ),
    );
  }

  Widget _arrivalBlock(ProviderBooking booking) {
    final done = booking.faceVerifiedAt != null;
    return SCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            t('At the door'),
            trailing: StatusChip(done ? 'Checked in' : 'Not yet',
                tone: done ? ChipTone.good : ChipTone.warn, dense: true),
          ),
          Text(
            t('Take a photo of yourself at the door. Sathiyaa keeps it with the booking and checks you are at the right address before the customer is sent their code.'),
            style: ST.body,
          ),
          const SizedBox(height: 14),
          if (!done)
            GradientButton(
              label: t('Take arrival photo'),
              icon: Icons.photo_camera_rounded,
              busy: busy,
              onPressed: busy ? null : () => _faceCheck(booking),
            )
          else
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: SC.greenTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_rounded, color: SC.green, size: 19),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(t('Photo saved, and you are on site.'),
                        style: const TextStyle(
                            color: Color(0xFF1F7A45),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _otpBlock(ProviderBooking booking) {
    final sent = booking.otp != null;
    return SCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(t('Start the visit')),
          if (!sent) ...[
            Text(
              t('The customer gets a six-digit code on their phone. Ask them to read it to you, then type it in here.'),
              style: ST.body,
            ),
            const SizedBox(height: 14),
            GradientButton(
              label: t('Send code to the customer'),
              icon: Icons.send_rounded,
              busy: busy,
              onPressed: busy
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        final otp = await Backend.instance.startService(booking.id);
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(
                              content: Text(t('Code sent to the customer (test aid: {code})',
                                  {'code': otp}))),
                        );
                        setState(() {});
                      } catch (e) {
                        messenger.showSnackBar(SnackBar(
                            content: Text(e.toString().replaceFirst('Exception: ', ''))));
                      }
                    },
            ),
          ] else ...[
            Text(t('Ask the customer for the six digits on their screen.'),
                style: ST.body),
            const SizedBox(height: 14),
            TextField(
              controller: otpCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 8),
              decoration: const InputDecoration(
                counterText: '',
                hintText: '••••••',
                hintStyle: TextStyle(letterSpacing: 8, color: SC.hairlineCool),
              ),
            ),
            const SizedBox(height: 12),
            GradientButton(
              label: t('Start'),
              icon: Icons.play_arrow_rounded,
              busy: busy,
              onPressed: busy
                  ? null
                  : () async {
                      await run(() => Backend.instance
                          .confirmOtpAndStart(booking.id, otpCtrl.text.trim()));
                      if (mounted) setState(() {});
                    },
            ),
          ],
        ],
      ),
    );
  }

  Widget _workingBlock(ProviderBooking booking) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DarkCard(
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
                  const LivePulse(color: Colors.white, size: 8),
                  const SizedBox(width: 6),
                  Text(t('IN PROGRESS'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                booking.serviceStartedAt == null
                    ? 'The visit has started.'
                    : 'Started at ${_hhmm(booking.serviceStartedAt!)}',
                style: const TextStyle(
                    color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(t('Billed on the hours you actually work.'),
                  style: const TextStyle(color: Colors.white70, fontSize: 13.5)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.directions_rounded, size: 18),
                label: Text(t('Show directions')),
                onPressed: () => _showDirections(booking),
              ),
              const SizedBox(height: 12),
              GradientButton(
                label: t('End the visit'),
                icon: Icons.stop_rounded,
                busy: busy,
                onPressed: busy ? null : () => _endService(booking),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Ends the visit, and — for somebody who gives their time free — says thank
  /// you. Nothing is awarded; it is a moment of warmth and then out.
  Future<void> _endService(ProviderBooking booking) async {
    final hours = booking.totalHours;
    await run(() => Backend.instance.endService(booking.id));
    if (!mounted) return;
    setState(() {});

    if (Backend.instance.currentProvider?.noFees ?? false) {
      await _thankYou(b.totalHours ?? hours);
    }
  }

  Future<void> _thankYou(double? hours) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: SC.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SC.rCard)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 32, 26, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SuccessCheck(color: SC.green),
              const SizedBox(height: 20),
              Text(t('Thank you'), style: ST.h1, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Text(
                hours == null
                    ? 'Somebody had company today because you turned up. Nothing is '
                        'charged for your visit.'
                    : 'You gave ${hours.toStringAsFixed(1)} hours today, and nothing '
                        'is charged for them. Somebody was not alone because you '
                        'turned up.',
                style: ST.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(t('Close')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paymentBlock(ProviderBooking booking) {
    final volunteer = Backend.instance.currentProvider?.noFees ?? false;

    if (volunteer) {
      return SCard(
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
              child: const Icon(Icons.favorite_rounded, color: SC.green, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('Nothing to collect'), style: ST.h3),
                  const SizedBox(height: 3),
                  Text(
                    booking.totalHours == null
                        ? 'You gave this visit free. Thank you.'
                        : '${booking.totalHours!.toStringAsFixed(1)} hours, given free. Thank you.',
                    style: ST.small,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final outstanding = booking.amountDue - booking.amountReceived;
    final paid = booking.paymentStatus == PaymentStatus.paid;

    return SCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(
            t('Payment'),
            trailing: StatusChip(
              switch (booking.paymentStatus) {
                PaymentStatus.paid => 'Paid',
                PaymentStatus.partial => 'Part paid',
                PaymentStatus.unpaid => 'Unpaid',
              },
              tone: switch (booking.paymentStatus) {
                PaymentStatus.paid => ChipTone.good,
                PaymentStatus.partial => ChipTone.warn,
                PaymentStatus.unpaid => ChipTone.bad,
              },
              dense: true,
            ),
          ),
          Row(
            children: [
              Expanded(child: _money('Due', booking.amountDue)),
              Expanded(child: _money('Received', booking.amountReceived)),
              if (!paid) Expanded(child: _money('Outstanding', outstanding)),
            ],
          ),
          if (!paid) ...[
            const SizedBox(height: 16),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: t('Amount handed over now'),
                prefixText: '₹ ',
              ),
            ),
            const SizedBox(height: 12),
            GradientButton(
              label: t('Mark the full ₹{amount} received',
                  {'amount': outstanding.toStringAsFixed(0)}),
              icon: Icons.check_rounded,
              busy: busy,
              onPressed: busy
                  ? null
                  : () async {
                      await run(() => Backend.instance
                          .recordPayment(booking.id, outstanding, full: true));
                      if (mounted) setState(() {});
                    },
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () async {
                      await run(() => Backend.instance.recordPayment(
                          booking.id, double.tryParse(amountCtrl.text) ?? 0,
                          full: false));
                      if (mounted) setState(() {});
                    },
              child: Text(t('Record a part payment')),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              icon: const Icon(Icons.notifications_outlined, size: 17),
              label: Text(booking.paymentReminderSentAt == null
                  ? 'Remind the customer'
                  : 'Reminder sent'),
              onPressed: booking.paymentReminderSentAt != null || busy
                  ? null
                  : () async {
                      await run(() => Backend.instance.sendPaymentReminder(booking.id));
                      if (mounted) setState(() {});
                    },
            ),
          ],
        ],
      ),
    );
  }

  Widget _money(String label, double value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: ST.small.copyWith(fontSize: 11.5)),
        const SizedBox(height: 3),
        Text('₹${value.toStringAsFixed(0)}', style: ST.h3.copyWith(fontSize: 18)),
      ],
    );
  }

  Widget _rateBlock(ProviderBooking booking) {
    return SCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(t('How was the visit?')),
          Text(
            t('Your rating is private to Sathiyaa and helps the next carer know what to expect.'),
            style: ST.body,
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            icon: const Icon(Icons.star_rounded, size: 18),
            label: Text(t('Rate this customer')),
            onPressed: () => _rateCustomerDialog(context, booking),
          ),
        ],
      ),
    );
  }

  String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// ", 78" after a name. A carer knows what to expect from an age in a way
  /// they do not from a date of birth read off a screen at the door.
  String _ageSuffix(DateTime? dob) {
    if (dob == null) return '';
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) age--;
    if (age < 0 || age > 120) return '';
    return ', $age';
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

  // ---- unchanged handlers ---------------------------------------------

  void _showDirections(ProviderBooking booking) {
    final p = Backend.instance.currentProvider!;
    final fromLat = p.currentLat ?? p.lat;
    final fromLng = p.currentLng ?? p.lng;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SC.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t('Directions'), style: ST.h2),
              const SizedBox(height: 14),
              DirectionsPanel(
                fromLat: fromLat,
                fromLng: fromLng,
                toLat: booking.customerLat,
                toLng: booking.customerLng,
                destination: booking.customerAddress.isEmpty
                    ? booking.customerName
                    : booking.customerAddress,
                distanceKm: MockBackend.distanceKm(
                    fromLat, fromLng, booking.customerLat, booking.customerLng),
              ),
              // Demo mode only.
              //
              // This reports the CUSTOMER'S coordinates as the carer's
              // position. Offline, with no server and nobody to mislead, it
              // is how a tester reaches the arrival screen without driving
              // anywhere. Against a live server it is a button that puts a
              // carer at the family's front door without them going there —
              // defeating the geofence the start-of-service check exists to
              // run, and writing a false position into the tracking map an
              // administrator is trusting.
              if (!Backend.isLive) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.near_me_rounded, size: 18),
                    label: Text(t('Demo: pretend I have arrived')),
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      await Backend.instance
                          .pingLocation(booking.customerLat, booking.customerLng);
                      if (!mounted) return;
                      navigator.pop();
                      setState(() {});
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runningLateSheet(ProviderBooking booking) async {
    final eta = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: SC.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(t('How late will you be?'), style: ST.h2),
              ),
            ),
            for (final option in ['10 minutes', '15 minutes', '30 minutes'])
              ListTile(
                leading: const Icon(Icons.schedule_rounded, color: SC.blueBright),
                title: Text(option, style: ST.bodyStrong),
                onTap: () => Navigator.pop(context, option),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (eta == null) return;
    await run(() => Backend.instance.sendRunningLate(booking.id, eta));
    if (mounted) setState(() {});
  }

  /// Rings the customer.
  ///
  /// The number is shown and dialled directly. Masked calling — where neither
  /// side sees the other's real number — needs a paid telephony account, and
  /// the backend has the endpoint ready behind
  /// backend/src/integrations/masked_calls; until that is switched on, this is
  /// the honest version rather than a button that does nothing.
  Future<void> _callCustomer(ProviderBooking booking) async {
    final number = booking.customerMobile;
    if (number == null || number.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri(scheme: 'tel', path: number);
    try {
      final launched = await launchUrl(uri);
      if (!launched && mounted) {
        messenger.showSnackBar(
            SnackBar(
                content: Text(t('Could not open the dialler. The number is {number}.',
                    {'number': number}))));
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
            SnackBar(
                content: Text(t('Could not open the dialler. The number is {number}.',
                    {'number': number}))));
      }
    }
  }

  /// Takes the arrival selfie, then runs the checks.
  ///
  /// The camera opens for real, which is also what asks the phone for camera
  /// permission. Previously this sent a made-up filename, so nothing was
  /// photographed and nothing was kept.
  Future<void> _faceCheck(ProviderBooking booking) async {
    final messenger = ScaffoldMessenger.of(context);

    String? selfiePath;
    try {
      final shot = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 1200,
        imageQuality: 80,
      );
      selfiePath = shot?.path;
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(t('Could not open the camera: {error}', {'error': e})),
        backgroundColor: SC.redDeep,
      ));
      return;
    }
    if (selfiePath == null) {
      messenger.showSnackBar(SnackBar(
        content: Text(t('A photo of you is needed before the customer gets their code.')),
      ));
      return;
    }

    setState(() => busy = true);
    final result =
        await Backend.instance.verifyFaceAndGeofence(booking.id, selfiePath: selfiePath);
    if (!mounted) return;
    setState(() => busy = false);
    messenger.showSnackBar(SnackBar(
      content: Text(result.message),
      backgroundColor: result.passed ? SC.green : SC.redDeep,
    ));
  }

  Future<void> _rateCustomerDialog(BuildContext context, ProviderBooking booking) async {
    double rating = 5;
    final commentCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          backgroundColor: SC.surface,
          title: Text(t('Rate this customer'), style: ST.h2),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StarPicker(
                value: rating.round(),
                onChanged: (v) => setD(() => rating = v.toDouble()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: commentCtrl,
                decoration: InputDecoration(labelText: t('Anything worth noting?')),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Submit'))),
          ],
        );
      }),
    );
    if (ok == true) {
      await Backend.instance.rateCustomer(booking.id, rating, commentCtrl.text.trim());
      if (mounted) setState(() {});
    }
  }
}
