// Welcome, register and log in — the first three screens anyone sees.
//
// Rebuilt on the design system. The submit logic is unchanged; what changed is
// how it presents itself, plus four real fixes found while going through it:
//
//   * the register button was labelled "Set OTP";
//   * the login screen posted whatever was in the mobile box, including
//     nothing at all, and let the server do the complaining;
//   * resending had no cooldown, so it could be tapped in a loop;
//   * both verify steps ran `setState` in a `finally` that fires after the
//     screen has already been replaced by the home shell.

import 'dart:async';

import 'package:flutter/material.dart';

import '../backend.dart';
import '../mock_data.dart';
import '../i18n/l10n.dart';
import '../theme/sathiyaa_theme.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import '../widgets/sathiyaa_ui.dart';
import 'app_entry.dart';
import 'legal_content.dart';
import 'server_settings_screen.dart';

/// The seeded customer in demo data. Shown — and pre-filled — only when the app
/// is on demo data, so somebody handed the APK can get in without being told
/// the number over the phone.
const _demoMobile = MockBackend.demoMobile;

/// Long enough that a resend is a considered act, short enough that somebody
/// whose SMS genuinely did not arrive is not left waiting.
const _resendSeconds = 30;

String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');

// ---------------------------------------------------------------------------
// WELCOME
// ---------------------------------------------------------------------------

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          BrandHeader(
            height: 340,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(SC.gutter, 8, SC.gutter, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: PressableScale(
                      onTap: () => push(context, const ServerSettingsScreen()),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(SC.rPill),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.dns_rounded, size: 15, color: Colors.white),
                            SizedBox(width: 7),
                            BackendModeChip(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  const SathiyaaLogo(size: 86),
                  const SizedBox(height: 18),
                  Text(t('Sathiyaa'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5)),
                  const SizedBox(height: 6),
                  Text(t('Aging with dignity, living with passion'),
                      style: const TextStyle(color: Colors.white70, fontSize: 15.5)),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          Expanded(
            child: PagePad(
              top: 28,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FadeInUp(
                    index: 0,
                    child: GradientButton(
                      label: t('Create an account'),
                      icon: Icons.person_add_rounded,
                      onPressed: () => push(context, const RegisterScreen()),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FadeInUp(
                    index: 1,
                    child: OutlinedButton(
                      onPressed: () => push(context, const LoginScreen()),
                      child: Text(t('I already have an account')),
                    ),
                  ),
                  if (!Backend.isLive) ...[
                    const SizedBox(height: 16),
                    // A tap rather than a note. The app no longer opens already
                    // signed in — a first run has to show the journey above —
                    // so the quick look everybody actually wants has to be one
                    // press, not a number to copy out of a sentence.
                    FadeInUp(
                      index: 2,
                      child: PressableScale(
                        onTap: () async {
                          await MockBackend.instance.openDemoAccount();
                          if (!context.mounted) return;
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const AppEntry()),
                            (route) => false,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: SC.goldTint,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFEEDCB6)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.science_rounded,
                                  size: 17, color: Color(0xFF8A6317)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Running on demo data. Open the demo account '
                                  '($_demoMobile) without signing up.',
                                  style: ST.small.copyWith(
                                      color: const Color(0xFF7A5612), height: 1.4),
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded,
                                  size: 19, color: Color(0xFF8A6317)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Text(
                      t('Every carer is checked by Sathiyaa before you can find them — ID, police verification, and a medical certificate for clinical work.'),
                      textAlign: TextAlign.center,
                      style: ST.small,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// REGISTER
// ---------------------------------------------------------------------------

class RegisterScreen extends StatefulWidget {
  /// Jumps straight to the Terms gate, for a session that was restored after
  /// the OTP was verified but before the terms were accepted.
  final bool startAtTerms;
  const RegisterScreen({super.key, this.startAtTerms = false});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  late String step = widget.startAtTerms ? 'agree' : 'form'; // form -> otp -> agree
  final nameCtrl = TextEditingController();
  final mobileCtrl = TextEditingController();
  final otpCtrl = TextEditingController();
  String? devOtp;
  String? error;
  bool busy = false;
  bool agreed = false;

  int _cooldown = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    otpCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    nameCtrl.dispose();
    mobileCtrl.dispose();
    otpCtrl.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _ticker?.cancel();
    setState(() => _cooldown = _resendSeconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> submitForm() async {
    setState(() => error = null);
    if (nameCtrl.text.trim().length < 2) {
      setState(() => error = t('Please enter your full name.'));
      return;
    }
    if (mobileCtrl.text.trim().length != 10) {
      setState(() => error = t('A mobile number is ten digits, with no country code.'));
      return;
    }
    setState(() => busy = true);
    try {
      final otp = await Backend.instance
          .registerCustomer(name: nameCtrl.text.trim(), mobile: mobileCtrl.text.trim());
      if (!mounted) return;
      setState(() {
        devOtp = otp;
        otpCtrl.clear();
        step = 'otp';
      });
      _startCooldown();
    } catch (e) {
      if (mounted) setState(() => error = _clean(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> verify() async {
    setState(() {
      error = null;
      busy = true;
    });
    try {
      await Backend.instance.verifyOtp(mobileCtrl.text.trim(), otpCtrl.text.trim());
      if (!mounted) return;
      setState(() => step = 'agree');
    } catch (e) {
      if (mounted) setState(() => error = _clean(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> agreeAndContinue() async {
    if (!agreed) return;
    final navigator = Navigator.of(context);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await Backend.instance.acceptTerms();
      if (!mounted) return;
      navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AppEntry()), (r) => false);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = _clean(e);
        });
      }
    }
  }

  int get _stepIndex => switch (step) { 'form' => 0, 'otp' => 1, _ => 2 };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          _AuthHeader(
            title: t('Create an account'),
            subtitle: switch (step) {
              'form' => t('Two details and you are in.'),
              'otp' => t('Confirm the number is yours.'),
              _ => t('One last thing.'),
            },
            steps: [t('Your details'), t('Verify'), t('Agree')],
            current: _stepIndex,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(SC.gutter, 20, SC.gutter, 32),
              children: [
                if (step == 'form') ..._formStep(),
                if (step == 'otp') ..._otpStep(),
                if (step == 'agree') ..._agreeStep(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _formStep() => staggered([
        SCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FieldLabel(t('Full name'), required: true),
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(hintText: t('As it appears on your ID')),
              ),
              const SizedBox(height: 16),
              FieldLabel(t('Mobile number'), required: true),
              TextField(
                controller: mobileCtrl,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                decoration: InputDecoration(
                  hintText: t('10 digits, no country code'),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 6),
              Text(t('We send a code to this number to confirm it is yours.'),
                  style: ST.small.copyWith(fontSize: 12, height: 1.4)),
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          InlineError(message: error!),
        ],
        const SizedBox(height: 20),
        GradientButton(
          label: t('Send the code'),
          icon: Icons.sms_rounded,
          busy: busy,
          onPressed: busy ? null : submitForm,
        ),
      ]);

  List<Widget> _otpStep() => staggered([
        SCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(t('Sent to {mobile}', {'mobile': mobileCtrl.text.trim()}),
                        style: ST.bodyStrong.copyWith(fontSize: 14.5)),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => setState(() => step = 'form'),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: Text(t('Change')),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (devOtp != null)
                DevOtpBanner(otp: devOtp!, onUse: () => otpCtrl.text = devOtp!)
              else
                Text(t('We have sent you a code by SMS.'), style: ST.small),
              const SizedBox(height: 16),
              FieldLabel(t('Enter the code')),
              TextField(
                controller: otpCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 10),
                decoration: const InputDecoration(counterText: ''),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: (_cooldown > 0 || busy) ? null : submitForm,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: Text(_cooldown > 0
                      ? 'Send a new code in ${_cooldown}s'
                      : t('Send a new code')),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                ),
              ),
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          InlineError(message: error!),
        ],
        const SizedBox(height: 20),
        GradientButton(
          label: t('Verify and continue'),
          icon: Icons.check_rounded,
          busy: busy,
          // Six digits or it does nothing anyway, so the button says so.
          onPressed: (busy || otpCtrl.text.trim().length != 6) ? null : verify,
        ),
      ]);

  List<Widget> _agreeStep() {
    final who = nameCtrl.text.trim().isEmpty
        ? (Backend.instance.currentCustomer?.name ?? 'there')
        : nameCtrl.text.trim();
    return staggered([
      SCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                      color: SC.greenTint, shape: BoxShape.circle),
                  child: const Icon(Icons.verified_rounded,
                      size: 21, color: Color(0xFF1F7A45)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(t('You are verified, {name}.', {'name': who}),
                      style: ST.h3, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              t('Before you book anybody, please read what we promise you and what we ask of you.'),
              style: ST.small.copyWith(height: 1.45),
            ),
            const SizedBox(height: 14),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => push(context, const LegalContentScreen()),
                child: Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: SC.sunkTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.description_rounded, size: 18, color: SC.blueBright),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(t('Terms & Conditions and Privacy Policy'),
                            style: ST.bodyStrong),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: SC.inkFaint),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            CheckboxListTile(
              value: agreed,
              onChanged: (v) => setState(() => agreed = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(t('I have read and agree to both.'),
                  style: ST.body.copyWith(fontSize: 14.5)),
            ),
          ],
        ),
      ),
      if (error != null) ...[
        const SizedBox(height: 16),
        InlineError(message: error!),
      ],
      const SizedBox(height: 20),
      GradientButton(
        label: t('Start using Sathiyaa'),
        icon: Icons.arrow_forward_rounded,
        busy: busy,
        onPressed: agreed && !busy ? agreeAndContinue : null,
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// LOG IN
// ---------------------------------------------------------------------------

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Pre-filled on demo data only. On a live server this stays empty.
  late final mobileCtrl = TextEditingController(text: Backend.isLive ? '' : _demoMobile);
  final otpCtrl = TextEditingController();
  String step = 'mobile';
  String? devOtp;
  String? error;
  bool busy = false;

  int _cooldown = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    otpCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    mobileCtrl.dispose();
    otpCtrl.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _ticker?.cancel();
    setState(() => _cooldown = _resendSeconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> requestOtp() async {
    // The number was posted as typed before, so a blank box became a server
    // error rather than a sentence the customer could act on.
    if (mobileCtrl.text.trim().length != 10) {
      setState(() => error = t('A mobile number is ten digits, with no country code.'));
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final otp = await Backend.instance.loginRequestOtp(mobileCtrl.text.trim());
      if (!mounted) return;
      setState(() {
        devOtp = otp;
        otpCtrl.clear();
        step = 'otp';
      });
      _startCooldown();
    } catch (e) {
      if (mounted) setState(() => error = _clean(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> verify() async {
    final navigator = Navigator.of(context);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await Backend.instance.verifyOtp(mobileCtrl.text.trim(), otpCtrl.text.trim());
      if (!mounted) return;
      navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AppEntry()), (r) => false);
      // Deliberately no setState after this: the screen is gone, and the old
      // `finally` block used to call one anyway.
      return;
    } catch (e) {
      if (mounted) {
        setState(() {
          error = _clean(e);
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          _AuthHeader(
            title: t('Log in'),
            subtitle: step == 'mobile'
                ? 'Your mobile number is your account.'
                : t('Confirm the number is yours.'),
            steps: const ['Your number', 'Verify'],
            current: step == 'mobile' ? 0 : 1,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(SC.gutter, 20, SC.gutter, 32),
              children: step == 'mobile' ? _mobileStep() : _otpStep(),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _mobileStep() => staggered([
        SCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FieldLabel(t('Mobile number'), required: true),
              TextField(
                controller: mobileCtrl,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: t('10 digits, no country code'),
                  counterText: '',
                ),
              ),
              if (!Backend.isLive) ...[
                const SizedBox(height: 8),
                Text(t('Demo data: {mobile} is already filled in for you.',
                        {'mobile': _demoMobile}),
                    style: ST.small.copyWith(fontSize: 12, color: SC.gold)),
              ],
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          InlineError(message: error!),
        ],
        const SizedBox(height: 20),
        GradientButton(
          label: t('Send the code'),
          icon: Icons.sms_rounded,
          busy: busy,
          onPressed: busy ? null : requestOtp,
        ),
      ]);

  List<Widget> _otpStep() => staggered([
        SCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(t('Sent to {mobile}', {'mobile': mobileCtrl.text.trim()}),
                        style: ST.bodyStrong.copyWith(fontSize: 14.5)),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => setState(() => step = 'mobile'),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: Text(t('Change')),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (devOtp != null)
                DevOtpBanner(otp: devOtp!, onUse: () => otpCtrl.text = devOtp!)
              else
                Text(t('We have sent you a code by SMS.'), style: ST.small),
              const SizedBox(height: 16),
              FieldLabel(t('Enter the code')),
              TextField(
                controller: otpCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 10),
                decoration: const InputDecoration(counterText: ''),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: (_cooldown > 0 || busy) ? null : requestOtp,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: Text(_cooldown > 0
                      ? 'Send a new code in ${_cooldown}s'
                      : t('Send a new code')),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                ),
              ),
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          InlineError(message: error!),
        ],
        const SizedBox(height: 20),
        GradientButton(
          label: t('Verify and continue'),
          icon: Icons.check_rounded,
          busy: busy,
          onPressed: (busy || otpCtrl.text.trim().length != 6) ? null : verify,
        ),
      ]);
}

// ---------------------------------------------------------------------------
// SHARED
// ---------------------------------------------------------------------------

/// The dark header the two auth screens share, with the step bar underneath.
///
/// The bar exists so nobody wonders how much further this goes. Three steps
/// is short; not knowing it is three is what makes a form feel long.
class _AuthHeader extends StatelessWidget {
  const _AuthHeader({
    required this.title,
    required this.subtitle,
    required this.steps,
    required this.current,
  });

  final String title;
  final String subtitle;
  final List<String> steps;
  final int current;

  @override
  Widget build(BuildContext context) {
    return BrandHeader(
      curved: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, SC.gutter, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.chevron_left_rounded,
                      color: Colors.white, size: 30),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: const TextStyle(color: Colors.white70, fontSize: 13.5)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Row(
                children: [
                  for (var i = 0; i < steps.length; i++) ...[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedContainer(
                            duration: Dur.normal,
                            curve: Ease.enter,
                            height: 4,
                            decoration: BoxDecoration(
                              color: i <= current
                                  ? SC.gold
                                  : Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            steps[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: i <= current
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (i != steps.length - 1) const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
