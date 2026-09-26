import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../backend.dart';
import '../city_defaults.dart';
import '../models.dart';
import '../services/location_service.dart';
import '../services/geocode.dart';
import '../theme/sathiyaa_theme.dart';
import '../utils/dates.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import '../widgets/osm_map.dart';
import '../widgets/sathiyaa_ui.dart';
import '../i18n/l10n.dart';

/// The editable half of the customer profile: identity, body metrics, the two
/// addresses, and how the customer wants to be contacted.
///
/// This is the one screen a customer genuinely has to fill in, so it does three
/// things the first version did not. It says at the top how much is left. It
/// marks a missing mandatory field in place, beside the field, instead of
/// posting the form and repeating whatever the server complained about. And it
/// asks before throwing away a half-finished form, because this is a long one
/// and a back-swipe used to cost the lot.
class BasicDetailsScreen extends StatefulWidget {
  const BasicDetailsScreen({super.key});

  @override
  State<BasicDetailsScreen> createState() => _BasicDetailsScreenState();
}

const _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
const _genders = ['Female', 'Male', 'Other'];
const _allLanguages = [
  'English', 'Hindi', 'Gujarati', 'Marathi', 'Tamil',
  'Telugu', 'Malayalam', 'Urdu', 'Bengali',
];
const _timeframePresets = ['Any time', '09:00-13:00', '13:00-18:00', '18:00-21:00'];

/// How each mode is said mid-sentence. Lower-casing the chip labels turned
/// "SMS" into "sms", which reads as a typo.
const _spokenMode = {
  ContactMode.email: 'email',
  ContactMode.call: 'a phone call',
  ContactMode.sms: 'SMS',
};
/// A BMI figure on its own means nothing to most people, so the band is spelled
/// out beside it. These are the WHO adult cut-offs.
({String word, Color tone}) _bmiBand(double bmi) {
  if (bmi < 18.5) return (word: 'Underweight', tone: SC.amber);
  if (bmi < 25) return (word: 'Healthy range', tone: SC.green);
  if (bmi < 30) return (word: 'Overweight', tone: SC.amber);
  return (word: 'Obese', tone: SC.red);
}

bool _sameSet<T>(Set<T> a, Set<T> b) => a.length == b.length && a.containsAll(b);

class _BasicDetailsScreenState extends State<BasicDetailsScreen> {
  late final Customer c = Backend.instance.currentCustomer!;

  late final nameCtrl = TextEditingController(text: c.name);
  late final emailCtrl = TextEditingController(text: c.email ?? '');
  late final heightCtrl = TextEditingController(text: c.heightCm?.toStringAsFixed(0) ?? '');
  late final weightCtrl = TextEditingController(text: c.weightKg?.toStringAsFixed(0) ?? '');

  late DateTime? dob = c.dob;
  late String? gender = c.gender;
  late String? bloodGroup = c.bloodGroup;
  late Set<String> languages = c.preferredLanguages.toSet();
  late String? photoPath = c.photoUrl;

  // Addresses — primary is mandatory, secondary optional.
  late final Address _primarySeed = Backend.instance.primaryAddress() ??
      Address(label: t('Primary'), line1: '', city: '', lat: kDefaultLat, lng: kDefaultLng, isPrimary: true);
  late final Address? _secondarySeed =
      c.addresses.where((a) => !a.isPrimary).cast<Address?>().firstWhere((a) => true, orElse: () => null);

  late final pLine = TextEditingController(text: _primarySeed.line1);
  late final pCity = TextEditingController(text: _primarySeed.city);
  late final sLine = TextEditingController(text: _secondarySeed?.line1 ?? '');
  late final sCity = TextEditingController(text: _secondarySeed?.city ?? '');

  /// Where the primary address pin sits. Seeded from whatever is saved, and
  /// moved by "Use my current location" or the map's own crosshair.
  late double _pinLat = _primarySeed.lat;
  late double _pinLng = _primarySeed.lng;
  bool _locating = false;
  String? _locationNote;
  bool _locationFailed = false;

  /// Call is ticked by default.
  ///
  /// Not a cosmetic default: this field decides how a family hears that a
  /// carer has accepted, and an empty set is a validation error standing
  /// between somebody and the Save button on a form they have otherwise
  /// finished. A phone call is what nearly everyone picks, and it is the one
  /// channel that works without an email address or a data connection.
  /// Somebody who wants SMS or email instead unticks it in one tap.
  late Set<ContactMode> contactModes =
      c.contactModes.isEmpty ? {ContactMode.call} : c.contactModes.toSet();
  late final timeframeCtrl = TextEditingController(text: c.contactTimeframe ?? '');

  /// The second address starts folded away unless one is already saved. Most
  /// people have one address and should not have to scroll past a second empty
  /// pair of fields to reach Save.
  late bool _showSecondary = (_secondarySeed?.line1 ?? '').isNotEmpty;

  bool _saving = false;
  String? _error;

  /// Set once the customer has pressed Save. Before that nothing is marked in
  /// red — a form that scolds you about a field you have not reached yet is
  /// just noise.
  bool _triedSave = false;

  final _scroll = ScrollController();
  final _photoKey = GlobalKey();
  final _nameKey = GlobalKey();
  final _dobKey = GlobalKey();
  final _genderKey = GlobalKey();
  final _addressKey = GlobalKey();

  // Cached so the per-keystroke listener rebuilds only when something visible
  // actually changes, rather than on every letter of a street name.
  bool _lastDirty = false;
  Set<String> _lastFlags = const {};

  @override
  void initState() {
    super.initState();
    for (final ctrl in [nameCtrl, emailCtrl, pLine, pCity, sLine, sCity, timeframeCtrl]) {
      ctrl.addListener(_onEdit);
    }
  }

  @override
  void dispose() {
    for (final ctrl in [nameCtrl, emailCtrl, pLine, pCity, sLine, sCity, timeframeCtrl]) {
      ctrl.removeListener(_onEdit);
    }
    for (final ctrl in [nameCtrl, emailCtrl, heightCtrl, weightCtrl, pLine, pCity, sLine, sCity, timeframeCtrl]) {
      ctrl.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _onEdit() {
    if (!mounted) return;
    final dirty = _dirty;
    final flags = _problemIds;
    if (dirty != _lastDirty || !_sameSet(flags, _lastFlags)) {
      setState(() {
        _lastDirty = dirty;
        _lastFlags = flags;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // What is still missing
  // ---------------------------------------------------------------------------

  /// The mandatory fields, in the order they appear on screen. The same list
  /// drives the meter in the header, the red marks, and the message above the
  /// Save button, so the three can never disagree with each other.
  List<({String id, GlobalKey key, String what})> get _problems => [
        if (!hasImage(photoPath)) (id: 'photo', key: _photoKey, what: 'a photo'),
        if (nameCtrl.text.trim().isEmpty) (id: 'name', key: _nameKey, what: 'your name'),
        if (dob == null) (id: 'dob', key: _dobKey, what: 'your date of birth'),
        if (gender == null) (id: 'gender', key: _genderKey, what: 'your gender'),
        if (pLine.text.trim().isEmpty || pCity.text.trim().isEmpty)
          (id: 'address', key: _addressKey, what: 'your home address'),
      ];

  Set<String> get _problemIds => _problems.map((p) => p.id).toSet();

  static const _requiredCount = 5;

  /// Red marks only appear after a save attempt, and clear themselves the
  /// moment the field is filled in.
  bool _missing(String id) => _triedSave && _problemIds.contains(id);

  bool get _dirty =>
      nameCtrl.text != c.name ||
      emailCtrl.text != (c.email ?? '') ||
      photoPath != c.photoUrl ||
      dob != c.dob ||
      gender != c.gender ||
      bloodGroup != c.bloodGroup ||
      !_sameSet(languages, c.preferredLanguages.toSet()) ||
      heightCtrl.text != (c.heightCm?.toStringAsFixed(0) ?? '') ||
      weightCtrl.text != (c.weightKg?.toStringAsFixed(0) ?? '') ||
      pLine.text != _primarySeed.line1 ||
      pCity.text != _primarySeed.city ||
      _pinLat != _primarySeed.lat ||
      _pinLng != _primarySeed.lng ||
      sLine.text != (_secondarySeed?.line1 ?? '') ||
      sCity.text != (_secondarySeed?.city ?? '') ||
      !_sameSet(contactModes, c.contactModes.toSet()) ||
      timeframeCtrl.text != (c.contactTimeframe ?? '');

  double? get _liveBmi {
    final h = double.tryParse(heightCtrl.text);
    final w = double.tryParse(weightCtrl.text);
    if (h == null || w == null || h <= 0) return null;
    return w / ((h / 100) * (h / 100));
  }

  int? get _age {
    if (dob == null) return null;
    final now = DateTime.now();
    var age = now.year - dob!.year;
    if (now.month < dob!.month || (now.month == dob!.month && now.day < dob!.day)) age--;
    return age;
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Asks the phone for a position and drops the pin there.
  ///
  /// Typing a street name never set any coordinates, so an address saved from
  /// this screen kept whatever the default city was — and the search that runs
  /// from it looked in the wrong place.
  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _locationNote = null;
      _locationFailed = false;
    });
    final fix = await LocationService.current();
    if (!mounted) return;
    if (!fix.isOk) {
      setState(() {
        _locating = false;
        _locationFailed = true;
        _locationNote = fix.error;
      });
      return;
    }

    setState(() {
      _pinLat = fix.lat!;
      _pinLng = fix.lng!;
      _locationFailed = false;
      _locationNote = t('Finding your address…');
    });

    // The pin is already right, so this is a bonus rather than a step: if the
    // lookup fails the note goes back to describing the pin and nothing is
    // lost.
    final place = await Geocode.reverse(fix.lat!, fix.lng!);
    if (!mounted) return;
    setState(() {
      _locating = false;
      final pinNote = t('Pin set to where you are now — accurate to about {m} m.',
          {'m': fix.accuracyMetres!.round()});
      if (place == null || place.isEmpty) {
        _locationNote = pinNote;
        return;
      }
      // Only into empty boxes. Overwriting an address somebody typed, because
      // they tapped a button to move a pin, is not a helpful surprise.
      final filled = <String>[];
      if (pLine.text.trim().isEmpty && place.line1.isNotEmpty) {
        pLine.text = place.line1;
        filled.add(t('address'));
      }
      if (pCity.text.trim().isEmpty && place.city.isNotEmpty) {
        pCity.text = place.city;
        filled.add(t('city'));
      }
      _locationNote = filled.isEmpty
          ? t('{pin} Your address is already filled in, so nothing was changed.',
              {'pin': pinNote})
          : t('{pin} We filled in your {what} — check it and correct anything wrong.',
              {'pin': pinNote, 'what': filled.join(t(' and '))});
    });
  }

  Future<void> _pickPhoto() async {
    final hasOne = hasImage(photoPath);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: SC.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: SC.hairlineCool,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(SC.gutter, 8, SC.gutter, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(t('Your photo'), style: ST.h2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: SC.blueBright),
              title: Text(t('Choose from gallery'), style: ST.bodyStrong),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded, color: SC.blueBright),
              title: Text(t('Take a photo'), style: ST.bodyStrong),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            if (hasOne)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: SC.red),
                title: Text(t('Remove photo'),
                    style: const TextStyle(fontWeight: FontWeight.w700, color: SC.red)),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (choice == 'remove') {
      setState(() => photoPath = null);
      return;
    }
    try {
      final file = await ImagePicker().pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (file != null && mounted) setState(() => photoPath = file.path);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open the camera or gallery: $e');
    }
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: dob ?? DateTime(1960),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      helpText: 'Your date of birth',
    );
    if (picked != null) setState(() => dob = picked);
  }

  Future<bool> _confirmDiscard() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: SC.surface,
        title: Text(t('Leave without saving?'), style: ST.h2),
        content: Text(t('The changes you made here will be lost.'), style: ST.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('Keep editing')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: SC.red),
            child: Text(t('Discard')),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  Future<void> _save() async {
    setState(() => _triedSave = true);

    // Everything mandatory is checked here rather than at the server, so the
    // customer is told which field, beside the field, and not after a round
    // trip that leaves them at the top of the form guessing.
    final problems = _problems;
    if (problems.isNotEmpty) {
      final ctx = problems.first.key.currentContext;
      if (ctx != null) {
        await Scrollable.ensureVisible(
          ctx,
          duration: Dur.normal,
          curve: Ease.enter,
          alignment: 0.15,
        );
      }
      if (mounted) {
        setState(() => _error = 'Still needed: ${problems.map((p) => p.what).join(', ')}.');
      }
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Backend.instance.updateBasicDetails(
        name: nameCtrl.text.trim(),
        email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
        photoPath: photoPath,
        dob: dob,
        gender: gender,
        bloodGroup: bloodGroup,
        languages: languages.toList(),
        heightCm: double.tryParse(heightCtrl.text),
        weightKg: double.tryParse(weightCtrl.text),
      );
      await Backend.instance.saveAddresses(
        primary: Address(
          label: t('Primary'),
          line1: pLine.text.trim(),
          city: pCity.text.trim(),
          lat: _pinLat,
          lng: _pinLng,
          isPrimary: true,
        ),
        secondary: sLine.text.trim().isEmpty
            ? null
            : Address(
                label: t('Secondary'),
                line1: sLine.text.trim(),
                city: sCity.text.trim(),
                lat: _secondarySeed?.lat ?? kDefaultLat,
                lng: _secondarySeed?.lng ?? kDefaultLng,
              ),
      );
      await Backend.instance.setContactPreference(
        modes: contactModes,
        timeframe: timeframeCtrl.text.trim().isEmpty ? null : timeframeCtrl.text.trim(),
      );
      if (!mounted) return;
      // The messenger and navigator are captured before the awaits above: this
      // context is gone the moment we pop, and reading either off it then is
      // how you get a "looked up a deactivated widget" crash.
      messenger.showSnackBar(SnackBar(content: Text(t('Profile saved.'))));
      navigator.pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !mounted) return;
        // Taken before the await: after it this context may be gone, and
        // reading a Navigator off a dead context is a crash, not a warning.
        final navigator = Navigator.of(context);
        final leave = await _confirmDiscard();
        if (leave && mounted) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: SC.paper,
        body: Column(
          children: [
            _header(),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 26),
                children: staggered([
                  _identity(),
                  _languageSection(),
                  _metrics(),
                  _addresses(),
                  _contact(),
                ]),
              ),
            ),
            _saveBar(),
          ],
        ),
      ),
    );
  }

  /// The header carries the meter. Coming here from the "Still needed" note on
  /// the profile, the first thing you want to know is how much is left.
  Widget _header() {
    final left = _problems.length;
    final done = _requiredCount - left;

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
                  icon: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 30),
                ),
                Expanded(
                  child: Text(
                    t('Basic details'),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 0, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        left == 0 ? Icons.check_circle_rounded : Icons.donut_large_rounded,
                        size: 15,
                        color: left == 0 ? const Color(0xFF7BE0A6) : SC.gold,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          left == 0
                              ? 'Everything we need is filled in'
                              : left == 1
                                  ? '1 thing still needed'
                                  : '$left things still needed',
                          style: const TextStyle(color: Colors.white70, fontSize: 13.5),
                        ),
                      ),
                      Text('$done/$_requiredCount',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: done / _requiredCount),
                    duration: Dur.slow,
                    curve: Ease.enter,
                    builder: (_, v, __) => ClipRRect(
                      borderRadius: BorderRadius.circular(SC.rPill),
                      child: LinearProgressIndicator(
                        value: v,
                        minHeight: 6,
                        backgroundColor: Colors.white.withValues(alpha: 0.18),
                        valueColor: AlwaysStoppedAnimation(
                            left == 0 ? const Color(0xFF7BE0A6) : SC.gold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- section 1: who you are -------------------------------------------------

  Widget _identity() => _section(
        'Who you are',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _photoRow(),
            const SizedBox(height: 18),
            Container(key: _nameKey),
            FieldLabel(t('Full name'), required: true),
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: t('As it appears on your ID'),
                errorText: _missing('name') ? 'We need a name to put on the booking' : null,
              ),
            ),
            const SizedBox(height: 16),
            Container(key: _dobKey),
            FieldLabel(t('Date of birth'), required: true),
            _tappableField(
              icon: Icons.cake_rounded,
              text: dob == null ? 'Choose your date of birth' : prettyDate(dob!),
              trailing: dob == null ? null : 'age $_age',
              placeholder: dob == null,
              flagged: _missing('dob'),
              onTap: _pickDob,
            ),
            if (_missing('dob')) _hint('A carer needs to know who they are visiting.', tone: SC.redDeep),
            const SizedBox(height: 16),
            Container(key: _genderKey),
            FieldLabel(t('Gender'), required: true),
            Row(
              children: [
                for (final g in _genders) ...[
                  Expanded(
                    child: _choice(
                      label: g,
                      on: gender == g,
                      flagged: _missing('gender'),
                      onTap: () => setState(() => gender = g),
                    ),
                  ),
                  if (g != _genders.last) const SizedBox(width: 9),
                ],
              ],
            ),
            if (_missing('gender'))
              _hint('Many families ask for a carer of a particular gender.', tone: SC.redDeep),
            const SizedBox(height: 16),
            FieldLabel(t('Blood group')),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in _bloodGroups)
                  _pill(
                    label: b,
                    on: bloodGroup == b,
                    // Tapping the chosen one again clears it. Without that there
                    // is no way back to "not sure" once you have picked.
                    onTap: () => setState(() => bloodGroup = bloodGroup == b ? null : b),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FieldLabel(t('Email')),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(hintText: t('Optional — for receipts')),
            ),
            const SizedBox(height: 16),
            FieldLabel(t('Mobile number')),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              decoration: BoxDecoration(
                color: SC.sunkTint,
                borderRadius: BorderRadius.circular(SC.rField),
                border: Border.all(color: SC.hairlineCool),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 16, color: SC.inkFaint),
                  const SizedBox(width: 10),
                  Expanded(child: Text(c.mobile, style: ST.bodyStrong)),
                  StatusChip(t('Verified'), tone: ChipTone.good, dense: true),
                ],
              ),
            ),
            _hint('This is the number you registered with. Ask support to change it.',
                tone: SC.inkFaint),
          ],
        ),
      );

  Widget _photoRow() {
    final flagged = _missing('photo');
    final has = hasImage(photoPath);
    return Row(
      key: _photoKey,
      children: [
        PressableScale(
          onTap: _pickPhoto,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: flagged ? SC.red : (has ? SC.blueBright : SC.hairlineCool),
                    width: 2,
                  ),
                ),
                child: CircleAvatar(
                  radius: 36,
                  backgroundColor: SC.blueTint,
                  backgroundImage: avatarImage(photoPath),
                  child: has
                      ? null
                      : const Icon(Icons.person_rounded, size: 34, color: SC.blueBright),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: SC.blueBright,
                    shape: BoxShape.circle,
                    border: Border.all(color: SC.surface, width: 2.5),
                  ),
                  child: const Icon(Icons.photo_camera_rounded, size: 14, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(has ? 'Your photo' : 'Add a photo', style: ST.h3),
              const SizedBox(height: 4),
              Text(
                has
                    ? 'Tap to change it or take it off.'
                    : 'Required. Your carer uses it to be sure they have found '
                        'the right person at the door.',
                style: ST.small.copyWith(
                    height: 1.4, color: flagged ? SC.redDeep : SC.inkSoft),
              ),
              const SizedBox(height: 6),
              Text(c.id, style: ST.label.copyWith(color: SC.inkFaint, letterSpacing: 0.6)),
            ],
          ),
        ),
      ],
    );
  }

  // --- section 2: languages ---------------------------------------------------

  Widget _languageSection() => _section(
        'Languages you speak',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              languages.isEmpty
                  ? 'Pick any you are comfortable in. Carers who share a '
                      'language with you come first in your search.'
                  : 'Carers who speak '
                      '${languages.length == 1 ? languages.first : 'one of these'} '
                      'come first in your search.',
              style: ST.small.copyWith(height: 1.45),
            ),
            const SizedBox(height: 13),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final l in _allLanguages)
                  _pill(
                    label: l,
                    on: languages.contains(l),
                    onTap: () => setState(() =>
                        languages.contains(l) ? languages.remove(l) : languages.add(l)),
                  ),
              ],
            ),
          ],
        ),
      );

  // --- section 3: height, weight, BMI ----------------------------------------

  Widget _metrics() {
    final bmi = _liveBmi;
    return _section(
      'Height and weight',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FieldLabel(t('Height')),
                    TextField(
                      controller: heightCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: '165', suffixText: 'cm'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FieldLabel(t('Weight')),
                    TextField(
                      controller: weightCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: '62', suffixText: 'kg'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FadeSwitch(
            child: bmi == null
                ? Container(
                    key: const ValueKey('no-bmi'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: SC.sunkTint,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(t('Fill in both and we work out your BMI.'),
                        style: ST.small),
                  )
                : Container(
                    key: ValueKey(_bmiBand(bmi).word),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _bmiBand(bmi).tone.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _bmiBand(bmi).tone.withValues(alpha: 0.30)),
                    ),
                    child: Row(
                      children: [
                        AnimatedFigure(
                          value: bmi,
                          decimals: 1,
                          style: ST.figure.copyWith(fontSize: 26, color: _bmiBand(bmi).tone),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('BMI · ${_bmiBand(bmi).word}',
                                  style: ST.bodyStrong.copyWith(fontSize: 14)),
                              const SizedBox(height: 2),
                              Text(t('Worked out from your height and weight.'),
                                  style: ST.small.copyWith(fontSize: 12)),
                            ],
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

  // --- section 4: addresses ---------------------------------------------------

  Widget _addresses() => _section(
        'Where you are',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('Home address'), key: _addressKey, style: ST.h3),
            const SizedBox(height: 12),
            TextField(
              controller: pLine,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: t('Flat, building, street or area'),
                errorText: _missing('address') && pLine.text.trim().isEmpty
                    ? 'A carer needs a street to come to'
                    : null,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: pCity,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: t('City'),
                errorText:
                    _missing('address') && pCity.text.trim().isEmpty ? 'Which city?' : null,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _locating ? null : _useCurrentLocation,
                icon: _locating
                    ? const SizedBox(
                        width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location_rounded, size: 17),
                label: Text(_locating ? 'Finding you…' : 'Use my current location'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              ),
            ),
            if (_locationNote != null)
              _hint(_locationNote!, tone: _locationFailed ? SC.redDeep : SC.green),
            const SizedBox(height: 12),
            OsmMap(
              lat: _pinLat,
              lng: _pinLng,
              label: t('Home'),
              height: 165,
              zoom: 15,
              interactive: true,
              // Both the button above and the map's own crosshair move the
              // saved pin. Before, the map moved but the coordinates that got
              // saved did not, so the pin snapped back on the next visit.
              onLocated: (lat, lng) => setState(() {
                _pinLat = lat;
                _pinLng = lng;
                _locationFailed = false;
                _locationNote = 'Pin set to where you are now.';
              }),
            ),
            _hint('Drag the map to check the pin sits on the right building — '
                'this is where a carer is sent.'),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 14),
            if (!_showSecondary)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _showSecondary = true),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(t('Add a second address')),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(child: Text(t('Second address'), style: ST.h3)),
                  TextButton(
                    onPressed: () => setState(() {
                      sLine.clear();
                      sCity.clear();
                      _showSecondary = false;
                    }),
                    style: TextButton.styleFrom(
                        foregroundColor: SC.inkSoft, padding: EdgeInsets.zero),
                    child: Text(t('Remove')),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(t("Optional — a parent's house, or where you stay at weekends."),
                  style: ST.small.copyWith(height: 1.4)),
              const SizedBox(height: 12),
              TextField(
                controller: sLine,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(hintText: t('Flat, building, street or area')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: sCity,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(hintText: t('City')),
              ),
            ],
          ],
        ),
      );

  // --- section 5: contact -----------------------------------------------------

  Widget _contact() => _section(
        'How we should reach you',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              contactModes.isEmpty
                  ? t('Pick at least one. Booking updates go out this way.')
                  : t('Booking updates go out by {how}.', {
                      'how': contactModes.map((m) => t(_spokenMode[m]!)).join(t(' and ')),
                    }),
              style: ST.small.copyWith(height: 1.45),
            ),
            const SizedBox(height: 13),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in ContactMode.values)
                  _pill(
                    label: m.label,
                    on: contactModes.contains(m),
                    onTap: () => setState(() => contactModes.contains(m)
                        ? contactModes.remove(m)
                        : contactModes.add(m)),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            FieldLabel(t('Best time to reach you')),
            TextField(
              controller: timeframeCtrl,
              decoration: InputDecoration(hintText: t('e.g. 09:00-18:00')),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _timeframePresets)
                  _pill(
                    label: t,
                    on: timeframeCtrl.text.trim() == t,
                    dense: true,
                    onTap: () => setState(() =>
                        timeframeCtrl.text = timeframeCtrl.text.trim() == t ? '' : t),
                  ),
              ],
            ),
          ],
        ),
      );

  // --- the save bar -----------------------------------------------------------

  /// Pinned to the bottom. On a form this long the Save button used to be a
  /// scroll away from wherever you happened to be.
  Widget _saveBar() {
    return Container(
      decoration: const BoxDecoration(
        color: SC.surface,
        border: Border(top: BorderSide(color: SC.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(SC.gutter, 12, SC.gutter, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) ...[
                InlineError(message: _error!),
                const SizedBox(height: 12),
              ],
              Builder(builder: (_) {
                final settled = !_dirty && _problems.isEmpty;
                return GradientButton(
                  label: settled ? 'Saved' : 'Save profile',
                  icon: settled ? Icons.check_circle_rounded : Icons.check_rounded,
                  busy: _saving,
                  onPressed: _saving ? null : _save,
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // --- small shared pieces ----------------------------------------------------

  Widget _section(String title, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(title),
            SCard(child: child),
          ],
        ),
      );

  Widget _hint(String text, {Color tone = SC.inkSoft}) => Padding(
        padding: const EdgeInsets.only(top: 7, left: 2),
        child: Text(text, style: ST.small.copyWith(fontSize: 12, color: tone, height: 1.4)),
      );

  Widget _pill({
    required String label,
    required bool on,
    required VoidCallback onTap,
    bool dense = false,
  }) {
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Dur.quick,
        curve: Ease.enter,
        padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 14, vertical: dense ? 8 : 10),
        decoration: BoxDecoration(
          color: on ? SC.blueBright : SC.surface,
          borderRadius: BorderRadius.circular(SC.rPill),
          border: Border.all(color: on ? SC.blueBright : SC.hairlineCool, width: 1.3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (on) ...[
              const Icon(Icons.check_rounded, size: 14, color: Colors.white),
              const SizedBox(width: 5),
            ],
            Text(label,
                style: TextStyle(
                  fontSize: dense ? 12.5 : 13.5,
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : SC.inkSoft,
                )),
          ],
        ),
      ),
    );
  }

  /// The equal-width variant, for a row of options that should read as one
  /// control rather than a scatter of chips.
  Widget _choice({
    required String label,
    required bool on,
    required VoidCallback onTap,
    bool flagged = false,
  }) {
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Dur.quick,
        curve: Ease.enter,
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? SC.blueBright : SC.surface,
          borderRadius: BorderRadius.circular(SC.rField),
          border: Border.all(
            color: on ? SC.blueBright : (flagged ? SC.red : SC.hairlineCool),
            width: 1.3,
          ),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: on ? Colors.white : SC.inkSoft,
            )),
      ),
    );
  }

  Widget _tappableField({
    required IconData icon,
    required String text,
    required bool placeholder,
    required VoidCallback onTap,
    String? trailing,
    bool flagged = false,
  }) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: SC.surface,
          borderRadius: BorderRadius.circular(SC.rField),
          border: Border.all(color: flagged ? SC.red : SC.hairline, width: 1.3),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: placeholder ? SC.inkFaint : SC.blueBright),
            const SizedBox(width: 11),
            Expanded(
              child: Text(text,
                  style: placeholder ? ST.body.copyWith(color: SC.inkFaint) : ST.bodyStrong),
            ),
            if (trailing != null) StatusChip(trailing, tone: ChipTone.neutral, dense: true),
          ],
        ),
      ),
    );
  }
}
