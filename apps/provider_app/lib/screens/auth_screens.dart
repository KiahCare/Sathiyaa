// Welcome, sign in, and provider registration.
//
// Rebuilt on the design system. The validation and the submit logic are
// unchanged — they were the part that worked. What changed is how the five
// steps present themselves, and one decision that used to be a bare switch
// labelled "No Fees (donated / volunteer service)": giving your time free is
// now an explained choice between two cards, because nobody should opt into
// working unpaid by flipping a toggle whose label is jargon.

import 'package:flutter/material.dart';

import '../models.dart';
import '../backend.dart';
import '../mock_data.dart';
import '../theme/sathiyaa_theme.dart';
import '../widgets/sathiyaa_ui.dart';
import '../widgets/motion.dart';
import '../widgets/document_field.dart';
import '../widgets/osm_map.dart';
import '../city_defaults.dart';
import '../languages.dart';
import '../services/location_service.dart';
import '../services/geocode.dart';
import 'app_entry.dart';
import 'server_settings_screen.dart';
import '../utils/dates.dart';
import '../i18n/l10n.dart';

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
            height: 330,
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
                  Text(t('Care work, on your own schedule'),
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
                      label: t('Register as a provider'),
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
                    const SizedBox(height: 10),
                    FadeInUp(
                      index: 2,
                      // This used to walk straight into the home shell, which
                      // worked only because demo data opened already signed in.
                      // It does not any more, so the button has to actually
                      // sign in — otherwise the first screen reads
                      // currentProvider! and the app dies on the spot.
                      child: TextButton(
                        onPressed: () async {
                          await MockBackend.instance.openDemoAccount();
                          if (!context.mounted) return;
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const AppEntry()),
                            (r) => false,
                          );
                        },
                        child: Text(t('Skip — look around with the demo account')),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Text(
                      t('Every provider is checked by Sathiyaa before families can find them — ID, police verification, and a medical certificate for clinical work.'),
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
// SIGN IN
// ---------------------------------------------------------------------------

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Only pre-filled off a live server, where it is the demo account and
  // filling it in saves a tester typing. Against a real server it starts
  // empty — pre-filling somebody else's number there would be nonsense.
  late final mobileCtrl =
      TextEditingController(text: Backend.isLive ? '' : MockBackend.demoMobile);
  late final pinCtrl =
      TextEditingController(text: Backend.isLive ? '' : MockBackend.demoPin);

  String? error;
  bool busy = false;

  @override
  void dispose() {
    mobileCtrl.dispose();
    pinCtrl.dispose();
    super.dispose();
  }

  Future<void> login() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await Backend.instance.loginWithPin(mobileCtrl.text.trim(), pinCtrl.text.trim());
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AppEntry()),
        (r) => false,
      );
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// A PIN reset needs an OTP and a new-PIN screen, and the server endpoint
  /// for it exists but is not wired to this app yet. Rather than a button that
  /// does nothing — which is what was here — this says who to ask.
  void _forgotPin() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SC.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                      color: SC.hairlineCool, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              Text(t('Forgotten your PIN?'), style: ST.h2),
              const SizedBox(height: 10),
              Text(
                t('Call Sathiyaa on 1800 123 4567 and they will reset it for you. Resetting it yourself from the app is not switched on yet.'),
                style: ST.body,
              ),
              const SizedBox(height: 18),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          BrandHeader(
            curved: false,
            child: BrandBar(
              title: t('Sign in'),
              subtitle: t('Your mobile number and PIN'),
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(SC.gutter, 22, SC.gutter, 24),
              children: staggered([
                if (!Backend.isLive)
                  Container(
                    padding: const EdgeInsets.all(13),
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: SC.amberTint,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFF0DCBC)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 18, color: Color(0xFFA9670F)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            t('Demo mode — the demo account is filled in below.'),
                            style: ST.small.copyWith(color: const Color(0xFF8A5510)),
                          ),
                        ),
                      ],
                    ),
                  ),
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
                const SizedBox(height: 16),
                FieldLabel(t('6-digit PIN'), required: true),
                TextField(
                  controller: pinCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  obscureText: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 8),
                  decoration: const InputDecoration(counterText: ''),
                ),
                if (error != null) ...[
                  const SizedBox(height: 16),
                  InlineError(message: error!),
                ],
                const SizedBox(height: 22),
                GradientButton(
                  label: t('Sign in'),
                  icon: Icons.login_rounded,
                  busy: busy,
                  onPressed: busy ? null : login,
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: _forgotPin,
                    child: Text(t('Forgotten your PIN?')),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// REGISTRATION
// ---------------------------------------------------------------------------

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  int step = 0;
  ProviderKind kind = ProviderKind.freelancer;
  final nameCtrl = TextEditingController();
  final mobileCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final addressCtrl = TextEditingController();
  String gender = 'Female';
  DateTime? dob;
  final rateCtrl = TextEditingController();
  bool noFees = false;
  Set<ServiceType> expertise = {ServiceType.companion};
  final Set<String> workDays = {'Mon', 'Tue', 'Wed', 'Thu', 'Fri'};

  /// What this carer speaks.
  ///
  /// The form never asked, and registration sent a hardcoded ['English'] for
  /// everybody. The customer app filters on this and prints it on every
  /// result card, so the filter worked perfectly and matched nobody, and
  /// every carer's card claimed English.
  /// Not asked for on this form.
  ///
  /// It used to be a required picker on the first step, and it was taken off
  /// because registration is where people give up and every field costs
  /// somebody. It is still a real field -- a family filters on it and reads
  /// it off the card -- so it is asked once, on the profile screen, where
  /// there is a banner that will not go away until it has been answered.
  ///
  /// English to begin with so the column is never null: JSON_CONTAINS against
  /// null matches nothing, which would make a carer invisible to every
  /// language search rather than only the wrong ones.
  final Set<String> languages = {...kDefaultLanguages};

  // ---- when those days are worked --------------------------------------
  //
  // Registration used to send 09:00-18:00 for every day somebody ticked,
  // because the form never asked. The backend has stored a start and end
  // time per day since the first migration, so this was throwing away real
  // information about when a carer is actually free -- and a family booking
  // 07:00 was matched against hours nobody had agreed to.
  String workFrom = '09:00';
  String workTo = '18:00';

  /// Off by default: most people keep the same hours, and asking them to fill
  /// in seven rows to say so is the kind of form nobody finishes.
  bool differentHours = false;
  final Map<String, DayHours> dayHours = {};

  // ---- organisations ----------------------------------------------------
  final contactCtrl = TextEditingController();
  final gstCtrl = TextEditingController();
  String? regCertUrl;
  String? aadharUrl;
  String? policeUrl;
  DateTime? policeFrom;
  DateTime? policeTo;
  String? medicalUrl;
  DateTime? medicalFrom;
  DateTime? medicalTo;
  final pinCtrl = TextEditingController();
  bool busy = false;
  String? error;

  /// Where the work-location pin sits. Starts on the city default and moves
  /// when the provider taps "Use my current location".
  double pinLat = kDefaultLat;
  double pinLng = kDefaultLng;
  bool locating = false;
  String? locationNote;
  bool locationFailed = false;

  /// The steps, named for whoever is filling them in. An organisation is not
  /// registering "You", and the papers it is asked for are not the same
  /// papers, so calling both paths by one set of labels was the first sign
  /// that one form was doing two jobs badly.
  List<JourneyStep> get _steps => isOrg
      ? const [
          JourneyStep('Organisation', Icons.business_rounded),
          JourneyStep('Office', Icons.place_rounded),
          JourneyStep('Rates', Icons.payments_rounded),
          JourneyStep('Registration', Icons.verified_rounded),
          JourneyStep('PIN', Icons.lock_rounded),
        ]
      : const [
          JourneyStep('You', Icons.person_rounded),
          JourneyStep('Work', Icons.place_rounded),
          JourneyStep('Pay', Icons.payments_rounded),
          JourneyStep('Papers', Icons.description_rounded),
          JourneyStep('PIN', Icons.lock_rounded),
        ];

  bool get isOrg => kind == ProviderKind.organization;

  final stepsTotal = 5;

  @override
  void dispose() {
    nameCtrl.dispose();
    mobileCtrl.dispose();
    emailCtrl.dispose();
    addressCtrl.dispose();
    rateCtrl.dispose();
    pinCtrl.dispose();
    contactCtrl.dispose();
    gstCtrl.dispose();
    super.dispose();
  }

  /// Clears one field's error as soon as it is edited, so the red text goes
  /// away when the problem does rather than lingering until the next tap.
  void _clearError(String key) {
    if (fieldErrors.containsKey(key)) {
      setState(() {
        fieldErrors.remove(key);
        if (fieldErrors.isEmpty) error = null;
      });
    }
  }

  /// Asks the phone where it is and drops the pin there.
  ///
  /// This is also the first time the app ever requests the location
  /// permission it has always declared in the manifest.
  Future<void> _useCurrentLocation() async {
    setState(() {
      locating = true;
      locationNote = null;
      locationFailed = false;
    });
    final fix = await LocationService.current();
    if (!mounted) return;
    if (!fix.isOk) {
      setState(() {
        locating = false;
        locationFailed = true;
        locationNote = fix.error;
      });
      return;
    }

    setState(() {
      pinLat = fix.lat!;
      pinLng = fix.lng!;
      locationFailed = false;
      locationNote = t('Finding your address…');
    });

    // A bonus on top of the pin, not a step that can fail the form.
    final place = await Geocode.reverse(fix.lat!, fix.lng!);
    if (!mounted) return;
    setState(() {
      locating = false;
      final pinNote = fix.accuracyMetres == null
          ? t('Pin set to where you are.')
          : t('Pin set to where you are (about {m} m accurate).',
              {'m': fix.accuracyMetres!.round()});
      if (place == null || place.isEmpty) {
        locationNote = pinNote;
        return;
      }
      if (addressCtrl.text.trim().isEmpty) {
        addressCtrl.text = place.oneLine;
        _clearError('address');
        locationNote =
            t('{pin} We filled the address in — check it and correct anything wrong.',
                {'pin': pinNote});
      } else {
        locationNote = t('{pin} Your address is already filled in, so nothing was changed.',
            {'pin': pinNote});
      }
    });
  }

  Future<void> _submit() async {
    if (!_validateAll()) return;
    await finish();
  }

  /// Field name -> what is wrong with it. Empty until Next is pressed, so the
  /// form does not scold anyone for fields they have not reached yet.
  Map<String, String> fieldErrors = {};

  // ------------------------------------------------------------ validation ---
  //
  // Registration used to let anyone press Next five times and submit an empty
  // application: no name, no mobile, no PIN, no documents. Each step is now
  // checked before it can be left, and the first offending field says what is
  // wrong, in red, underneath itself.

  static final _mobileRe = RegExp(r'^[6-9]\d{9}$');
  /// 2 digits state code, 10 character PAN, 1 entity digit, Z, 1 checksum.
  static final _gstRe = RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z]\d[Z][A-Z\d]$');
  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

  /// "18:00" is after "09:00". String comparison works because both are
  /// zero-padded 24-hour times, and being explicit about that is cheaper than
  /// parsing two DateTimes to find out.
  static bool _after(String a, String b) => a.compareTo(b) > 0;

  Map<String, String> _validate(int forStep) {
    final e = <String, String>{};
    switch (forStep) {
      case 0:
        if (nameCtrl.text.trim().length < 2) {
          e['name'] = isOrg ? t('Enter the organisation name.') : t('Enter your full name.');
        }
        if (isOrg && contactCtrl.text.trim().length < 2) {
          e['contact'] = t('Enter the name of the person we should speak to.');
        }
        if (!_mobileRe.hasMatch(mobileCtrl.text.trim())) {
          e['mobile'] = t('Enter a 10-digit Indian mobile number starting 6-9.');
        }
        final email = emailCtrl.text.trim();
        if (email.isNotEmpty && !_emailRe.hasMatch(email)) {
          e['email'] = t('That does not look like an email address.');
        }
        // Date of birth is optional now. It is still checked when given --
        // an age under 18 is a real problem whether or not the field was
        // required -- but a blank one no longer blocks the form.
        if (dob != null) {
          final years = DateTime.now().difference(dob!).inDays / 365.25;
          if (years < 18) e['dob'] = t('A carer must be at least 18 years old.');
          if (years > 80) e['dob'] = t('Please check the date of birth.');
        }
        break;
      case 1:
        if (addressCtrl.text.trim().length < 6) {
          e['address'] = isOrg
              ? t('Enter the registered office address.')
              : t('Enter your home address.');
        }
        // An organisation's own days are not a real constraint: an agency
        // covers whatever hours the carer it sends covers, and its carers
        // each have their own. Asking made it a required field that meant
        // nothing, so it is optional and the hours below follow it.
        if (!isOrg && workDays.isEmpty) {
          e['workDays'] = t('Pick at least one working day.');
        }
        // An end time before a start time is a silent problem: the booking
        // search computes capacity from these two, and a negative window makes
        // a carer look permanently unavailable with nothing on screen to say
        // why.
        final bad = <String>[];
        if (differentHours) {
          for (final d in workDays) {
            final h = dayHours[d] ?? DayHours(workFrom, workTo);
            if (!_after(h.to, h.from)) bad.add(t(d));
          }
        } else if (!_after(workTo, workFrom)) {
          bad.add('');
        }
        if (bad.isNotEmpty) {
          e['hours'] = bad.first.isEmpty
              ? t('The finish time has to be after the start time.')
              : t('On {day} the finish time has to be after the start time.',
                  {'day': bad.first});
        }
        if (expertise.isEmpty) e['expertise'] = t('Pick at least one service you provide.');
        break;
      case 2:
        if (!noFees) {
          final rate = double.tryParse(rateCtrl.text.trim());
          if (rate == null) {
            e['rate'] = isOrg
                ? t('Enter your standard hourly rate.')
                : t('Enter your hourly rate, or choose to give your time free.');
          } else if (rate < 50) {
            e['rate'] = t('The hourly rate looks too low. Enter the amount in rupees.');
          } else if (rate > 5000) {
            e['rate'] = t('The hourly rate looks too high. Enter the amount in rupees.');
          }
        }
        break;
      case 3:
        if (isOrg) {
          // An organisation proves it is registered; its carers prove who
          // they are, one at a time, on the screen that adds them.
          final gst = gstCtrl.text.trim();
          if (gst.isNotEmpty && !_gstRe.hasMatch(gst)) {
            e['gst'] = t('That does not look like a GST number.');
          }
          break;
        }
        if (aadharUrl == null) e['aadhar'] = t('Aadhar or work certificate is required.');
        if (policeUrl == null) {
          e['police'] = t('Police verification is required.');
        } else if (policeFrom == null || policeTo == null) {
          e['policeDates'] = t('Enter the dates the police verification is valid between.');
        } else if (!policeTo!.isAfter(policeFrom!)) {
          e['policeDates'] = t('The "to" date must be after the "from" date.');
        } else if (policeTo!.isBefore(DateTime.now())) {
          e['policeDates'] = t('This police verification has expired.');
        }
        // A medical certificate is only required of clinical services.
        final clinical =
            expertise.any((x) => x == ServiceType.nurse || x == ServiceType.physiotherapy);
        if (clinical && medicalUrl == null) {
          e['medical'] = t('A medical certificate is required for nursing and physiotherapy.');
        }
        if (medicalUrl != null && (medicalFrom == null || medicalTo == null)) {
          e['medicalDates'] = t('Enter the dates the medical certificate is valid between.');
        }
        break;
      case 4:
        final pin = pinCtrl.text.trim();
        if (pin.length != 6 || int.tryParse(pin) == null) {
          e['pin'] = t('The PIN must be exactly 6 digits.');
        } else if (RegExp(r'^(\d)\1{5}$').hasMatch(pin)) {
          e['pin'] = t('Choose a PIN that is not the same digit six times.');
        } else if (pin == '123456' || pin == '654321') {
          e['pin'] = t('That PIN is too easy to guess.');
        }
        break;
    }
    return e;
  }

  /// Moves on only if this step is complete; otherwise shows what is missing.
  void _next() {
    final errors = _validate(step);
    setState(() {
      fieldErrors = errors;
      error = errors.isEmpty
          ? null
          : errors.length == 1
              ? t('Please fix 1 field before continuing.')
              : t('Please fix {count} fields before continuing.', {'count': errors.length});
      if (errors.isEmpty) {
        step++;
        error = null;
      }
    });
  }

  /// Every step re-checked at submit, so a back-and-forth edit cannot slip a
  /// bad value past a step that was valid when it was left.
  bool _validateAll() {
    for (var i = 0; i < stepsTotal; i++) {
      final errors = _validate(i);
      if (errors.isNotEmpty) {
        setState(() {
          step = i;
          fieldErrors = errors;
          error = t('Something on this step still needs attention.');
        });
        return false;
      }
    }
    return true;
  }

  Widget _fieldError(String key) {
    final message = fieldErrors[key];
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 5, left: 2),
      child: Text(message,
          style: const TextStyle(color: SC.red, fontSize: 12.5, fontWeight: FontWeight.w600)),
    );
  }

  Future<void> finish() async {
    setState(() => busy = true);
    final draft = ProviderProfile(
      id: 'PROV-${100000 + DateTime.now().millisecond}',
      kind: kind,
      name: nameCtrl.text.trim(),
      // An organisation has neither, and storing a default made the admin
      // console show agencies as female with no date of birth.
      gender: isOrg ? '' : gender,
      dob: isOrg ? null : dob,
      contactPerson: isOrg ? contactCtrl.text.trim() : null,
      gstNumber: isOrg && gstCtrl.text.trim().isNotEmpty ? gstCtrl.text.trim() : null,
      mobile: mobileCtrl.text.trim(),
      email: emailCtrl.text.trim(),
      address: addressCtrl.text.trim(),
      lat: pinLat,
      lng: pinLng,
      languages: languages.toList(),
      // The hours somebody actually entered, not a hardcoded 09:00-18:00.
      // An organisation that named no days is open every day.
      //
      // Not a cosmetic default: the matching query inner-joins the work-hours
      // table, so an agency with no rows is never offered a booking and
      // nothing on any screen says why. The server applies the same fallback;
      // this is here so the profile screen shows what was actually stored.
      workPref: WorkPreference(
        days: (isOrg && workDays.isEmpty)
            ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
            : workDays.toList(),
        timeFrom: workFrom,
        timeTo: workTo,
        perDay: differentHours ? Map<String, DayHours>.from(dayHours) : {},
      ),
      expertise: expertise.toList(),
      hourlyRate: noFees ? null : double.tryParse(rateCtrl.text),
      noFees: noFees,
      aadhar: ProviderDocument(url: isOrg ? null : aadharUrl),
      policeVerification: isOrg
          ? ProviderDocument()
          : ProviderDocument(url: policeUrl, validFrom: policeFrom, validTo: policeTo),
      medicalCertificate: isOrg
          ? ProviderDocument()
          : ProviderDocument(url: medicalUrl, validFrom: medicalFrom, validTo: medicalTo),
      registrationCertificate: ProviderDocument(url: isOrg ? regCertUrl : null),
      pin: pinCtrl.text.trim(),
    );

    // Registration can fail for real reasons — a mobile number already
    // registered, a server that is unreachable. Without this the spinner ran
    // forever and the screen simply looked stuck.
    try {
      await Backend.instance.completeRegistration(draft);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = e.toString().replaceFirst('Exception: ', '');
      });
      return;
    }

    if (!mounted) return;
    setState(() => busy = false);

    // On a live server the account really is pending until an admin approves
    // it, and saying otherwise would be a lie. Only the offline demo waves it
    // through, so that a single device can explore the whole app.
    final live = Backend.isLive;
    if (!live) {
      Backend.instance.currentProvider!.approvalStatus = 'active';
      Backend.instance.currentProvider!.approved = true;
    }

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
              SuccessCheck(color: noFees ? SC.green : SC.blueBright),
              const SizedBox(height: 20),
              Text(noFees ? 'Thank you' : 'Registration sent', style: ST.h1,
                  textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Text(
                noFees
                    ? 'Your details are with Sathiyaa. Somebody checks your papers '
                        'before families can find you — and thank you for offering '
                        'your time.'
                    : live
                        ? 'Your details are saved. Somebody at Sathiyaa checks your '
                            'papers before families can find you in search. You can '
                            'sign in and finish your profile meanwhile.'
                        : 'Your details are saved and nothing has been charged. This '
                            'demo approves you straight away so you can look around.',
                style: ST.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const AppEntry()),
                      (r) => false,
                    );
                  },
                  child: Text(t('Continue')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
              title: isOrg ? t('Register your organisation') : t('Join Sathiyaa'),
              subtitle: t('Step {n} of {total}', {'n': step + 1, 'total': stepsTotal}),
              onBack: () {
                if (step == 0) {
                  Navigator.of(context).pop();
                } else {
                  setState(() => step--);
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(SC.gutter, 14, SC.gutter, 0),
            child: JourneyStepper(
              title: isOrg ? t('Organisation sign-up') : t('Registration'),
              steps: _steps,
              current: step,
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 18),
              children: [
                FadeSwitch(
                  child: KeyedSubtree(key: ValueKey(step), child: _stepBody()),
                ),
                if (error != null) ...[
                  const SizedBox(height: 16),
                  InlineError(message: error!),
                ],
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
                SC.gutter, 12, SC.gutter, 12 + MediaQuery.of(context).padding.bottom * 0.4),
            decoration: const BoxDecoration(
              color: SC.surface,
              border: Border(top: BorderSide(color: SC.hairline)),
            ),
            child: Row(
              children: [
                if (step > 0) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : () => setState(() => step--),
                      child: Text(t('Back')),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: GradientButton(
                    label: step == stepsTotal - 1 ? 'Submit' : 'Next',
                    icon: step == stepsTotal - 1
                        ? Icons.check_rounded
                        : Icons.arrow_forward_rounded,
                    busy: busy,
                    height: 52,
                    onPressed: busy ? null : (step == stepsTotal - 1 ? _submit : _next),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepBody() {
    switch (step) {
      case 0:
        return _stepYou();
      case 1:
        return _stepWork();
      case 2:
        return _stepPay();
      case 3:
        return _stepPapers();
      case 4:
      default:
        return _stepPin();
    }
  }

  // ---- step 0: you ----------------------------------------------------

  Widget _stepYou() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(t('Are you registering as')),
        Row(
          children: [
            Expanded(
              child: _choiceCard(
                selected: kind == ProviderKind.freelancer,
                icon: Icons.person_rounded,
                title: t('Myself'),
                onTap: () => setState(() => kind = ProviderKind.freelancer),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _choiceCard(
                selected: kind == ProviderKind.organization,
                icon: Icons.business_rounded,
                title: t('An organisation'),
                onTap: () => setState(() => kind = ProviderKind.organization),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        FieldLabel(isOrg ? t('Organisation name') : t('Full name'), required: true),
        TextField(
          controller: nameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: isOrg ? t('e.g. CareWell Health Services') : t('e.g. Lalita Menon'),
            errorText: fieldErrors['name'],
          ),
          onChanged: (_) => _clearError('name'),
        ),

        // An organisation has no gender and no date of birth. Asking for them
        // was not just noise -- it produced records saying an agency was
        // female and born in 1994, which is then what an admin sees.
        if (isOrg) ...[
          const SizedBox(height: 16),
          FieldLabel(t('Person we should speak to'), required: true),
          TextField(
            controller: contactCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: t('Name of the manager or owner'),
              errorText: fieldErrors['contact'],
            ),
            onChanged: (_) => _clearError('contact'),
          ),
        ] else ...[
          const SizedBox(height: 16),
          FieldLabel(t('Gender')),
          _dropdown(gender, const ['Female', 'Male', 'Other'], (v) => setState(() => gender = v)),
        ],
        const SizedBox(height: 16),
        FieldLabel(isOrg ? t('Office mobile number') : t('Mobile number'), required: true),
        TextField(
          controller: mobileCtrl,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          decoration: InputDecoration(
            hintText: t('10 digits, no country code'),
            counterText: '',
            errorText: fieldErrors['mobile'],
          ),
          onChanged: (_) => _clearError('mobile'),
        ),
        if (!isOrg) ...[
          const SizedBox(height: 16),
          // Optional. It was required, and it is the field that stopped people
          // finishing: plenty of carers do not carry a document with their
          // date of birth on it, and an age is not what verifies anybody here
          // -- the police check and the Aadhaar are. It is still asked for,
          // because it is useful, and still refused if it makes somebody
          // under 18.
          FieldLabel(t('Date of birth')),
          PressableScale(
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: dob ?? DateTime(now.year - 30),
                firstDate: DateTime(now.year - 80),
                lastDate: DateTime(now.year - 18),
                helpText: 'Date of birth',
              );
              if (picked != null) {
                setState(() {
                  dob = picked;
                  _clearError('dob');
                });
              }
            },
            child: _pickerBox(
              Icons.cake_rounded,
              dob == null ? t('Optional — tap to choose') : prettyDate(dob!),
              muted: dob == null,
            ),
          ),
          _fieldError('dob'),
        ],
        const SizedBox(height: 16),
        FieldLabel(t('Email')),
        TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: t('Optional'),
            errorText: fieldErrors['email'],
          ),
          onChanged: (_) => _clearError('email'),
        ),
      ],
    );
  }

  // ---- step 1: work ---------------------------------------------------

  Widget _stepWork() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Which address, said plainly. "Address you work from" was ambiguous
        // for a freelancer (home? the family's house?) and meaningless for an
        // organisation, which has an office and carers living all over the
        // city.
        FieldLabel(isOrg ? t('Registered office address') : t('Your home address'),
            required: true),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            isOrg
                ? t('Where the organisation is based. Each carer\'s own address is asked for when you add them.')
                : t('Where you set out from. Sathiyaa measures the distance to a family from here, so it decides which visits you are offered.'),
            style: ST.small,
          ),
        ),
        TextField(
          controller: addressCtrl,
          maxLines: 2,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: t('House / street, area, city'),
            errorText: fieldErrors['address'],
          ),
          onChanged: (_) => _clearError('address'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: locating ? null : _useCurrentLocation,
          icon: locating
              ? const SizedBox(
                  width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.my_location_rounded, size: 18),
          label: Text(locating ? 'Finding you…' : 'Use my current location'),
        ),
        if (locationNote != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 2),
            child: Text(
              locationNote!,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: locationFailed ? SC.red : SC.green),
            ),
          ),
        const SizedBox(height: 14),
        // A real map, so the pin can be checked rather than taken on trust.
        OsmMap(
          lat: pinLat,
          lng: pinLng,
          label: t('Where you work from'),
          height: 160,
          onLocated: (la, ln) => setState(() {
            pinLat = la;
            pinLng = ln;
          }),
        ),
        const SizedBox(height: 22),
        FieldLabel(isOrg ? t('Days the organisation operates') : t('Days you work'),
            required: !isOrg),
        if (isOrg)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              t('Optional. Leave it blank and we will take the organisation as open every day. Each carer sets their own days when you add them, and that is what a family is matched against.'),
              style: ST.small,
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((d) {
            final sel = workDays.contains(d);
            return _pill(t(d), sel, () {
              setState(() {
                sel ? workDays.remove(d) : workDays.add(d);
                _clearError('workDays');
              });
            });
          }).toList(),
        ),
        _fieldError('workDays'),
        const SizedBox(height: 18),
        _hoursSection(),
        const SizedBox(height: 22),
        FieldLabel(isOrg ? t('Care the organisation provides') : t('Care you can give'),
            required: true),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ServiceType.values.map((s) {
            final sel = expertise.contains(s);
            return _pill(s.label, sel, () {
              setState(() {
                sel ? expertise.remove(s) : expertise.add(s);
                _clearError('expertise');
              });
            });
          }).toList(),
        ),
        _fieldError('expertise'),
      ],
    );
  }

  // ---- step 2: pay ----------------------------------------------------

  /// The volunteer decision.
  ///
  /// This was a switch labelled "No Fees (donated / volunteer service)" with
  /// no explanation of what it meant. Choosing to work unpaid deserves more
  /// than a toggle, so it is two cards that say plainly what each one means —
  /// including that giving your time free earns nothing back, which is the
  /// truth and is the point.
  Widget _stepPay() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Only a person can choose to give their time away. An organisation
        // pays wages, so "how would you like to work?" had exactly one honest
        // answer for them and the question was noise on the form.
        if (!isOrg) ...[
          FieldLabel(t('How would you like to work?'), required: true),
          _payChoice(
            selected: !noFees,
            icon: Icons.payments_rounded,
            title: t('I charge for my time'),
            body: t('You set an hourly rate. Families pay it, and Sathiyaa adds its '
                'own share on top — you receive the rate you enter.'),
            onTap: () => setState(() => noFees = false),
          ),
          const SizedBox(height: 12),
          _payChoice(
            selected: noFees,
            icon: Icons.favorite_rounded,
            title: t('I give my time free'),
            body: t('Families are charged nothing for your visits, and nothing is owed '
                'to you — no points, no rewards. Sathiyaa keeps a record of your hours, '
                'and says thank you.'),
            tone: SC.green,
            onTap: () => setState(() {
              noFees = true;
              _clearError('rate');
            }),
          ),
        ],
        if (!noFees) ...[
          if (!isOrg) const SizedBox(height: 22),
          FieldLabel(isOrg ? t('Your standard hourly rate') : t('Your hourly rate'),
              required: true),
          if (isOrg)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                t('What a family pays per hour for a carer from your organisation. You can set a different rate per carer once you are approved.'),
                style: ST.small,
              ),
            ),
          TextField(
            controller: rateCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: t('e.g. 450'),
              prefixText: '₹ ',
              errorText: fieldErrors['rate'],
            ),
            onChanged: (_) => _clearError('rate'),
          ),
          const SizedBox(height: 8),
          Text(
            t('Most companions charge ₹180–250 an hour, nurses ₹400–500, physiotherapists ₹550–650.'),
            style: ST.small,
          ),
        ],
      ],
    );
  }

  Widget _payChoice({
    required bool selected,
    required IconData icon,
    required String title,
    required String body,
    required VoidCallback onTap,
    Color tone = SC.blueBright,
  }) {
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Dur.quick,
        curve: Ease.standard,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? tone.withValues(alpha: 0.07) : SC.surface,
          borderRadius: BorderRadius.circular(SC.rCard),
          border: Border.all(color: selected ? tone : SC.hairline, width: selected ? 1.8 : 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected ? tone.withValues(alpha: 0.14) : SC.sunkTint,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, size: 21, color: selected ? tone : SC.inkFaint),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: ST.h3),
                  const SizedBox(height: 5),
                  Text(body, style: ST.small.copyWith(height: 1.5)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            AnimatedContainer(
              duration: Dur.quick,
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? tone : Colors.transparent,
                border: Border.all(
                    color: selected ? tone : SC.hairlineCool, width: 2),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // ---- step 3: papers -------------------------------------------------

  Widget _stepPapers() {
    if (isOrg) return _stepOrgPapers();
    final clinical =
        expertise.any((x) => x == ServiceType.nurse || x == ServiceType.physiotherapy);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(t('Your papers')),
        Text(
          t('A family deciding who to let into their home is trusting Sathiyaa to have checked these. Photograph each one with your camera, or pick a scan you already have.'),
          style: ST.body,
        ),
        const SizedBox(height: 6),
        Text(
          t('Nothing is sent until you finish the last step, so you can change any of them before then.'),
          style: ST.small,
        ),
        const SizedBox(height: 18),

        DocumentField(
          label: t('Aadhar or work certificate'),
          category: 'aadhar',
          required: true,
          hint: t('Either side, as long as your name and photo are readable.'),
          url: aadharUrl,
          errorText: fieldErrors['aadhar'],
          onChanged: (u) => setState(() {
            aadharUrl = u;
            _clearError('aadhar');
          }),
        ),

        DocumentField(
          label: t('Police verification'),
          category: 'police-verification',
          required: true,
          hint: t('The certificate from your local station. We need the dates on it as well, so make sure they are in the photo.'),
          url: policeUrl,
          errorText: fieldErrors['police'],
          onChanged: (u) => setState(() {
            policeUrl = u;
            _clearError('police');
          }),
        ),
        // The dates belong to the document above, so they only appear once
        // there is one, and they are indented to show what they attach to.
        if (policeUrl != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dateRangeRow('Valid between', policeFrom, policeTo,
                    (f, t) => setState(() {
                          policeFrom = f;
                          policeTo = t;
                          _clearError('policeDates');
                        })),
                _fieldError('policeDates'),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],

        DocumentField(
          label: t('Medical certificate'),
          category: 'medical-certificate',
          required: clinical,
          hint: clinical
              ? 'Required because you offer nursing or physiotherapy.'
              : 'Optional for companion work. Add it if you have one.',
          url: medicalUrl,
          errorText: fieldErrors['medical'],
          onChanged: (u) => setState(() {
            medicalUrl = u;
            _clearError('medical');
          }),
        ),
        if (medicalUrl != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dateRangeRow('Valid between', medicalFrom, medicalTo,
                    (f, t) => setState(() {
                          medicalFrom = f;
                          medicalTo = t;
                          _clearError('medicalDates');
                        })),
                _fieldError('medicalDates'),
              ],
            ),
          ),
      ],
    );
  }

  /// What an organisation is asked for instead.
  ///
  /// Nobody runs a police check on a company and an Aadhaar card does not
  /// belong to one, so asking an agency for both produced either a refusal to
  /// finish or -- worse -- one director's documents standing in for every
  /// carer the agency would go on to send. The verification that matters for
  /// an agency is that the agency is registered; the verification that
  /// matters for the people entering a home is collected per carer, on the
  /// screen where a carer is added.
  Widget _stepOrgPapers() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(t('Proof of registration')),
        Text(
          t('One document showing the organisation exists and is registered — a certificate of incorporation, a shops and establishment licence, or a society or trust registration. Add it now if you have it, or later from your profile.'),
          style: ST.body,
        ),
        const SizedBox(height: 18),
        DocumentField(
          label: t('Registration certificate'),
          category: 'org-registration',
          // Not required to finish registering. An agency that has just been
          // set up may not have the certificate to hand on the evening it
          // signs up, and losing that registration entirely is worse than
          // reviewing it later -- the account is pending until Sathiyaa looks
          // at it either way, and that is when the document is chased.
          required: false,
          hint: t('Photograph it or pick a scan. The name on it must match the organisation name you entered. You can add it later from your profile.'),
          url: regCertUrl,
          errorText: fieldErrors['regCert'],
          onChanged: (u) => setState(() {
            regCertUrl = u;
            _clearError('regCert');
          }),
        ),
        if (regCertUrl == null)
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 4),
            child: Text(
              t('Without it your organisation can register, but it cannot be approved — and until it is approved your carers cannot be sent to families.'),
              style: ST.small.copyWith(height: 1.45),
            ),
          ),
        const SizedBox(height: 6),
        FieldLabel(t('GST number')),
        TextField(
          controller: gstCtrl,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: t('Optional — leave blank if you are not registered'),
            errorText: fieldErrors['gst'],
          ),
          onChanged: (_) => _clearError('gst'),
        ),
        const SizedBox(height: 22),

        // Said here rather than discovered later, because it changes what an
        // organisation has to collect before its carers can be sent anywhere.
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: SC.blueTint,
            borderRadius: BorderRadius.circular(SC.rCard),
            border: Border.all(color: SC.hairlineCool),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.groups_rounded, size: 20, color: SC.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('Your carers are verified one by one'), style: ST.h3),
                    const SizedBox(height: 5),
                    Text(
                      t('Aadhaar and police verification are collected for each carer when you add them, not here. A carer without them cannot be sent to a family.'),
                      style: ST.small.copyWith(height: 1.5),
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

  // ---- the hours somebody actually works -------------------------------

  String _fmt(TimeOfDay v) =>
      '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}';

  TimeOfDay _parse(String v) {
    final bits = v.split(':');
    return TimeOfDay(hour: int.tryParse(bits.first) ?? 9, minute: int.tryParse(bits.last) ?? 0);
  }

  Future<void> _pickTime(String current, ValueChanged<String> onPicked) async {
    final picked = await showTimePicker(context: context, initialTime: _parse(current));
    if (picked != null) onPicked(_fmt(picked));
  }

  Widget _timeBox(String value, ValueChanged<String> onPicked) {
    return Expanded(
      child: PressableScale(
        onTap: () => _pickTime(value, (v) {
          setState(() {
            onPicked(v);
            _clearError('hours');
          });
        }),
        child: _pickerBox(Icons.schedule_rounded, value),
      ),
    );
  }

  Widget _hoursSection() {
    final ordered = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        .where(workDays.contains)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(isOrg ? t('Hours the organisation operates') : t('Hours you work'),
            required: !isOrg),
        if (!differentHours) ...[
          Row(
            children: [
              _timeBox(workFrom, (v) => workFrom = v),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('–', style: ST.bodyStrong),
              ),
              _timeBox(workTo, (v) => workTo = v),
            ],
          ),
        ] else ...[
          if (ordered.isEmpty)
            Text(t('Pick the days above first.'), style: ST.small)
          else
            for (final d in ordered)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(width: 46, child: Text(t(d), style: ST.bodyStrong)),
                    _timeBox(
                      (dayHours[d] ?? DayHours(workFrom, workTo)).from,
                      (v) => dayHours[d] = DayHours(v, (dayHours[d] ?? DayHours(workFrom, workTo)).to),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('–', style: ST.bodyStrong),
                    ),
                    _timeBox(
                      (dayHours[d] ?? DayHours(workFrom, workTo)).to,
                      (v) => dayHours[d] = DayHours((dayHours[d] ?? DayHours(workFrom, workTo)).from, v),
                    ),
                  ],
                ),
              ),
        ],
        _fieldError('hours'),
        const SizedBox(height: 4),
        // A switch rather than two modes on the form, because the common case
        // is one window and the seven-row version should cost a deliberate
        // tap rather than being what everybody meets first.
        InkWell(
          onTap: () => setState(() {
            differentHours = !differentHours;
            if (differentHours && dayHours.isEmpty) {
              for (final d in ordered) {
                dayHours[d] = DayHours(workFrom, workTo);
              }
            }
            if (!differentHours) dayHours.clear();
          }),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 24,
                  child: Switch.adaptive(
                    value: differentHours,
                    activeThumbColor: SC.blueBright,
                    onChanged: (v) => setState(() {
                      differentHours = v;
                      if (v && dayHours.isEmpty) {
                        for (final d in ordered) {
                          dayHours[d] = DayHours(workFrom, workTo);
                        }
                      }
                      if (!v) dayHours.clear();
                    }),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(t('Different hours on some days'), style: ST.body),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---- step 4: pin ----------------------------------------------------

  Widget _stepPin() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(t('Choose a PIN')),
        Text(
          t('Six digits. You will use it with your mobile number every time you sign in.'),
          style: ST.body,
        ),
        const SizedBox(height: 18),
        TextField(
          controller: pinCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          obscureText: true,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 8),
          decoration: InputDecoration(
            counterText: '',
            errorText: fieldErrors['pin'],
          ),
          onChanged: (_) => _clearError('pin'),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: SC.amberTint,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF0DCBC)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFA9670F)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t('Nothing is charged to register — no payment provider is connected yet. Submitting sends your details to Sathiyaa for checking.'),
                  style: ST.small.copyWith(color: const Color(0xFF8A5510), height: 1.45),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---- small pieces ---------------------------------------------------

  Widget _choiceCard({
    required bool selected,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Dur.quick,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? SC.blueBright : SC.surface,
          borderRadius: BorderRadius.circular(SC.rCard),
          border: Border.all(color: selected ? SC.blueBright : SC.hairline),
        ),
        child: Column(
          children: [
            Icon(icon, size: 24, color: selected ? Colors.white : SC.blueBright),
            const SizedBox(height: 9),
            Text(title,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : SC.ink,
                )),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, bool selected, VoidCallback onTap) {
    return PressableScale(
      onTap: onTap,
      scale: 0.94,
      child: AnimatedContainer(
        duration: Dur.micro,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? SC.blueBright : SC.surface,
          borderRadius: BorderRadius.circular(SC.rPill),
          border: Border.all(color: selected ? SC.blueBright : SC.hairline),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : SC.ink,
            )),
      ),
    );
  }

  Widget _pickerBox(IconData icon, String text, {bool muted = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      decoration: BoxDecoration(
        color: SC.surface,
        borderRadius: BorderRadius.circular(SC.rField),
        border: Border.all(color: SC.hairline),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: SC.blueBright),
          const SizedBox(width: 11),
          Expanded(
            child: Text(text,
                style: muted ? ST.body.copyWith(color: SC.inkFaint) : ST.bodyStrong),
          ),
          const Icon(Icons.expand_more_rounded, size: 19, color: SC.inkFaint),
        ],
      ),
    );
  }

  Widget _dropdown(String value, List<String> options, ValueChanged<String> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: SC.surface,
        borderRadius: BorderRadius.circular(SC.rField),
        border: Border.all(color: SC.hairline),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
          style: ST.bodyStrong,
          icon: const Icon(Icons.expand_more_rounded, color: SC.inkFaint),
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: (v) => onChanged(v!),
        ),
      ),
    );
  }

  Widget _dateRangeRow(
      String label, DateTime? from, DateTime? to, void Function(DateTime?, DateTime?) onChange) {
    String fmt(DateTime? d) => d == null ? '' : prettyDate(d);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(label, required: true),
          Row(
            children: [
              Expanded(
                child: PressableScale(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: from ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                      helpText: 'Valid from',
                    );
                    if (picked != null) onChange(picked, to);
                  },
                  child: _pickerBox(Icons.calendar_today_rounded,
                      from == null ? 'From' : fmt(from),
                      muted: from == null),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PressableScale(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: to ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                      helpText: 'Valid to',
                    );
                    if (picked != null) onChange(from, picked);
                  },
                  child: _pickerBox(Icons.event_rounded, to == null ? 'To' : fmt(to),
                      muted: to == null),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
