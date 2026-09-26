// The two account cards on the profile: the annual registration fee, and the
// business-partner reference code.
//
// Rebuilt on the design system. The fee used to be settled by a button reading
// "Mark registration complete" — accurate, since nothing is taken, but it made
// the one recurring charge in the app feel unlike every other payment in it.
// It now goes through the same simulated UPI / card chooser the booking fee
// does, and says just as plainly that no money moves.

import 'package:flutter/material.dart';

import '../backend.dart';
import '../mock_data.dart';
import '../theme/sathiyaa_theme.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../widgets/motion.dart';
import '../widgets/sathiyaa_ui.dart';
import 'payment_screen.dart' show PayMethod, UpiApp, kUpiApps;
import '../i18n/l10n.dart';

/// Annual registration fee.
///
/// No payment provider is connected yet, so this records the fee as settled
/// rather than pretending to take money. The amount and the transaction row are
/// still written, so switching on a real gateway later
/// (backend/src/integrations/payment.js) changes how it is collected, not what
/// is recorded.
class RegistrationPaymentCard extends StatefulWidget {
  final VoidCallback onChanged;
  const RegistrationPaymentCard({super.key, required this.onChanged});

  @override
  State<RegistrationPaymentCard> createState() => _RegistrationPaymentCardState();
}

class _RegistrationPaymentCardState extends State<RegistrationPaymentCard> {
  Future<void> _openSheet(double amount) async {
    final paid = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FeeSheet(amount: amount),
    );
    if (paid == true && mounted) {
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('Registration fee recorded — your account is active.'))),
      );
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Backend.instance.currentCustomer!;
    final paid = c.registrationFeePaid;

    // A fee of zero is not a payment of zero.
    //
    // The amount is set in the admin console, and setting it to 0 used to
    // leave this card offering "Pay ₹0" over a gateway that refuses orders
    // under a rupee -- so the one price the product could not charge was
    // free. When there is nothing to pay there is nothing to pay for: the
    // card says so and offers no button.
    if (c.registrationFeeAmount <= 0) return _noFeeCard(paid);

    // Three states once there is a fee at all: never paid, inside the paid
    // year, and a year gone by. The renewal rate is a different number from
    // the joining rate — it is set separately in the admin console — and the
    // server has already worked out which one applies here.
    final due = paid && c.registrationRenewalDue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          t('Registration'),
          trailing: StatusChip(
            !paid ? 'Due' : due ? 'Renew' : 'Paid',
            tone: !paid ? ChipTone.warn : due ? ChipTone.warn : ChipTone.good,
            dense: true,
          ),
        ),
        SCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(inr(c.registrationFeeAmount),
                      style: ST.figure.copyWith(fontSize: 30)),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(t('a year'), style: ST.small),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                !paid
                    ? t('Charged once a year, and it keeps your account active so carers can accept your bookings.')
                    : due
                        ? t('Your year is up. Nothing has stopped working — renew whenever it suits you.')
                        : t('Charged once a year. Nothing is due right now.'),
                style: ST.small.copyWith(height: 1.45),
              ),
              const SizedBox(height: 14),
              if (paid && !due)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SC.greenTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF1F7A45), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                            c.registrationRenewsAt == null
                                ? t('Recorded as paid.')
                                : t('Paid. Renews on {date}.',
                                    {'date': prettyDate(c.registrationRenewsAt!)}),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, color: Color(0xFF1F7A45))),
                      ),
                    ],
                  ),
                )
              else
                GradientButton(
                  label: due
                      ? t('Renew for {amount}', {'amount': inr(c.registrationFeeAmount)})
                      : t('Pay {amount}', {'amount': inr(c.registrationFeeAmount)}),
                  icon: due
                      ? Icons.autorenew_rounded
                      : Icons.account_balance_wallet_rounded,
                  onPressed: () => _openSheet(c.registrationFeeAmount),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

extension _NoFee on _RegistrationPaymentCardState {
  Widget _noFeeCard(bool paid) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          t('Registration'),
          trailing: StatusChip(t('Free'), tone: ChipTone.good, dense: true),
        ),
        SCard(
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: SC.greenTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.card_giftcard_rounded,
                    size: 19, color: Color(0xFF1F7A45)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('Nothing to pay'), style: ST.h3),
                    const SizedBox(height: 4),
                    Text(
                      t('Sathiyaa is not charging a registration fee at the moment. Your account is active.'),
                      style: ST.small.copyWith(height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The method chooser for the annual fee.
///
/// Deliberately the same shapes as the booking payment screen — the same UPI
/// apps, the same simulated authorisation, the same warning — so paying twice
/// in this app never feels like paying in two different apps.
class _FeeSheet extends StatefulWidget {
  const _FeeSheet({required this.amount});
  final double amount;

  @override
  State<_FeeSheet> createState() => _FeeSheetState();
}

class _FeeSheetState extends State<_FeeSheet> {
  PayMethod _method = PayMethod.upi;
  UpiApp _app = kUpiApps.first;
  bool _busy = false;
  String? _error;

  Future<void> _pay() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    await _authorising();
    if (!mounted) return;
    try {
      await Backend.instance.payRegistrationFee();
      if (!mounted) return;
      await _success();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _authorising() async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: SC.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SC.rCard)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(strokeWidth: 3, color: SC.blueBright),
              ),
              const SizedBox(height: 20),
              Text(
                _method == PayMethod.upi
                    ? 'Opening ${_app.name}…'
                    : 'Authorising your card…',
                style: ST.h3,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(t('Simulated — no payment provider is connected'),
                  style: ST.small, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _success() async {
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
              const SuccessCheck(),
              const SizedBox(height: 20),
              Text(t('Registration active'), style: ST.h1, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(t('{amount} recorded. Nothing due for another year.',
                      {'amount': inr(widget.amount)}),
                  style: ST.small, textAlign: TextAlign.center),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(t('Done')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: SC.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(SC.gutter, 10, SC.gutter, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: SC.hairlineCool,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: Text(t('Annual registration'), style: ST.h2)),
                  Text(inr(widget.amount), style: ST.figure.copyWith(fontSize: 24)),
                ],
              ),
              const SizedBox(height: 16),
              FieldLabel(t('Pay with')),
              Row(
                children: [
                  Expanded(
                    child: _methodTile(
                      on: _method == PayMethod.upi,
                      icon: Icons.qr_code_rounded,
                      label: 'UPI',
                      onTap: () => setState(() => _method = PayMethod.upi),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _methodTile(
                      on: _method == PayMethod.card,
                      icon: Icons.credit_card_rounded,
                      label: t('Card'),
                      onTap: () => setState(() => _method = PayMethod.card),
                    ),
                  ),
                ],
              ),
              if (_method == PayMethod.upi) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: [
                    for (final a in kUpiApps)
                      PressableScale(
                        onTap: () => setState(() => _app = a),
                        child: AnimatedContainer(
                          duration: Dur.quick,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: SC.surface,
                            borderRadius: BorderRadius.circular(SC.rPill),
                            border: Border.all(
                              color: _app == a ? a.color : SC.hairlineCool,
                              width: _app == a ? 1.8 : 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                alignment: Alignment.center,
                                decoration:
                                    BoxDecoration(color: a.color, shape: BoxShape.circle),
                                child: Text(a.glyph,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800)),
                              ),
                              const SizedBox(width: 8),
                              Text(a.name,
                                  style: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SC.amberTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 17, color: Color(0xFFA9670F)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t('No payment provider is connected. This runs a simulated authorisation and records the fee. No money moves.'),
                        style: ST.small
                            .copyWith(color: const Color(0xFF8A5510), height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                InlineError(message: _error!),
              ],
              const SizedBox(height: 16),
              GradientButton(
                label: t('Pay {amount}', {'amount': inr(widget.amount)}),
                icon: Icons.lock_rounded,
                busy: _busy,
                onPressed: _busy ? null : _pay,
              ),
              const SizedBox(height: 6),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                  child: Text(t('Not now')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _methodTile({
    required bool on,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Dur.quick,
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? SC.blueTint : SC.surface,
          borderRadius: BorderRadius.circular(SC.rField),
          border: Border.all(
            color: on ? SC.blueBright : SC.hairlineCool,
            width: on ? 1.8 : 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: on ? SC.blueBright : SC.inkSoft),
            const SizedBox(width: 9),
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: on ? SC.blue : SC.inkSoft)),
          ],
        ),
      ),
    );
  }
}

/// Business Partner reference code. Entering a valid code links this customer
/// to the partner who referred them, which is what drives that partner's
/// revenue share on every hour the customer subsequently books.
class ReferenceCodeCard extends StatefulWidget {
  final VoidCallback onChanged;
  const ReferenceCodeCard({super.key, required this.onChanged});

  @override
  State<ReferenceCodeCard> createState() => _ReferenceCodeCardState();
}

class _ReferenceCodeCardState extends State<ReferenceCodeCard> {
  final ctrl = TextEditingController();
  bool busy = false;
  String? error;
  String? partnerName;

  @override
  void initState() {
    super.initState();
    ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final name = await Backend.instance.applyReferenceCode(ctrl.text.trim());
      if (!mounted) return;
      setState(() => partnerName = name);
      widget.onChanged();
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _clear() async {
    await Backend.instance.clearReferenceCode();
    if (!mounted) return;
    setState(() {
      partnerName = null;
      ctrl.clear();
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final customer = Backend.instance.currentCustomer!;
    final code = customer.referenceCode;
    // The name the server confirmed, kept on the customer so it survives the
    // app being closed. The demo map is the fallback for offline mode, where
    // there is no server to confirm anything.
    final knownPartner = partnerName ??
        customer.referencePartner ??
        (code == null ? null : MockBackend.referralCodes[code]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(t('Reference code')),
        SCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (code != null) ...[
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: SC.greenTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_rounded,
                          color: Color(0xFF1F7A45), size: 19),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(code,
                                style: ST.bodyStrong.copyWith(
                                    letterSpacing: 1.2, color: const Color(0xFF1F7A45))),
                            if (knownPartner != null) ...[
                              const SizedBox(height: 2),
                              Text(knownPartner,
                                  style: ST.small.copyWith(fontSize: 12.5)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _clear,
                  style: OutlinedButton.styleFrom(
                      foregroundColor: SC.inkSoft,
                      minimumSize: const Size.fromHeight(46)),
                  child: Text(t('Remove this code')),
                ),
              ] else ...[
                Text(
                  t('Given a code by a Sathiyaa business partner — a hospital, a clinic, a society office? Enter it here.'),
                  style: ST.small.copyWith(height: 1.45),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: t('e.g. APOL2337'),
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 12),
                GradientButton(
                  label: t('Apply code'),
                  icon: Icons.local_offer_rounded,
                  busy: busy,
                  onPressed: (busy || ctrl.text.trim().isEmpty) ? null : _apply,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
