import 'package:flutter/material.dart';

import '../../backend.dart';
import '../../models.dart';
import '../../languages.dart';
import '../../theme/sathiyaa_theme.dart';
import '../../widgets/motion.dart';
import '../../widgets/sathiyaa_ui.dart';
import '../../widgets/document_field.dart';
import '../../widgets/osm_map.dart';
import '../../services/geocode.dart';
import '../../services/location_service.dart';
import '../../city_defaults.dart';
import '../../utils/dates.dart';
import '../../i18n/l10n.dart';

/// Adding or editing one of an organisation's carers.
///
/// Rebuilt on the design system, with three things corrected: nothing was
/// validated, so a nameless employee with no number could be saved and then
/// allocated to a visit; the controllers were never disposed; and the form
/// carried a grey box reading "Map placeholder", which is a note-to-self left
/// where a user can read it. An employee has no coordinates to draw, so the box
/// is gone rather than faked.
class AddEditEmployeeScreen extends StatefulWidget {
  final Employee? employee;
  const AddEditEmployeeScreen({super.key, this.employee});
  @override
  State<AddEditEmployeeScreen> createState() => _AddEditEmployeeScreenState();
}

const _genders = ['Female', 'Male', 'Other'];

class _AddEditEmployeeScreenState extends State<AddEditEmployeeScreen> {
  late TextEditingController nameCtrl;
  late TextEditingController mobileCtrl;
  late TextEditingController addressCtrl;
  late TextEditingController homeDistCtrl;
  late TextEditingController officeDistCtrl;
  String gender = 'Female';
  bool busy = false;
  bool _tried = false;

  // ---- the carer's own papers ------------------------------------------
  //
  // Not the organisation's. An agency proving it is registered says nothing
  // about the person who will be standing in somebody's hallway, and a family
  // has no way of knowing which route a carer arrived by.
  String? aadharUrl;
  String? policeUrl;
  DateTime? policeFrom;
  DateTime? policeTo;
  String? medicalUrl;
  DateTime? medicalFrom;
  DateTime? medicalTo;
  DateTime? dob;
  Set<ServiceType> expertise = {ServiceType.companion};
  Set<String> languages = {...kDefaultLanguages};

  // ---- where they set out from -----------------------------------------
  double pinLat = kDefaultLat;
  double pinLng = kDefaultLng;
  bool locating = false;
  String? locationNote;
  bool locationFailed = false;

  // ---- when they work ---------------------------------------------------
  //
  // Same shape as the registration form, because it is the same question and
  // an organisation should not have to learn a second one.
  final Set<String> workDays = {};
  String workFrom = '09:00';
  String workTo = '18:00';
  bool differentHours = false;
  final Map<String, DayHours> dayHours = {};

  bool get _isNew => widget.employee == null;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    nameCtrl = TextEditingController(text: e?.name ?? '');
    mobileCtrl = TextEditingController(text: e?.mobile ?? '');
    addressCtrl = TextEditingController(text: e?.address ?? '');
    homeDistCtrl = TextEditingController(text: e?.distanceFromHomeKm?.toString() ?? '');
    officeDistCtrl = TextEditingController(text: e?.distanceFromOfficeKm?.toString() ?? '');
    gender = e?.gender.isNotEmpty == true ? e!.gender : 'Female';
    dob = e?.dob;
    expertise = e?.expertise.toSet() ?? {ServiceType.companion};
    languages = e?.languages.toSet() ?? {...kDefaultLanguages};
    pinLat = e?.lat ?? kDefaultLat;
    pinLng = e?.lng ?? kDefaultLng;
    final pref = e?.workPref ?? WorkPreference();
    workDays.addAll(pref.days);
    workFrom = pref.timeFrom;
    workTo = pref.timeTo;
    differentHours = pref.perDay.isNotEmpty;
    dayHours.addAll(pref.perDay);
    aadharUrl = e?.aadhar.url;
    policeUrl = e?.policeVerification.url;
    policeFrom = e?.policeVerification.validFrom;
    policeTo = e?.policeVerification.validTo;
    medicalUrl = e?.medicalCertificate.url;
    medicalFrom = e?.medicalCertificate.validFrom;
    medicalTo = e?.medicalCertificate.validTo;
    for (final c in [nameCtrl, mobileCtrl, addressCtrl]) {
      c.addListener(() {
        if (_tried && mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    for (final c in [nameCtrl, mobileCtrl, addressCtrl, homeDistCtrl, officeDistCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  String? get _nameError =>
      nameCtrl.text.trim().length < 2 ? 'A carer needs a name on the job sheet' : null;

  String? get _mobileError => mobileCtrl.text.trim().length != 10
      ? 'Ten digits, no country code — this is how a family reaches them'
      : null;

  String? get _addressError => addressCtrl.text.trim().isEmpty
      ? t('Needed to work out travel distance')
      : null;

  String? get _aadharError =>
      aadharUrl == null ? t('Required before this carer can visit anybody') : null;

  String? get _policeError => policeUrl == null
      ? t('Required before this carer can visit anybody')
      : (policeFrom == null || policeTo == null)
          ? t('Add the dates printed on the certificate')
          : !policeTo!.isAfter(policeFrom!)
              ? t('The "to" date must be after the "from" date')
              : policeTo!.isBefore(DateTime.now())
                  ? t('This police verification has expired')
                  : null;

  String? get _medicalError {
    final clinical = expertise
        .any((x) => x == ServiceType.nurse || x == ServiceType.physiotherapy);
    if (clinical && medicalUrl == null) {
      return t('Required for nursing and physiotherapy');
    }
    if (medicalUrl != null && (medicalFrom == null || medicalTo == null)) {
      return t('Add the dates printed on the certificate');
    }
    return null;
  }

  String? get _expertiseError =>
      expertise.isEmpty ? t('Pick at least one kind of care') : null;

  String? get _languagesError =>
      languages.isEmpty ? t('Pick at least one language.') : null;

  /// "18:00" is after "09:00" — both are zero-padded 24-hour times.
  static bool _after(String a, String b) => a.compareTo(b) > 0;

  String? get _daysError =>
      workDays.isEmpty ? t('Pick at least one day they work.') : null;

  /// A finish time before a start time is a silent problem: the allocation
  /// query works out capacity from these two, and a negative window makes a
  /// carer look permanently unavailable with nothing on screen to say why.
  String? get _hoursError {
    if (differentHours) {
      for (final d in workDays) {
        final h = dayHours[d] ?? DayHours(workFrom, workTo);
        if (!_after(h.to, h.from)) {
          return t('On {day} the finish time has to be after the start time.', {'day': t(d)});
        }
      }
      return null;
    }
    return _after(workTo, workFrom)
        ? null
        : t('The finish time has to be after the start time.');
  }

  Future<void> save() async {
    setState(() => _tried = true);
    if (_nameError != null ||
        _mobileError != null ||
        _addressError != null ||
        _daysError != null ||
        _hoursError != null ||
        _expertiseError != null ||
        _languagesError != null ||
        _aadharError != null ||
        _policeError != null ||
        _medicalError != null) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => busy = true);

    final e = Employee(
      id: widget.employee?.id ?? 'EMP-${DateTime.now().millisecondsSinceEpoch % 10000}',
      name: nameCtrl.text.trim(),
      gender: gender,
      mobile: mobileCtrl.text.trim(),
      dob: dob,
      address: addressCtrl.text.trim(),
      lat: pinLat,
      lng: pinLng,
      expertise: expertise.toList(),
      languages: languages.toList(),
      distanceFromHomeKm: double.tryParse(homeDistCtrl.text),
      distanceFromOfficeKm: double.tryParse(officeDistCtrl.text),
      status: widget.employee?.status ?? EmployeeStatus.active,
      approvalStatus: widget.employee?.approvalStatus ?? 'pending',
      workPref: WorkPreference(
        days: workDays.toList(),
        timeFrom: workFrom,
        timeTo: workTo,
        perDay: differentHours ? Map<String, DayHours>.from(dayHours) : {},
      ),
      aadhar: ProviderDocument(url: aadharUrl),
      policeVerification:
          ProviderDocument(url: policeUrl, validFrom: policeFrom, validTo: policeTo),
      medicalCertificate:
          ProviderDocument(url: medicalUrl, validFrom: medicalFrom, validTo: medicalTo),
    );

    try {
      if (_isNew) {
        await Backend.instance.addEmployee(e);
      } else {
        await Backend.instance.updateEmployee(e);
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isNew
              ? t('{name} added. Sathiyaa will check their documents before they can be allocated.',
                  {'name': e.name})
              : t('{name} updated.', {'name': e.name})),
        ),
      );
      navigator.pop(true);
    } catch (err) {
      if (!mounted) return;
      setState(() => busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text(err.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SC.paper,
      body: Column(
        children: [
          BrandHeader(
            curved: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, SC.gutter, 14),
              child: Row(
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
                        Text(_isNew ? 'Add a carer' : 'Edit carer',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(
                          _isNew
                              ? 'Somebody on your team who visits families'
                              : widget.employee!.id,
                          style: const TextStyle(color: Colors.white70, fontSize: 13.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 30),
              children: staggered([
                SectionLabel(t('Who they are')),
                SCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FieldLabel(t('Name'), required: true),
                      TextField(
                        controller: nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          hintText: t('As the family should see it'),
                          errorText: _tried ? _nameError : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FieldLabel(t('Gender')),
                      Row(
                        children: [
                          for (final g in _genders) ...[
                            Expanded(
                              child: _choice(
                                label: g,
                                on: gender == g,
                                onTap: () => setState(() => gender = g),
                              ),
                            ),
                            if (g != _genders.last) const SizedBox(width: 9),
                          ],
                        ],
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
                          errorText: _tried ? _mobileError : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Which address, spelled out. "Address" on a screen
                      // inside an organisation's account reads as the
                      // organisation's, and it is not: distance to a booking
                      // is measured from where the carer sets out.
                      FieldLabel(t('This carer\'s home address'), required: true),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          t('Where they travel from — not your office. Sathiyaa uses it to work out how far a visit is for them.'),
                          style: ST.small,
                        ),
                      ),
                      TextField(
                        controller: addressCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          hintText: t('House / street, area, city'),
                          errorText: _tried ? _addressError : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Only useful when the carer is standing next to you,
                      // which is how most of these are filled in — so it says
                      // whose location it is about to use.
                      OutlinedButton.icon(
                        onPressed: locating ? null : _useCurrentLocation,
                        icon: locating
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.my_location_rounded, size: 18),
                        label: Text(locating
                            ? t('Finding the address…')
                            : t('Use this phone\'s location')),
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
                      // The pin, so it can be dragged to the right house
                      // rather than taken on trust from a street name.
                      OsmMap(
                        lat: pinLat,
                        lng: pinLng,
                        label: t('Where this carer sets out from'),
                        height: 160,
                        onLocated: (la, ln) => setState(() {
                          pinLat = la;
                          pinLng = ln;
                        }),
                      ),
                      const SizedBox(height: 16),
                      FieldLabel(t('Date of birth')),
                      PressableScale(
                        onTap: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: dob ?? DateTime(now.year - 30),
                            firstDate: DateTime(now.year - 80),
                            lastDate: DateTime(now.year - 18),
                          );
                          if (picked != null) setState(() => dob = picked);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                          decoration: BoxDecoration(
                            color: SC.surface,
                            borderRadius: BorderRadius.circular(SC.rField),
                            border: Border.all(color: SC.hairline),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.cake_rounded, size: 18, color: SC.blueBright),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Text(
                                  dob == null ? t('Optional — tap to choose') : prettyDate(dob!),
                                  style: dob == null
                                      ? ST.body.copyWith(color: SC.inkFaint)
                                      : ST.bodyStrong,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SectionLabel(t('Care they can give')),
                SCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('A carer is only offered visits of a kind they are listed for.'),
                        style: ST.small.copyWith(height: 1.45),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ServiceType.values.map((svc) {
                          final on = expertise.contains(svc);
                          return PressableScale(
                            scale: 0.94,
                            onTap: () => setState(() {
                              on ? expertise.remove(svc) : expertise.add(svc);
                            }),
                            child: AnimatedContainer(
                              duration: Dur.micro,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 15, vertical: 9),
                              decoration: BoxDecoration(
                                color: on ? SC.blueBright : SC.surface,
                                borderRadius: BorderRadius.circular(SC.rPill),
                                border: Border.all(
                                    color: on ? SC.blueBright : SC.hairlineCool),
                              ),
                              child: Text(svc.label,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: on ? Colors.white : SC.ink,
                                  )),
                            ),
                          );
                        }).toList(),
                      ),
                      if (_tried && _expertiseError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(_expertiseError!,
                              style: const TextStyle(color: SC.red, fontSize: 12.5)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SectionLabel(t('When they work')),
                SCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('A visit is only offered to somebody whose hours cover it. Leave this wrong and this carer is never matched to anything.'),
                        style: ST.small.copyWith(height: 1.45),
                      ),
                      const SizedBox(height: 14),
                      FieldLabel(t('Days they work'), required: true),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                            .map((d) => _DayPill(
                                  label: t(d),
                                  on: workDays.contains(d),
                                  onTap: () => setState(() {
                                    workDays.contains(d)
                                        ? workDays.remove(d)
                                        : workDays.add(d);
                                  }),
                                ))
                            .toList(),
                      ),
                      if (_tried && _daysError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(_daysError!,
                              style: const TextStyle(color: SC.red, fontSize: 12.5)),
                        ),
                      const SizedBox(height: 18),
                      _hoursSection(),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SectionLabel(t('Languages they speak')),
                SCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('A family filters by language and reads this on the card before choosing. Getting it wrong sends somebody who cannot talk to the person they are visiting.'),
                        style: ST.small.copyWith(height: 1.45),
                      ),
                      const SizedBox(height: 12),
                      LanguagePicker(
                        selected: languages,
                        onChanged: (set) => setState(() => languages = set),
                      ),
                      if (_tried && _languagesError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(_languagesError!,
                              style: const TextStyle(color: SC.red, fontSize: 12.5)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SectionLabel(t('Their verification')),
                SCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('The same documents Sathiyaa asks of any carer. They belong to this person, not to your organisation, and a family is told every carer has been checked — so a carer without them is not allocated to anybody.'),
                        style: ST.small.copyWith(height: 1.45),
                      ),
                      const SizedBox(height: 14),
                      DocumentField(
                        label: t('Aadhar or work certificate'),
                        category: 'aadhar',
                        required: true,
                        hint: t('Either side, as long as their name and photo are readable.'),
                        url: aadharUrl,
                        errorText: _tried ? _aadharError : null,
                        onChanged: (u) => setState(() => aadharUrl = u),
                      ),
                      DocumentField(
                        label: t('Police verification'),
                        category: 'police-verification',
                        required: true,
                        hint: t('From their local station. The dates on it are needed too, so make sure they are in the photo.'),
                        url: policeUrl,
                        errorText: _tried ? _policeError : null,
                        onChanged: (u) => setState(() => policeUrl = u),
                      ),
                      if (policeUrl != null)
                        _validity(
                          from: policeFrom,
                          to: policeTo,
                          onChange: (f, t2) => setState(() {
                            policeFrom = f;
                            policeTo = t2;
                          }),
                        ),
                      DocumentField(
                        label: t('Medical certificate'),
                        category: 'medical-certificate',
                        required: expertise.any((x) =>
                            x == ServiceType.nurse || x == ServiceType.physiotherapy),
                        hint: expertise.any((x) =>
                                x == ServiceType.nurse || x == ServiceType.physiotherapy)
                            ? t('Required because this carer is listed for nursing or physiotherapy.')
                            : t('Optional for companion work.'),
                        url: medicalUrl,
                        errorText: _tried ? _medicalError : null,
                        onChanged: (u) => setState(() => medicalUrl = u),
                      ),
                      if (medicalUrl != null)
                        _validity(
                          from: medicalFrom,
                          to: medicalTo,
                          onChange: (f, t2) => setState(() {
                            medicalFrom = f;
                            medicalTo = t2;
                          }),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SectionLabel(t('How far they will travel')),
                SCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('Optional. Requests further away than this are not allocated to them.'),
                        style: ST.small.copyWith(height: 1.45),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FieldLabel(t('From home')),
                                TextField(
                                  controller: homeDistCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      hintText: '10', suffixText: 'km'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FieldLabel(t('From the office')),
                                TextField(
                                  controller: officeDistCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      hintText: '15', suffixText: 'km'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                GradientButton(
                  label: _isNew ? 'Add this carer' : 'Save changes',
                  icon: _isNew ? Icons.person_add_rounded : Icons.check_rounded,
                  busy: busy,
                  onPressed: busy ? null : save,
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// Finds where this phone is and fills the address in from it.
  ///
  /// Best effort on every step: a refused permission, a timed-out fix and a
  /// geocoder that says nothing all leave the form exactly as it was, with a
  /// sentence saying what happened. Nothing here can fail the save.
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
      locationNote = t('Finding the address…');
    });

    final place = await Geocode.reverse(fix.lat!, fix.lng!);
    if (!mounted) return;
    setState(() {
      locating = false;
      final pinNote = fix.accuracyMetres == null
          ? t('Pin set to where this phone is.')
          : t('Pin set to where this phone is (about {m} m accurate).',
              {'m': fix.accuracyMetres!.round()});
      if (place == null || place.isEmpty) {
        locationNote = pinNote;
        return;
      }
      if (addressCtrl.text.trim().isEmpty) {
        addressCtrl.text = place.oneLine;
        locationNote =
            t('{pin} We filled the address in — check it is the carer\'s home, not your office.',
                {'pin': pinNote});
      } else {
        locationNote = t('{pin} The address is already filled in, so nothing was changed.',
            {'pin': pinNote});
      }
    });
  }

  String _fmt(TimeOfDay v) =>
      '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}';

  TimeOfDay _parse(String v) {
    final bits = v.split(':');
    return TimeOfDay(hour: int.tryParse(bits.first) ?? 9, minute: int.tryParse(bits.last) ?? 0);
  }

  Future<void> _pickTime(String current, ValueChanged<String> onPicked) async {
    final picked = await showTimePicker(context: context, initialTime: _parse(current));
    if (picked != null) setState(() => onPicked(_fmt(picked)));
  }

  Widget _timeBox(String value, ValueChanged<String> onPicked) => Expanded(
        child: PressableScale(
          onTap: () => _pickTime(value, onPicked),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: SC.surface,
              borderRadius: BorderRadius.circular(SC.rField),
              border: Border.all(color: SC.hairline),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 16, color: SC.blueBright),
                const SizedBox(width: 9),
                Text(value, style: ST.bodyStrong),
              ],
            ),
          ),
        ),
      );

  /// One window, or seven. A switch rather than two modes on the form,
  /// because the common case is one window and the seven-row version should
  /// cost a deliberate tap.
  Widget _hoursSection() {
    final ordered = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        .where(workDays.contains)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(t('Hours they work'), required: true),
        if (!differentHours)
          Row(
            children: [
              _timeBox(workFrom, (v) => workFrom = v),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('–', style: ST.bodyStrong),
              ),
              _timeBox(workTo, (v) => workTo = v),
            ],
          )
        else if (ordered.isEmpty)
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
                    (v) => dayHours[d] =
                        DayHours(v, (dayHours[d] ?? DayHours(workFrom, workTo)).to),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('–', style: ST.bodyStrong),
                  ),
                  _timeBox(
                    (dayHours[d] ?? DayHours(workFrom, workTo)).to,
                    (v) => dayHours[d] =
                        DayHours((dayHours[d] ?? DayHours(workFrom, workTo)).from, v),
                  ),
                ],
              ),
            ),
        if (_tried && _hoursError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_hoursError!,
                style: const TextStyle(color: SC.red, fontSize: 12.5)),
          ),
        const SizedBox(height: 4),
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

  /// The "valid between" pair that belongs to the document above it.
  Widget _validity({
    required DateTime? from,
    required DateTime? to,
    required void Function(DateTime?, DateTime?) onChange,
  }) {
    Widget box(DateTime? value, String placeholder, VoidCallback onTap) => Expanded(
          child: PressableScale(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              decoration: BoxDecoration(
                color: SC.surface,
                borderRadius: BorderRadius.circular(SC.rField),
                border: Border.all(color: SC.hairline),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 15, color: SC.blueBright),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      value == null ? placeholder : prettyDate(value),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: value == null
                          ? ST.small.copyWith(color: SC.inkFaint)
                          : ST.small.copyWith(fontWeight: FontWeight.w700, color: SC.ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

    Future<DateTime?> pick(DateTime? initial) => showDatePicker(
          context: context,
          initialDate: initial ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2035),
        );

    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(t('Valid between'), required: true),
          Row(
            children: [
              box(from, t('From'), () async {
                final p = await pick(from);
                if (p != null) onChange(p, to);
              }),
              const SizedBox(width: 10),
              box(to, t('To'), () async {
                final p = await pick(to);
                if (p != null) onChange(from, p);
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _choice({
    required String label,
    required bool on,
    required VoidCallback onTap,
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
            color: on ? SC.blueBright : SC.hairlineCool,
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
}

/// One day of the week, on or off.
class _DayPill extends StatelessWidget {
  const _DayPill({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scale: 0.94,
      onTap: onTap,
      child: AnimatedContainer(
        duration: Dur.micro,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: on ? SC.blueBright : SC.surface,
          borderRadius: BorderRadius.circular(SC.rPill),
          border: Border.all(color: on ? SC.blueBright : SC.hairlineCool),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: on ? Colors.white : SC.ink,
            )),
      ),
    );
  }
}
