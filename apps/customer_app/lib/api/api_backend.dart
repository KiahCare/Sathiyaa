import '../backend.dart';
import '../models.dart';
import '../broadcasts.dart';
import '../service_area.dart';
import 'api_client.dart';

/// Does this string point at something the *server* holds, rather than a file
/// sitting on this phone?
///
/// The old test was "does it start with a slash". On Android the image picker
/// hands back `/data/user/0/in.sathiyaa.customer/cache/scaled_1234.jpg`, which
/// starts with a slash too, so a local file was indistinguishable from a
/// server path -- and the provider app shipped a registration flow that
/// skipped the upload entirely because of it.
///
/// Server references are exactly two shapes: an absolute http(s) URL, or a
/// path under `/uploads/`. Everything else is local.
bool isServerRef(String? ref) {
  if (ref == null || ref.isEmpty) return false;
  return ref.startsWith('http://') || ref.startsWith('https://') || ref.startsWith('/uploads/');
}

/// The real backend: Express + MySQL, over the contract in
/// `docs/api-contract.md`.
///
/// The app's screens are built around a single in-memory [Customer] object, so
/// this class keeps one hydrated from the server: writes go out over HTTP and,
/// on success, the local copy is updated to match. That keeps every screen
/// working unchanged whether it is talking to the mock or to a live server.
class ApiBackend implements SathiyaaBackend {

  /// The upload endpoint returns paths relative to the server root
  /// (`/uploads/photo/x.jpg`), while the API itself lives under `/api/v1`.
  /// Strip the version prefix to get back to the host that serves the files.
  @override
  String? absoluteUrl(String? ref) {
    if (ref == null || ref.isEmpty) return null;
    if (ref.startsWith('http://') || ref.startsWith('https://')) return ref;
    if (!isServerRef(ref)) return null; // a file on this phone, not on the server
    final root = _c.baseUrl.replaceFirst(RegExp(r'/api/v\d+/?$'), '');
    return '$root$ref';
  }
  final ApiClient _c;

  /// [onToken] is called whenever the session token changes — with the new
  /// token on sign-in, and null on sign-out. Injected rather than reaching for
  /// storage directly, so this class stays a pure API client: it does not know
  /// or care whether the token is being persisted, and it is usable in a test
  /// with no Flutter bindings.
  ApiBackend(String baseUrl, {this.onToken}) : _c = ApiClient(baseUrl);

  final Future<void> Function(String? token)? onToken;

  @override
  Customer? currentCustomer;

  /// Providers already fetched this session, so list rows can render a name
  /// without issuing a request mid-build.
  final Map<String, Provider> _providerCache = {};

  @override
  Provider? cachedProvider(String id) => _providerCache[id];

  void _cache(Iterable<Provider> providers) {
    for (final p in providers) {
      _providerCache[p.id] = p;
    }
  }

  @override
  bool get supportsSimulation => false;

  // =========================================================== session ===
  @override
  Future<String?> registerCustomer({required String name, required String mobile}) async {
    final res = await _c.post('/auth/customer/register', {'name': name, 'mobile': mobile});
    return res is Map ? res['devOtp'] as String? : null;
  }

  @override
  Future<String?> loginRequestOtp(String mobile) async {
    final res = await _c.post('/auth/customer/login', {'mobile': mobile});
    return res is Map ? res['devOtp'] as String? : null;
  }

  @override
  Future<void> verifyOtp(String mobile, String otp) async {
    final res = await _c.post('/auth/customer/verify-otp', {'mobile': mobile, 'otp': otp});
    final token = res['token'] as String;
    _c.token = token;
    await onToken?.call(token);
    await refreshProfile();
  }

  /// Reinstates a token read back from storage at startup, without a login.
  void restoreToken(String? token) => _c.token = token;

  /// The token this client is currently using, so it can be persisted.
  String? get currentToken => _c.token;

  @override
  Future<void> acceptTerms() async {
    await _c.post('/customers/me/accept-terms', {'accepted': true});
    currentCustomer?.termsAccepted = true;
  }

  @override
  Future<void> signOut() async {
    _c.token = null;
    currentCustomer = null;
    await onToken?.call(null);
  }

  // =========================================================== profile ===
  @override
  Future<void> refreshProfile() async {
    final me = await _c.get('/customers/me') as Map;
    final c = _customerFrom(me);

    // The profile sections come from their own endpoints; fetch them together
    // so one refresh leaves the whole screen consistent.
    final results = await Future.wait([
      _c.get('/customers/me/vitals'),
      _c.get('/customers/me/medications'),
      _c.get('/customers/me/surgeries'),
      _c.get('/customers/me/allergies'),
      _c.get('/customers/me/insurance'),
      _c.get('/customers/me/family'),
      _c.get('/customers/me/linked-providers'),
    ]);

    c.vitals = _list(results[0], 'vitals').map(_vitalFrom).toList();
    c.medications = _list(results[1], 'medications').map(_medicationFrom).toList();
    c.surgeries = _list(results[2], 'surgeries').map(_surgeryFrom).toList();
    c.allergies = _list(results[3], 'allergies').map(_allergyFrom).toList();
    c.insurance = _list(results[4], 'insurance').map(_insuranceFrom).toList();
    c.family = _list(results[5], 'family').map(_familyFrom).toList();
    c.linkedProviderIds =
        _list(results[6], 'linkedProviders').map((r) => '${r['providerId']}').toList();

    currentCustomer = c;
  }

  @override
  Future<void> updateBasicDetails({
    required String name,
    String? email,
    String? photoPath,
    DateTime? dob,
    String? gender,
    String? bloodGroup,
    List<String>? languages,
    double? heightCm,
    double? weightKg,
  }) async {
    if (name.trim().isEmpty) throw Exception('Name is required.');
    if (dob == null) throw Exception('Date of birth is required.');
    if (gender == null || gender.isEmpty) throw Exception('Gender is required.');
    if ((photoPath ?? currentCustomer?.photoUrl) == null) {
      throw Exception('A profile photo is required.');
    }

    // A freshly-picked photo is a local file path; upload it and store the URL
    // the server hands back, so the photo survives a reinstall and is visible
    // from any device.
    var photoUrl = photoPath ?? currentCustomer?.photoUrl;
    // Same reasoning as _prescriptionUrl: the question is "is this already on
    // the server", and since uploads return `/uploads/...` rather than an
    // absolute URL, `startsWith('http')` no longer answers it.
    if (photoPath != null && !isServerRef(photoPath)) {
      photoUrl = await _c.uploadFile(photoPath, category: 'photo');
    }

    final res = await _c.put('/customers/me', {
      'name': name.trim(),
      'email': email,
      'photoUrl': photoUrl,
      'dob': ymd(dob),
      'gender': gender.toLowerCase(),
      'bloodGroup': bloodGroup,
      'preferredLanguages': languages ?? const <String>[],
      'heightCm': heightCm,
      'weightKg': weightKg,
    });

    final updated = _customerFrom(res as Map);
    // The section lists aren't returned by PUT, so carry the current ones over.
    final old = currentCustomer;
    if (old != null) {
      updated
        ..vitals = old.vitals
        ..medications = old.medications
        ..surgeries = old.surgeries
        ..allergies = old.allergies
        ..insurance = old.insurance
        ..family = old.family
        ..linkedProviderIds = old.linkedProviderIds
        ..addresses = old.addresses
        ..contactModes = old.contactModes
        ..contactTimeframe = old.contactTimeframe
        ..referenceCode = old.referenceCode;
    }
    updated.photoUrl = photoUrl;
    currentCustomer = updated;
  }

  @override
  Future<void> saveAddresses({required Address primary, Address? secondary}) async {
    if (primary.line1.trim().isEmpty || primary.city.trim().isEmpty) {
      throw Exception('A primary address (street and city) is required.');
    }
    final res = await _c.put('/customers/me/addresses', {
      'primary': {
        'line1': primary.line1.trim(),
        'city': primary.city.trim(),
        'latitude': primary.lat,
        'longitude': primary.lng,
      },
      if (secondary != null && secondary.line1.trim().isNotEmpty)
        'secondary': {
          'line1': secondary.line1.trim(),
          'city': secondary.city.trim(),
          'latitude': secondary.lat,
          'longitude': secondary.lng,
        },
    });
    currentCustomer?.addresses = _list(res, 'addresses').map(_addressFrom).toList();
  }

  @override
  Address? primaryAddress() {
    final list = currentCustomer?.addresses ?? const <Address>[];
    for (final a in list) {
      if (a.isPrimary) return a;
    }
    return list.isEmpty ? null : list.first;
  }

  @override
  Future<void> setContactPreference({required Set<ContactMode> modes, String? timeframe}) async {
    if (modes.isEmpty) throw Exception('Pick at least one way to be contacted.');
    await _c.put('/customers/me', {
      'preferredCommMode': modes.map((m) => m.name).join(','),
      'preferredCommTimeframe': timeframe,
    });
    currentCustomer
      ?..contactModes = modes
      ..contactTimeframe = timeframe;
  }

  @override
  Future<String> applyReferenceCode(String code) async {
    // Checked against business_agents, on the server.
    //
    // This used to count characters: four or more and the app showed a green
    // "verified" tick and kept the code in memory. So a typo passed, the
    // partner's name could not be shown because there was nothing to look it
    // up in, and closing the app threw the code away -- the customer booked
    // weeks later with no code attached and the partner who introduced them
    // earned nothing. The failure was invisible at both ends.
    final normalised = code.trim().toUpperCase();
    if (normalised.isEmpty) throw Exception('Enter the code you were given.');
    final res = await _c.post('/customers/me/referral', {'code': normalised});
    final partner = '${(res as Map)['partnerName'] ?? ''}';
    currentCustomer
      ?..referenceCode = '${res['code'] ?? normalised}'
      ..referencePartner = partner.isEmpty ? null : partner;
    return partner.isEmpty ? normalised : partner;
  }

  @override
  Future<void> clearReferenceCode() async {
    await _c.delete('/customers/me/referral');
    currentCustomer
      ?..referenceCode = null
      ..referencePartner = null;
  }


  @override
  Future<List<Broadcast>> loadBroadcasts() async {
    final res = await _c.get('/broadcasts');
    final list = (res as Map)['broadcasts'];
    if (list is! List) return const [];
    return list.whereType<Map>().map(Broadcast.fromJson).toList();
  }

  @override
  Future<void> markBroadcastsRead() async {
    await _c.post('/broadcasts/all/read', {});
  }

  @override
  Future<ServiceArea> loadServiceArea() async {
    final res = await _c.get('/public/service-area');
    return ServiceArea.fromJson(Map<String, dynamic>.from(res as Map));
  }

  @override
  Future<bool> reportSignupPlace(SignupPlace place) async {
    final res = await _c.put('/customers/me/signup-place', place.toJson());
    final inside = asBool((res as Map)['inServiceArea']);
    currentCustomer
      ?..signupInServiceArea = inside
      ..signupCity = place.city;
    return inside;
  }

  @override
  Future<void> payRegistrationFee() async {
    final res = await _c.post('/customers/me/registration-payment', {});
    currentCustomer?.registrationFeePaid = asBool((res as Map)['paid']);
    final amount = asDouble(res['amount']);
    if (amount != null) currentCustomer?.registrationFeeAmount = amount;
    // The renewal date and the next amount both move the moment a payment
    // lands, and only the server knows the new ones.
    await refreshProfile();
  }

  // =================================================== health sections ===
  @override
  Future<void> addVital(VitalRecord v) async {
    await _c.post('/customers/me/vitals', {
      'vitalType': v.type.wire,
      'valuePrimary': v.valuePrimary,
      'valueSecondary': v.valueSecondary,
      'recordedAt': '${ymd(v.date)} 09:00:00',
    });
    await _reloadSection('vitals');
  }

  @override
  Future<void> updateVital(VitalRecord v) async {
    await _c.put('/customers/me/vitals/${v.id}', {
      'vitalType': v.type.wire,
      'valuePrimary': v.valuePrimary,
      'valueSecondary': v.valueSecondary,
      'recordedAt': '${ymd(v.date)} 09:00:00',
    });
    await _reloadSection('vitals');
  }

  @override
  Future<void> deleteVital(String id) async {
    await _c.delete('/customers/me/vitals/$id');
    await _reloadSection('vitals');
  }

  @override
  List<VitalRecord> vitalsWithin(int days, {VitalType? type}) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final list = (currentCustomer?.vitals ?? const <VitalRecord>[])
        .where((v) => v.date.isAfter(cutoff) && (type == null || v.type == type))
        .toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  @override
  Future<void> addMedication(MedicationRecord m) async {
    await _c.post('/customers/me/medications', {
      'medicineName': m.name,
      'frequency': m.frequency,
      'prescriptionUrl': await _prescriptionUrl(m),
    });
    await _reloadSection('medications');
  }

  @override
  Future<void> updateMedication(MedicationRecord m) async {
    await _c.put('/customers/me/medications/${m.id}', {
      'medicineName': m.name,
      'frequency': m.frequency,
      'prescriptionUrl': await _prescriptionUrl(m),
    });
    await _reloadSection('medications');
  }

  /// A newly-attached prescription is a local file path; anything already on
  /// the server has been uploaded before and is passed through unchanged.
  ///
  /// The test used to be `startsWith('http')`, which was true while uploads
  /// came back as absolute URLs. They now come back as `/uploads/...`, so that
  /// test called an already-uploaded prescription a local file and tried to
  /// read it off the phone — "That file is no longer on this device" — every
  /// time somebody edited a medication without touching its prescription.
  Future<String?> _prescriptionUrl(MedicationRecord m) async {
    final ref = m.prescriptionUrl;
    if (ref == null || ref.isEmpty) return null;
    if (isServerRef(ref)) return ref;
    return _c.uploadFile(ref, category: 'prescription');
  }

  @override
  Future<void> deleteMedication(String id) async {
    await _c.delete('/customers/me/medications/$id');
    await _reloadSection('medications');
  }

  @override
  Future<void> addSurgery(SurgeryRecord s) async {
    await _c.post('/customers/me/surgeries', {'surgeryName': s.name, 'surgeryDate': ymd(s.date)});
    await _reloadSection('surgeries');
  }

  @override
  Future<void> updateSurgery(SurgeryRecord s) async {
    await _c.put('/customers/me/surgeries/${s.id}', {'surgeryName': s.name, 'surgeryDate': ymd(s.date)});
    await _reloadSection('surgeries');
  }

  @override
  Future<void> deleteSurgery(String id) async {
    await _c.delete('/customers/me/surgeries/$id');
    await _reloadSection('surgeries');
  }

  @override
  Future<void> addAllergy(AllergyRecord a) async {
    await _c.post('/customers/me/allergies', {
      'allergyName': a.name,
      'onsetDate': ymd(a.onsetDate),
      'status': a.active ? 'active' : 'inactive',
    });
    await _reloadSection('allergies');
  }

  @override
  Future<void> updateAllergy(AllergyRecord a) async {
    await _c.put('/customers/me/allergies/${a.id}', {
      'allergyName': a.name,
      'onsetDate': ymd(a.onsetDate),
      'status': a.active ? 'active' : 'inactive',
    });
    await _reloadSection('allergies');
  }

  @override
  Future<void> deleteAllergy(String id) async {
    await _c.delete('/customers/me/allergies/$id');
    await _reloadSection('allergies');
  }

  @override
  Future<void> addInsurance(InsuranceRecord i) async {
    await _c.post('/customers/me/insurance', {
      'insuredWith': i.insuredWith,
      'policyNumber': i.policyNumber,
      'startDate': ymd(i.startDate),
      'endDate': ymd(i.endDate),
    });
    await _reloadSection('insurance');
  }

  @override
  Future<void> updateInsurance(InsuranceRecord i) async {
    await _c.put('/customers/me/insurance/${i.id}', {
      'insuredWith': i.insuredWith,
      'policyNumber': i.policyNumber,
      'startDate': ymd(i.startDate),
      'endDate': ymd(i.endDate),
    });
    await _reloadSection('insurance');
  }

  @override
  Future<void> deleteInsurance(String id) async {
    await _c.delete('/customers/me/insurance/$id');
    await _reloadSection('insurance');
  }

  @override
  Future<void> addFamilyMember(FamilyMember f) async {
    await _c.post('/customers/me/family', {
      'name': f.name,
      'relationship': f.relationship,
      'contactNumber': f.contact,
    });
    await _reloadSection('family');
  }

  @override
  Future<void> updateFamilyMember(FamilyMember f) async {
    await _c.put('/customers/me/family/${f.id}', {
      'name': f.name,
      'relationship': f.relationship,
      'contactNumber': f.contact,
    });
    await _reloadSection('family');
  }

  @override
  Future<void> removeFamilyMember(String id) async {
    await _c.delete('/customers/me/family/$id');
    await _reloadSection('family');
  }

  Future<void> _reloadSection(String section) async {
    final res = await _c.get('/customers/me/$section');
    final c = currentCustomer;
    if (c == null) return;
    switch (section) {
      case 'vitals':
        c.vitals = _list(res, 'vitals').map(_vitalFrom).toList();
        break;
      case 'medications':
        c.medications = _list(res, 'medications').map(_medicationFrom).toList();
        break;
      case 'surgeries':
        c.surgeries = _list(res, 'surgeries').map(_surgeryFrom).toList();
        break;
      case 'allergies':
        c.allergies = _list(res, 'allergies').map(_allergyFrom).toList();
        break;
      case 'insurance':
        c.insurance = _list(res, 'insurance').map(_insuranceFrom).toList();
        break;
      case 'family':
        c.family = _list(res, 'family').map(_familyFrom).toList();
        break;
    }
  }

  // ========================================================= providers ===
  @override
  Future<List<Provider>> search({
    required ServiceType type,
    String? gender,
    String? language,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? timeFrom,
    String? timeTo,
    double? lat,
    double? lng,
    double? radiusKm,
  }) async {
    final res = await _c.get('/providers/search', query: {
      'service_type': _serviceWire(type),
      if (dateFrom != null) 'date_from': ymd(dateFrom),
      if (dateTo != null) 'date_to': ymd(dateTo),
      if (timeFrom != null) 'time_from': '$timeFrom:00',
      if (timeTo != null) 'time_to': '$timeTo:00',
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (radiusKm != null) 'radius_km': radiusKm,
      if (gender != null && gender != 'Any') 'gender': gender.toLowerCase(),
      if (language != null && language != 'Any') 'language': language,
    });
    final providers = _list(res, 'providers').map(_providerFrom).toList();
    _cache(providers);
    return providers;
  }

  @override
  Future<Provider> providerById(String id) async {
    final res = await _c.get('/providers/$id');
    final p = _providerFrom(res as Map);
    _providerCache[p.id] = p;
    return p;
  }

  @override
  Future<void> linkProvider(String providerId) async {
    await _c.post('/customers/me/linked-providers', {'providerId': int.tryParse(providerId) ?? providerId});
    await _reloadLinked();
  }

  @override
  Future<void> unlinkProvider(String providerId) async {
    await _c.delete('/customers/me/linked-providers/$providerId');
    await _reloadLinked();
  }

  Future<void> _reloadLinked() async {
    final res = await _c.get('/customers/me/linked-providers');
    currentCustomer?.linkedProviderIds =
        _list(res, 'linkedProviders').map((r) => '${r['providerId']}').toList();
  }

  @override
  Future<List<Provider>> linkedProviders() async {
    final res = await _c.get('/customers/me/linked-providers');
    final providers = _list(res, 'linkedProviders').map((r) {
      return Provider(
        id: '${r['providerId']}',
        name: '${r['name']}',
        gender: '${r['gender'] ?? ''}',
        expertise: const [],
        hourlyRate: asDouble(r['hourlyRate']),
        noFees: asBool(r['noFees']),
        lat: 0,
        lng: 0,
        city: '',
        ratingAvg: asDouble(r['ratingAvg']) ?? 0,
        ratingCount: asInt(r['ratingCount']) ?? 0,
      );
    }).toList();
    _cache(providers);
    return providers;
  }

  // ========================================================== bookings ===
  @override
  Future<List<Booking>> allBookings() async {
    final scopes = await Future.wait([
      _c.get('/bookings', query: {'scope': 'current'}),
      _c.get('/bookings', query: {'scope': 'future'}),
      _c.get('/bookings', query: {'scope': 'past'}),
    ]);
    final seen = <String>{};
    final all = <Booking>[];
    for (final res in scopes) {
      for (final row in _list(res, 'bookings')) {
        final b = _bookingFrom(row);
        if (seen.add(b.id)) all.add(b);
      }
    }
    all.sort((a, b) => b.startDate.compareTo(a.startDate));
    return all;
  }

  @override
  Future<List<BookingMessage>> bookingMessages(String bookingId) async {
    final res = await _c.get('/bookings/$bookingId/messages') as Map;
    return ((res['messages'] as List?) ?? const [])
        .map((m) => BookingMessage(
              id: '${(m as Map)['id']}',
              sender: BookingMessage.senderFromWire('${m['senderType']}'),
              body: '${m['body'] ?? ''}',
              sentAt: asDate(m['createdAt']) ?? DateTime.now(),
              read: m['readAt'] != null,
            ))
        .toList();
  }

  @override
  Future<BookingMessage> sendBookingMessage(String bookingId, String body) async {
    final m = await _c.post('/bookings/$bookingId/messages', {'body': body}) as Map;
    return BookingMessage(
      id: '${m['id']}',
      sender: BookingMessage.senderFromWire('${m['senderType']}'),
      body: '${m['body'] ?? ''}',
      sentAt: asDate(m['createdAt']) ?? DateTime.now(),
    );
  }

  @override
  Future<SosResult> raiseSos({
    double? lat,
    double? lng,
    String? addressText,
    String? note,
  }) async {
    final res = await _c.post('/customers/me/sos', {
      if (lat != null) 'latitude': lat,
      if (lng != null) 'longitude': lng,
      if (addressText != null) 'addressText': addressText,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    }) as Map;

    return SosResult(
      alertId: '${res['alertId']}',
      delivery: '${res['delivery'] ?? 'simulated'}',
      smsIsLive: res['smsIsLive'] == true,
      notifiedCount: asInt(res['notifiedCount']) ?? 0,
      recipients: ((res['recipients'] as List?) ?? const [])
          .map((r) => SosRecipient(
                name: '${(r as Map)['name'] ?? ''}',
                relationship: r['relationship']?.toString(),
                number: '${r['number'] ?? ''}',
                notified: r['notified'] == true,
              ))
          .toList(),
    );
  }

  @override
  Future<Booking> createBooking({
    required List<String> providerIds,
    required ServiceType type,
    required DateTime start,
    required DateTime end,
    required String timeFrom,
    required String timeTo,
    FamilyMember? forMember,
  }) async {
    final address = primaryAddress();
    // The ids are numeric on the server and strings in the app. Anything that
    // will not parse is dropped rather than sent: the server would reject the
    // whole booking over one bad entry, and a carer the app cannot identify is
    // one it should not be asking for.
    final wire = providerIds
        .map((id) => int.tryParse(id))
        .whereType<int>()
        .toList();
    final res = await _c.post('/bookings', {
      'serviceType': _serviceWire(type),
      'startDate': ymd(start),
      'endDate': ymd(end),
      'timeFrom': '$timeFrom:00',
      'timeTo': '$timeTo:00',
      if (address != null) 'latitude': address.lat,
      if (address != null) 'longitude': address.lng,
      if (wire.isNotEmpty) 'providerIds': wire,
      if (currentCustomer?.referenceCode != null) 'referralCode': currentCustomer!.referenceCode,
      if (forMember != null) 'forFamilyMemberId': int.tryParse(forMember.id) ?? forMember.id,
    }) as Map;

    // The request fans out to every matching provider and the first to accept
    // gets it, so at this moment there is no provider and nothing to pay:
    // the booking is still `searching`. The 15-minute payment window starts
    // when somebody accepts, not now.
    return Booking(
      id: '${res['bookingId']}',
      customerId: currentCustomer?.id ?? '',
      providerId: '',
      serviceType: type,
      startDate: start,
      endDate: end,
      timeFrom: timeFrom,
      timeTo: timeTo,
      status: _statusFromWire('${res['status'] ?? 'searching'}'),
      bookingCharge: asDouble(res['bookingChargeAmount']) ?? 0,
      providersNotified: asInt(res['providersNotified']),
      askedNames: ((res['providers'] as List?) ?? const [])
          .map((p) => '${(p as Map)['name'] ?? ''}')
          .where((n) => n.isNotEmpty)
          .toList(),
      chosenByCustomer: res['chosenByCustomer'] == true,
      unavailableCount: asInt(res['unavailableCount']) ?? 0,
      forName: res['forName'] as String?,
      forRelationship: forMember?.relationship,
      forContactNumber: forMember?.contact,
    );
  }

  @override
  Future<Booking> refreshBooking(String bookingId) async {
    final res = await _c.get('/bookings/$bookingId');
    return _bookingFrom(res as Map);
  }

  @override
  Future<void> payBookingCharge(String bookingId) async {
    await _c.post('/bookings/$bookingId/pay', {});
  }

  @override
  CancellationQuote quoteCancellation(Booking b) => defaultCancellationQuote(b);

  @override
  Future<CancellationQuote> cancelBooking(String bookingId) async {
    final res = await _c.post('/bookings/$bookingId/cancel', {}) as Map;
    final fee = asDouble(pick(res, ['cancellationFeeAmount', 'cancellation_fee_amount', 'feeAmount'])) ?? 0;
    final refund = asDouble(pick(res, ['refundAmount', 'refund_amount'])) ?? 0;
    final hours = asDouble(pick(res, ['hoursBeforeStart', 'hours_before_start'])) ?? 0;
    return CancellationQuote(
      hoursBeforeStart: hours,
      feeAmount: fee,
      refundAmount: refund,
      rule: '${pick(res, ['policy', 'rule', 'message']) ?? 'Cancellation processed by the server.'}',
    );
  }

  @override
  Future<void> rateProvider(String bookingId, double rating, String comment) async {
    await _c.post('/bookings/$bookingId/rating', {'rating': rating.round(), 'comments': comment});
  }

  // The provider app performs these for real against a live server.
  @override
  Future<void> startServiceSimulation(String bookingId) async {
    throw Exception('In live mode the provider app starts the service — use the Sathiyaa Provider app.');
  }

  @override
  Future<void> completeService(String bookingId) async {
    throw Exception('In live mode the provider app ends the service — use the Sathiyaa Provider app.');
  }

  // =========================================================== parsing ===
  List<Map<String, dynamic>> _list(dynamic res, String key) {
    if (res is Map && res[key] is List) {
      return (res[key] as List).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    if (res is List) return res.cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
    return const [];
  }

  Customer _customerFrom(Map m) {
    final langs = m['preferredLanguages'];
    final modes = '${m['preferredCommMode'] ?? ''}'
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((s) => ContactMode.values.where((c) => c.name == s).firstOrNull)
        .whereType<ContactMode>()
        .toSet();

    return Customer(
      id: '${m['displayId'] ?? m['customerId']}',
      name: '${m['name'] ?? ''}',
      mobile: '${m['mobileNumber'] ?? ''}',
      email: m['email'] as String?,
      photoUrl: m['photoUrl'] as String?,
      dob: asDate(m['dob']),
      gender: m['gender'] == null ? null : _titleCase('${m['gender']}'),
      bloodGroup: m['bloodGroup'] as String?,
      preferredLanguages: langs is List ? langs.map((e) => '$e').toList() : <String>[],
      heightCm: asDouble(m['heightCm']),
      weightKg: asDouble(m['weightKg']),
      addresses: _list(m, 'addresses').map(_addressFrom).toList(),
      contactModes: modes,
      contactTimeframe: m['preferredCommTimeframe'] as String?,
      registrationFeePaid: asBool(m['registrationFeePaid']),
      // What the fee is today, per the admin console. Without this the app
      // showed the 499 it was compiled with and the server charged whatever
      // the console said.
      registrationFeeAmount: asDouble(m['registrationFeeAmount']) ?? 499,
      registrationRenewsAt: asDate(m['registrationRenewsAt']),
      registrationRenewalDue: asBool(m['registrationRenewalDue']),
      referenceCode: m['referralCode'] as String?,
      signupCity: m['signupCity'] as String?,
      signupInServiceArea: m['signupInServiceArea'] == null
          ? null
          : asBool(m['signupInServiceArea']),
      termsAccepted: m['termsPrivacyAcceptedAt'] != null,
      ratingAvg: asDouble(m['ratingAvg']) ?? 0,
      ratingCount: asInt(m['ratingCount']) ?? 0,
    );
  }

  Address _addressFrom(Map r) {
    final type = '${pick(r, ['address_type', 'addressType']) ?? 'primary'}';
    final isPrimary = type == 'primary';
    return Address(
      label: isPrimary ? 'Primary' : 'Secondary',
      line1: '${pick(r, ['line1']) ?? ''}',
      city: '${pick(r, ['city']) ?? ''}',
      lat: asDouble(pick(r, ['latitude', 'lat'])) ?? 0,
      lng: asDouble(pick(r, ['longitude', 'lng'])) ?? 0,
      isPrimary: isPrimary,
    );
  }

  VitalRecord _vitalFrom(Map r) => VitalRecord(
        id: '${r['id']}',
        date: asDate(pick(r, ['recorded_at', 'recordedAt'])) ?? DateTime.now(),
        type: VitalTypeMeta.fromWire('${pick(r, ['vital_type', 'vitalType']) ?? 'bp'}'),
        valuePrimary: asDouble(pick(r, ['value_primary', 'valuePrimary'])) ?? 0,
        valueSecondary: asDouble(pick(r, ['value_secondary', 'valueSecondary'])),
      );

  MedicationRecord _medicationFrom(Map r) => MedicationRecord(
        id: '${r['id']}',
        name: '${pick(r, ['medicine_name', 'medicineName']) ?? ''}',
        frequency: '${pick(r, ['frequency']) ?? ''}',
        prescriptionUrl: pick(r, ['prescription_url', 'prescriptionUrl'])?.toString(),
      );

  SurgeryRecord _surgeryFrom(Map r) => SurgeryRecord(
        id: '${r['id']}',
        name: '${pick(r, ['surgery_name', 'surgeryName']) ?? ''}',
        date: asDate(pick(r, ['surgery_date', 'surgeryDate'])) ?? DateTime.now(),
      );

  AllergyRecord _allergyFrom(Map r) => AllergyRecord(
        id: '${r['id']}',
        name: '${pick(r, ['allergy_name', 'allergyName']) ?? ''}',
        onsetDate: asDate(pick(r, ['onset_date', 'onsetDate'])) ?? DateTime.now(),
        active: '${pick(r, ['status']) ?? 'active'}' == 'active',
      );

  InsuranceRecord _insuranceFrom(Map r) => InsuranceRecord(
        id: '${r['id']}',
        insuredWith: '${pick(r, ['insured_with', 'insuredWith']) ?? ''}',
        policyNumber: '${pick(r, ['policy_number', 'policyNumber']) ?? ''}',
        startDate: asDate(pick(r, ['start_date', 'startDate'])) ?? DateTime.now(),
        endDate: asDate(pick(r, ['end_date', 'endDate'])) ?? DateTime.now(),
      );

  FamilyMember _familyFrom(Map r) => FamilyMember(
        id: '${r['id']}',
        name: '${pick(r, ['name']) ?? ''}',
        relationship: '${pick(r, ['relationship']) ?? ''}',
        contact: '${pick(r, ['contact_number', 'contactNumber']) ?? ''}',
        active: pick(r, ['deleted_at', 'deletedAt']) == null,
      );

  Provider _providerFrom(Map r) {
    final langs = r['languages'];
    final expertise = <ServiceType>[];
    final exp = r['expertise'];
    if (exp is List) {
      for (final e in exp) {
        final wire = e is Map ? '${pick(e, ['service_type', 'serviceType'])}' : '$e';
        final t = _serviceFromWire(wire);
        if (t != null) expertise.add(t);
      }
    }
    return Provider(
      id: '${r['providerId'] ?? r['provider_id'] ?? r['id']}',
      name: '${r['name'] ?? ''}',
      gender: _titleCase('${r['gender'] ?? ''}'),
      photoUrl: r['photoUrl'] as String?,
      expertise: expertise,
      ratingAvg: asDouble(r['ratingAvg']) ?? 0,
      ratingCount: asInt(r['ratingCount']) ?? 0,
      hourlyRate: asDouble(r['hourlyRate']),
      noFees: asBool(r['noFees']),
      lat: asDouble(r['latitude']) ?? 0,
      lng: asDouble(r['longitude']) ?? 0,
      city: '${r['city'] ?? ''}',
      languages: langs is List ? langs.map((e) => '$e').toList() : <String>[],
      distanceKm: asDouble(r['distanceKm']),
    );
  }

  Booking _bookingFrom(Map r) {
    final start = asDate(pick(r, ['startDate', 'start_date'])) ?? DateTime.now();
    final end = asDate(pick(r, ['endDate', 'end_date'])) ?? start;
    return Booking(
      id: '${pick(r, ['bookingId', 'booking_id', 'id'])}',
      customerId: currentCustomer?.id ?? '',
      providerId: '${pick(r, ['confirmedProviderId', 'confirmed_provider_id', 'providerId']) ?? ''}',
      serviceType: _serviceFromWire('${pick(r, ['serviceType', 'service_type'])}') ?? ServiceType.companion,
      startDate: start,
      endDate: end,
      timeFrom: shortTime(pick(r, ['timeFrom', 'time_from'])),
      timeTo: shortTime(pick(r, ['timeTo', 'time_to'])),
      status: _statusFromWire('${pick(r, ['status'])}'),
      bookingCharge: asDouble(pick(r, ['bookingChargeAmount', 'booking_charge_amount'])) ?? 0,
      bookingChargePaid: asBool(pick(r, ['bookingChargePaid', 'booking_charge_paid'])),
      paymentDeadline: asDate(pick(r, ['paymentDeadlineAt', 'payment_deadline_at'])),
      totalHours: asDouble(pick(r, ['totalHours', 'total_hours'])),
      totalAmount: asDouble(pick(r, ['totalAmount', 'total_amount', 'amount'])),
      providerName: pick(r, ['providerName', 'provider_name'])?.toString(),
      // Who the visit is for. Absent on a booking for the account holder,
      // which is what null means everywhere this is read.
      forName: pick(r, ['forName', 'for_name'])?.toString(),
      forRelationship: pick(r, ['forRelationship', 'for_relationship'])?.toString(),
      forContactNumber: pick(r, ['forContactNumber', 'for_contact_number'])?.toString(),
      unreadMessages: asInt(pick(r, ['unreadMessages', 'unread_messages'])) ?? 0,
    );
  }

  static String _serviceWire(ServiceType t) {
    switch (t) {
      case ServiceType.companion:
        return 'companion';
      case ServiceType.medicalCompanion:
        return 'medical_companion';
      case ServiceType.nurse:
        return 'nurse';
      case ServiceType.physiotherapy:
        return 'physiotherapy';
    }
  }

  static ServiceType? _serviceFromWire(String? w) {
    switch (w) {
      case 'companion':
        return ServiceType.companion;
      case 'medical_companion':
        return ServiceType.medicalCompanion;
      case 'nurse':
        return ServiceType.nurse;
      case 'physiotherapy':
        return ServiceType.physiotherapy;
      default:
        return null;
    }
  }

  static BookingStatus _statusFromWire(String w) {
    switch (w) {
      case 'searching':
        return BookingStatus.searching;
      case 'pending_payment':
        return BookingStatus.pendingPayment;
      case 'confirmed':
        return BookingStatus.confirmed;
      case 'in_progress':
        return BookingStatus.inProgress;
      case 'completed':
        return BookingStatus.completed;
      case 'cancelled':
      case 'expired':
        return BookingStatus.cancelled;
      default:
        return BookingStatus.pendingPayment;
    }
  }

  static String _titleCase(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1).toLowerCase()}';
}
