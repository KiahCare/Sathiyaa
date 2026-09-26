import 'dart:convert' show jsonDecode;

import 'package:flutter/foundation.dart' show debugPrint;
import '../backend.dart';
import '../models.dart';
import '../broadcasts.dart';
import '../service_area.dart';
import '../languages.dart';
import 'api_client.dart';
import '../i18n/l10n.dart';

/// Does this string point at something the *server* holds, rather than a file
/// sitting on this phone?
///
/// The old test was "does it start with a slash" — anything that did was
/// treated as a server path. On Android the image picker hands back
/// `/data/user/0/in.sathiyaa.provider/cache/scaled_1234.jpg`, which starts with
/// a slash too. So every document a provider chose was judged to be "already
/// uploaded", the upload was skipped, and the phone's own file path was written
/// into the database as the document URL. Registrations looked like they
/// worked; the admin console then had nothing to open, and the file had never
/// left the device.
///
/// Server references are exactly two shapes: an absolute http(s) URL, or a
/// path under `/uploads/`. Everything else is local.
bool isServerRef(String? ref) {
  if (ref == null || ref.isEmpty) return false;
  return ref.startsWith('http://') || ref.startsWith('https://') || ref.startsWith('/uploads/');
}

/// The real provider backend: Express + MySQL, over `docs/api-contract.md`.
///
/// The screens read `myBookings`, `calendarBlocks` and `currentProvider`
/// synchronously while building, so this class keeps local copies hydrated
/// from the server: every write goes out over HTTP and then refreshes what it
/// touched.
class ApiBackend implements SathiyaaProviderBackend {

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

  @override
  Future<String> uploadDocument(String filePath, {String category = 'photo'}) =>
      _c.uploadFile(filePath, category: category);
  final ApiClient _c;

  /// [onToken] is called whenever the session token changes — with the new
  /// token on sign-in, and null on sign-out. Injected rather than reaching for
  /// storage directly, so this class stays a pure API client: it does not know
  /// or care whether the token is being persisted, and it is usable in a test
  /// with no Flutter bindings.
  ApiBackend(String baseUrl, {String deviceId = 'sathiyaa-provider-app', this.onToken})
      : _c = ApiClient(baseUrl, deviceId: deviceId);

  final Future<void> Function(String? token)? onToken;

  @override
  ProviderProfile? currentProvider;

  final List<ProviderBooking> _bookings = [];
  final List<CalendarBlock> _blocks = [];
  final List<TimeBankEntry> _timeBank = [];

  @override
  List<ProviderBooking> get myBookings => List.unmodifiable(_bookings);

  @override
  List<CalendarBlock> get calendarBlocks => List.unmodifiable(_blocks);

  @override
  List<TimeBankEntry> get timeBank => List.unmodifiable(_timeBank);

  // ============================================================== auth ===
  @override
  Future<void> registerStart({required String name, required String mobile}) async {
    // Provider registration is a single call with the full payload; nothing to
    // do until the form is complete.
  }

  /// Documents that could not be uploaded during the last registration.
  ///
  /// Registration itself still succeeds; this lets the screen say which
  /// document needs adding again rather than failing the whole sign-up.
  List<String> lastRegistrationUploadFailures = const [];

  /// True for a path that has not been uploaded yet.
  ///
  /// The registration form holds local file paths until the account exists,
  /// because the upload endpoint needs a signed-in caller. Anything carrying a
  /// URI scheme is not a file on this phone — a server path, an http URL, or
  /// one of the `app://` placeholders older builds used — and must not be fed
  /// to the uploader.
  bool _isLocalFile(String? ref) => ref != null && ref.isNotEmpty && !isServerRef(ref);

  @override
  Future<ProviderProfile> completeRegistration(ProviderProfile draft) async {
    final res = await _c.post('/auth/provider/register', {
      'providerKind': _kindWire(draft.kind),
      'name': draft.name,
      'gender': draft.gender.toLowerCase(),
      'dob': draft.dob == null ? null : ymd(draft.dob!),
      'mobile': draft.mobile,
      'email': draft.email,
      'pin': draft.pin,
      'hourlyRate': draft.noFees ? 0 : (draft.hourlyRate ?? 0),
      'photoUrl': draft.photoUrl,
      // Local paths are meaningless to the server; the real URLs are PUT
      // immediately below, once this call has given us a token.
      'aadharDocUrl': _isLocalFile(draft.aadhar.url) ? null : draft.aadhar.url,
      'policeVerificationUrl':
          _isLocalFile(draft.policeVerification.url) ? null : draft.policeVerification.url,
      'workCertificateUrl':
          _isLocalFile(draft.workCertificate.url) ? null : draft.workCertificate.url,
      'deviceId': _c.deviceId,
      // What the carer actually said, not a constant. This line was
      // `const ['English']`, for every provider who ever registered, while the
      // customer app filtered and displayed on it.
      'languages': draft.languages,
      // The endpoint takes a list of addresses, not a single object.
      'addresses': [
        {
          'addressType': 'home',
          'line1': draft.address,
          'latitude': draft.lat,
          'longitude': draft.lng,
        }
      ],
      'workHours': _workHoursPayload(draft.workPref),
      'expertise': draft.expertise.map((e) => {'serviceType': _serviceWire(e)}).toList(),
    }) as Map;

    if (res['token'] != null) {
      _c.token = '${res['token']}';
      await onToken?.call(_c.token);
    }

    // Registration predates the No-Fees / document-validity fields, so they
    // are set straight afterwards through the profile endpoint that does
    // understand them.
    // Now that there is a token, send the documents that were chosen during
    // the form. Each is uploaded and the resulting URL saved on the profile.
    //
    // A failure here must not lose the account: registration has already
    // succeeded on the server, and throwing would leave the provider with an
    // account they cannot see and a screen that looks like it failed. A
    // document that did not make it can be added again from the profile.
    final uploads = <String, String>{};
    final failedUploads = <String>[];
    for (final entry in <String, ProviderDocument>{
      'aadharDocUrl': draft.aadhar,
      'policeVerificationUrl': draft.policeVerification,
      'workCertificateUrl': draft.workCertificate,
      'medicalCertificateUrl': draft.medicalCertificate,
      'orgRegistrationUrl': draft.registrationCertificate,
    }.entries) {
      final path = entry.value.url;
      if (!_isLocalFile(path)) continue;
      final category = switch (entry.key) {
        'aadharDocUrl' => 'aadhar',
        'policeVerificationUrl' => 'police-verification',
        'workCertificateUrl' => 'work-certificate',
        'orgRegistrationUrl' => 'org-registration',
        _ => 'medical-certificate',
      };
      try {
        uploads[entry.key] = await _c.uploadFile(path!, category: category);
      } catch (e) {
        debugPrint('[register] could not upload $category: $e');
        failedUploads.add(category);
      }
    }
    lastRegistrationUploadFailures = failedUploads;

    final extras = <String, dynamic>{
      ...uploads,
      if (draft.noFees) 'noFees': true,
      if (draft.policeVerification.validFrom != null)
        'policeVerificationValidFrom': _d(draft.policeVerification.validFrom),
      if (draft.policeVerification.validTo != null)
        'policeVerificationValidTo': _d(draft.policeVerification.validTo),
      // Only when it is already a server URL. A local path here would land
      // after the `...uploads` spread above and overwrite the URL the upload
      // just returned, sending the phone's own filename to the server.
      if (!_isLocalFile(draft.medicalCertificate.url) && draft.medicalCertificate.url != null)
        'medicalCertificateUrl': draft.medicalCertificate.url,
      if (draft.medicalCertificate.validFrom != null)
        'medicalCertificateValidFrom': _d(draft.medicalCertificate.validFrom),
      if (draft.medicalCertificate.validTo != null)
        'medicalCertificateValidTo': _d(draft.medicalCertificate.validTo),
      if (draft.kind == ProviderKind.organization && draft.allocateViaOrg) 'allocateViaOrg': true,
      if (draft.contactPerson != null && draft.contactPerson!.isNotEmpty)
        'contactPerson': draft.contactPerson,
      if (draft.gstNumber != null && draft.gstNumber!.isNotEmpty)
        'gstNumber': draft.gstNumber,
    };
    if (extras.isNotEmpty) await _c.put('/providers/me', extras);

    await refresh();
    return currentProvider ?? draft;
  }

  @override
  Future<void> loginWithPin(String mobile, String pin) async {
    final res = await _c.post('/auth/provider/login', {
      'mobile': mobile,
      'pin': pin,
      'deviceId': _c.deviceId,
    }) as Map;
    _c.token = '${res['token']}';
    await onToken?.call(_c.token);
    await refresh();
  }

  /// Reinstates a token read back from storage at startup, without a login.
  void restoreToken(String? token) => _c.token = token;

  /// The token this client is currently using, so it can be persisted.
  String? get currentToken => _c.token;

  @override
  Future<void> signOut() async {
    _c.token = null;
    currentProvider = null;
    _bookings.clear();
    _blocks.clear();
    _timeBank.clear();
    await onToken?.call(null);
  }

  // =========================================================== loading ===
  @override
  Future<void> refresh() async {
    final me = await _c.get('/providers/me') as Map;
    currentProvider = _profileFrom(me);

    final results = await Future.wait([
      _c.get('/providers/me/requests'),
      _c.get('/providers/me/appointments', query: {'scope': 'future'}),
      _c.get('/providers/me/appointments', query: {'scope': 'past'}),
      _c.get('/providers/me/time-bank'),
      _c.get('/providers/me/calendar-blocks'),
      if (currentProvider!.kind == ProviderKind.organization) _c.get('/providers/employees'),
    ]);

    final seen = <String>{};
    _bookings
      ..clear()
      ..addAll([
        ..._rows(results[0], ['requests', 'bookings']),
        ..._rows(results[1], ['appointments', 'bookings']),
        ..._rows(results[2], ['appointments', 'bookings']),
      ].map(_bookingFrom).where((b) => seen.add(b.id)));

    _timeBank
      ..clear()
      ..addAll(_rows(results[3], ['ledger', 'entries', 'sessions']).map(_timeBankFrom));

    _blocks
      ..clear()
      ..addAll(_rows(results[4], ['calendarBlocks']).map(_blockFrom));

    if (results.length > 5) {
      currentProvider!.employees = _rows(results[5], ['employees']).map(_employeeFrom).toList();
    }
  }

  // =================================================== availability ======
  @override
  Future<void> setLanguages(List<String> languages) async {
    await _c.put('/providers/me', {'languages': languages});
    currentProvider
      ?..languages = List<String>.from(languages)
      ..languagesConfirmed = true;
  }

  @override
  Future<void> setLocationOn(bool on) async {
    await _c.put('/providers/me', {'locationOn': on});
    currentProvider?.locationOn = on;
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
    final res = await _c.put('/providers/me/signup-place', place.toJson());
    final inside = asBool((res as Map)['inServiceArea']);
    currentProvider
      ?..signupInServiceArea = inside
      ..signupCity = place.city;
    return inside;
  }

  @override
  Future<void> pingLocation(double lat, double lng) async {
    await _c.patch('/providers/me/location', {'lat': lat, 'lng': lng});
    currentProvider
      ?..currentLat = lat
      ..currentLng = lng;
  }

  // =============================================== service delivery ======
  @override
  Future<void> acceptBooking(String id) async {
    if (currentProvider?.locationOn != true) {
      throw Exception('Turn location sharing on before accepting a request.');
    }
    await _c.post('/providers/me/requests/$id/accept', {});
    await refresh();
  }

  @override
  Future<void> rejectBooking(String id) async {
    await _c.post('/providers/me/requests/$id/reject', {});
    await refresh();
  }

  @override
  Future<void> transferBooking(String id, String toEmployeeId) async {
    await _c.post('/providers/me/bookings/$id/reallocate', {'employeeId': int.tryParse(toEmployeeId) ?? toEmployeeId});
    await refresh();
  }

  @override
  Future<void> sendRunningLate(String id, String eta) async {
    final minutes = int.tryParse(eta.split(' ').first) ?? 15;
    await _c.post('/providers/me/bookings/$id/running-late', {'minutes': minutes});
    final b = _find(id);
    b?.runningLateSent = true;
    b?.runningLateEta = eta;
  }

  @override
  Future<FaceCheckResult> verifyFaceAndGeofence(String id, {String? selfiePath}) async {
    final p = currentProvider;
    if (p == null || !p.locationOn) {
      return FaceCheckResult(passed: false, message: t('Location sharing is off — turn it on to start the service.'));
    }
    try {
      // A real photo, taken seconds ago on this phone, uploaded and kept with
      // the booking. This used to send the literal string 'app://selfie-capture'
      // -- no camera was opened and nothing was stored, so the arrival check
      // proved nothing and an admin had no photo to look at.
      String? selfieUrl;
      if (selfiePath != null && selfiePath.isNotEmpty) {
        selfieUrl = await _c.uploadFile(selfiePath, category: 'selfie');
      }

      // The server runs the face-match provider *and* the real geofence check,
      // and issues the customer's OTP if both pass.
      final res = await _c.post('/providers/me/bookings/$id/start', {
        'selfieUrl': selfieUrl,
      }) as Map;
      final b = _find(id);
      b?.faceVerifiedAt = DateTime.now();
      // The OTP goes to the customer, not to us; the server echoes it only in
      // dev builds.
      final devOtp = pick(res, ['devOtp', 'otp']);
      if (devOtp != null) b?.otp = '$devOtp';
      return FaceCheckResult(
        passed: true,
        distanceKm: asDouble(pick(res, ['distanceKm'])),
        message: '${pick(res, ['message']) ?? 'Face matched and you are on site. OTP sent to the customer.'}',
      );
    } on ApiException catch (e) {
      return FaceCheckResult(passed: false, message: e.message);
    }
  }

  @override
  Future<String> startService(String id) async {
    final b = _find(id);
    if (b?.faceVerifiedAt == null) {
      throw Exception('Complete the face and location check first.');
    }
    // The server issued the OTP during the start call; the customer reads it
    // from their own app.
    return b?.otp ?? '——————';
  }

  @override
  Future<void> confirmOtpAndStart(String id, String enteredOtp) async {
    await _c.post('/providers/me/bookings/$id/verify-start-otp', {'otp': enteredOtp});
    await refresh();
  }

  @override
  Future<void> endService(String id) async {
    await _c.post('/providers/me/bookings/$id/end', {});
    await refresh();
  }

  @override
  Future<void> recordPayment(String id, double amount, {required bool full}) async {
    await _c.post('/providers/me/bookings/$id/payments', {
      'amount': amount,
      'paymentType': full ? 'full' : 'part',
    });
    await refresh();
  }

  @override
  Future<void> sendPaymentReminder(String id) async {
    await _c.post('/providers/me/bookings/$id/payment-reminder', {});
    _find(id)?.paymentReminderSentAt = DateTime.now();
  }

  @override
  Future<void> rateCustomer(String id, double rating, String comment) async {
    await _c.post('/providers/me/bookings/$id/rate-customer', {
      'rating': rating.round(),
      'comments': comment,
    });
    final b = _find(id);
    b?.customerRatingByProvider = rating;
    b?.customerCommentByProvider = comment;
  }

  @override
  Future<void> orgCancel(String id) async {
    await _c.post('/providers/me/bookings/$id/org-cancel', {});
    await refresh();
  }

  // ========================================================== calendar ===
  @override
  bool isBlocked(DateTime day) => _blocks.any((b) => b.covers(day));

  @override
  List<ProviderBooking> bookingsOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return _bookings.where((b) {
      if (b.status == BookingStatus.cancelled) return false;
      final from = DateTime(b.startDate.year, b.startDate.month, b.startDate.day);
      final to = DateTime(b.endDate.year, b.endDate.month, b.endDate.day);
      return !d.isBefore(from) && !d.isAfter(to);
    }).toList();
  }

  @override
  bool worksOn(DateTime day) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return currentProvider?.workPref.days.contains(names[day.weekday - 1]) ?? false;
  }

  @override
  double freeHoursOn(DateTime day) {
    if (!worksOn(day) || isBlocked(day)) return 0;
    final pref = currentProvider!.workPref;
    final total = hoursBetween(pref.timeFrom, pref.timeTo);
    final booked = bookingsOn(day).fold<double>(0, (sum, b) => sum + hoursBetween(b.timeFrom, b.timeTo));
    final left = total - booked;
    return left < 0 ? 0 : left;
  }

  @override
  Future<CalendarBlock> blockCalendar({required DateTime from, required DateTime to, String reason = ''}) async {
    final clash = _bookings.where((b) {
      if (b.status == BookingStatus.cancelled || b.status == BookingStatus.completed) return false;
      return !(b.endDate.isBefore(from) || b.startDate.isAfter(to));
    }).toList();
    if (clash.isNotEmpty) {
      throw Exception('You have ${clash.length} booking(s) in that range — transfer or finish them first.');
    }
    final res = await _c.post('/providers/me/calendar-blocks', {
      'blockStart': '${ymd(from)} 00:00:00',
      'blockEnd': '${ymd(to)} 23:59:59',
      'reason': reason,
    });
    final block = res is Map
        ? _blockFrom(res.cast<String, dynamic>())
        : CalendarBlock(id: '${DateTime.now().millisecondsSinceEpoch}', from: from, to: to, reason: reason);
    _blocks.add(block);
    return block;
  }

  @override
  Future<void> unblockCalendar(String id) async {
    await _c.delete('/providers/me/calendar-blocks/$id');
    _blocks.removeWhere((b) => b.id == id);
  }

  // ========================================= dashboard & organization ===
  @override
  DashboardStats statsFor(String period, {String? employeeId}) {
    // Computed from the bookings already loaded, so the period selector stays
    // instant instead of issuing a request per change. `/providers/me/dashboard`
    // is the server-side equivalent if these ever need to differ.
    final from = periodStart(period, DateTime.now());
    var scoped = _bookings.where((b) => !b.startDate.isBefore(from)).toList();
    if (employeeId != null) {
      scoped = scoped.where((b) => b.assignedEmployeeId == employeeId).toList();
    }
    final done = scoped.where((b) => b.status == BookingStatus.completed).toList();
    return DashboardStats(
      appointments: scoped.length,
      revenue: done.fold<double>(0, (s, b) => s + b.amountReceived),
      pending: done.fold<double>(0, (s, b) => s + (b.amountDue - b.amountReceived)),
      hours: done.fold<double>(0, (s, b) => s + (b.totalHours ?? 0)),
    );
  }

  @override
  Map<String, dynamic> utilizationFor(String employeeId) {
    final stats = statsFor('Annual', employeeId: employeeId);
    return {
      'appointments': stats.appointments,
      'businessDone': stats.revenue,
      'pending': stats.pending,
      'rating': currentProvider?.ratingAvg ?? 0,
    };
  }

  @override
  Future<void> addEmployee(Employee e) async {
    await _c.post('/providers/employees', _employeePayload(await _uploadEmployeeDocuments(e)));
    await refresh();
  }

  @override
  Future<void> updateEmployee(Employee e) async {
    await _c.put('/providers/employees/${e.id}',
        _employeePayload(await _uploadEmployeeDocuments(e)));
    await refresh();
  }

  @override
  Future<void> setEmployeeStatus(String id, EmployeeStatus status) async {
    await _c.patch('/providers/employees/$id/status', {
      'status': status == EmployeeStatus.active ? 'active' : 'blocked',
    });
    await refresh();
  }

  @override
  Future<void> toggleAllocateViaOrg(bool value) async {
    await _c.put('/providers/me', {'allocateViaOrg': value});
    currentProvider?.allocateViaOrg = value;
  }

  Map<String, dynamic> _employeePayload(Employee e) => {
        'name': e.name,
        'gender': e.gender.toLowerCase(),
        'mobile': e.mobile,
        // updateEmployee reads mobileNumber, addEmployee reads mobile. Both
        // are sent rather than making the caller know which endpoint it is
        // about to hit.
        'mobileNumber': e.mobile,
        if (e.dob != null) 'dob': _d(e.dob),
        'address': {
          'line1': e.address,
          if (e.lat != null) 'latitude': e.lat,
          if (e.lng != null) 'longitude': e.lng,
        },
        'distanceFromHomePrefKm': e.distanceFromHomeKm,
        'distanceFromOfficePrefKm': e.distanceFromOfficeKm,
        'workHours': _workHoursPayload(e.workPref),
        'expertise': e.expertise.map((x) => {'serviceType': _serviceWire(x)}).toList(),
        'languages': e.languages,
        // Only when they are server URLs. A local path would be stored
        // verbatim and the admin console would show a filename off somebody's
        // phone where a document should be -- which is the bug that lost the
        // provider documents once already.
        if (!_isLocalFile(e.aadhar.url)) 'aadharDocUrl': e.aadhar.url,
        if (!_isLocalFile(e.policeVerification.url))
          'policeVerificationUrl': e.policeVerification.url,
        if (e.policeVerification.validFrom != null)
          'policeVerificationValidFrom': _d(e.policeVerification.validFrom),
        if (e.policeVerification.validTo != null)
          'policeVerificationValidTo': _d(e.policeVerification.validTo),
        if (!_isLocalFile(e.medicalCertificate.url))
          'medicalCertificateUrl': e.medicalCertificate.url,
        if (e.medicalCertificate.validFrom != null)
          'medicalCertificateValidFrom': _d(e.medicalCertificate.validFrom),
        if (e.medicalCertificate.validTo != null)
          'medicalCertificateValidTo': _d(e.medicalCertificate.validTo),
      };

  /// Uploads any document that is still a local file, and returns a copy of
  /// [e] holding the server URLs.
  ///
  /// Unlike registration, the organisation is already signed in here, so the
  /// upload can happen before the employee is created rather than after --
  /// which means a carer is never written to the database with a phone path
  /// where a document URL belongs.
  Future<Employee> _uploadEmployeeDocuments(Employee e) async {
    Future<ProviderDocument> up(ProviderDocument d, String category) async {
      if (!_isLocalFile(d.url)) return d;
      try {
        final url = await _c.uploadFile(d.url!, category: category);
        return ProviderDocument(url: url, validFrom: d.validFrom, validTo: d.validTo);
      } catch (err) {
        debugPrint('[employee] could not upload $category: $err');
        // Keep the local path out of the payload rather than failing the
        // whole save: the carer is still worth creating, and the document
        // can be added again from their record.
        return ProviderDocument(validFrom: d.validFrom, validTo: d.validTo);
      }
    }

    return Employee(
      id: e.id,
      name: e.name,
      gender: e.gender,
      mobile: e.mobile,
      dob: e.dob,
      address: e.address,
      workPref: e.workPref,
      expertise: e.expertise,
      languages: e.languages,
      distanceFromHomeKm: e.distanceFromHomeKm,
      distanceFromOfficeKm: e.distanceFromOfficeKm,
      status: e.status,
      aadhar: await up(e.aadhar, 'aadhar'),
      policeVerification: await up(e.policeVerification, 'police-verification'),
      medicalCertificate: await up(e.medicalCertificate, 'medical-certificate'),
    );
  }

  /// One row per working day, carrying that day's own hours.
  static List<Map<String, dynamic>> _workHoursPayload(WorkPreference w) => w.days
      .map((d) {
        final h = w.hoursFor(d);
        return {
          'dayOfWeek': d.toLowerCase().substring(0, 3),
          'startTime': '${h.from}:00',
          'endTime': '${h.to}:00',
        };
      })
      .toList();

  // =========================================================== helpers ===
  ProviderBooking? _find(String id) {
    for (final b in _bookings) {
      if (b.id == id) return b;
    }
    return null;
  }

  List<Map<String, dynamic>> _rows(dynamic res, List<String> keys) {
    if (res is Map) {
      for (final k in keys) {
        if (res[k] is List) {
          return (res[k] as List).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
        }
      }
    }
    if (res is List) return res.cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
    return const [];
  }

  ProviderProfile _profileFrom(Map m) {
    final address = m['address'] is Map ? m['address'] as Map : const {};
    final workHours = m['workHours'] is List ? (m['workHours'] as List) : const [];
    const dayNames = {'mon': 'Mon', 'tue': 'Tue', 'wed': 'Wed', 'thu': 'Thu', 'fri': 'Fri', 'sat': 'Sat', 'sun': 'Sun'};

    // Keep each day's own hours. Reading them into one pair of variables let
    // whichever row came last decide the hours for the whole week.
    final days = <String>[];
    final hoursByDay = <String, DayHours>{};
    for (final w in workHours) {
      if (w is! Map) continue;
      final d = dayNames['${pick(w, ['dayOfWeek', 'day_of_week'])}'];
      if (d == null) continue;
      days.add(d);
      hoursByDay[d] = DayHours(
        shortTime(pick(w, ['startTime', 'start_time']) ?? '09:00:00'),
        shortTime(pick(w, ['endTime', 'end_time']) ?? '18:00:00'),
      );
    }

    // The window most days share becomes the default, and the rest are
    // exceptions -- which is how the form asks the question, so a profile
    // opened for editing shows what was actually entered.
    var from = '09:00';
    var to = '18:00';
    if (hoursByDay.isNotEmpty) {
      final tally = <DayHours, int>{};
      for (final h in hoursByDay.values) {
        tally[h] = (tally[h] ?? 0) + 1;
      }
      final commonest = tally.entries.reduce((a, b) => b.value > a.value ? b : a).key;
      from = commonest.from;
      to = commonest.to;
    }
    final exceptions = <String, DayHours>{
      for (final e in hoursByDay.entries)
        if (e.value != DayHours(from, to)) e.key: e.value,
    };

    final expertise = <ServiceType>[];
    if (m['expertise'] is List) {
      for (final e in m['expertise'] as List) {
        final wire = e is Map ? '${pick(e, ['serviceType', 'service_type'])}' : '$e';
        final t = _serviceFromWire(wire);
        if (t != null) expertise.add(t);
      }
    }

    return ProviderProfile(
      id: '${pick(m, ['displayId']) ?? pick(m, ['providerId'])}',
      kind: _kindFromWire('${pick(m, ['providerKind', 'provider_kind'])}'),
      name: '${m['name'] ?? ''}',
      photoUrl: m['photoUrl'] as String?,
      gender: _titleCase('${m['gender'] ?? ''}'),
      dob: asDate(m['dob']),
      mobile: '${pick(m, ['mobileNumber', 'mobile']) ?? ''}',
      email: m['email'] as String?,
      address: '${pick(address, ['line1']) ?? ''}',
      lat: asDouble(pick(address, ['latitude'])) ?? 0,
      lng: asDouble(pick(address, ['longitude'])) ?? 0,
      languages: _languagesFrom(m['languages']),
      workPref: WorkPreference(
        days: days.isEmpty ? null : days,
        timeFrom: from,
        timeTo: to,
        perDay: exceptions,
      ),
      expertise: expertise,
      hourlyRate: asDouble(m['hourlyRate']),
      noFees: asBool(m['noFees']),
      contactPerson: pick(m, ['contactPerson']) as String?,
      gstNumber: pick(m, ['gstNumber']) as String?,
      registrationCertificate:
          ProviderDocument(url: pick(m, ['orgRegistrationUrl']) as String?),
      approvalStatus: '${m['approvalStatus'] ?? 'pending'}',
      approved: '${m['approvalStatus']}' == 'approved',
      ratingAvg: asDouble(m['ratingAvg']) ?? 0,
      ratingCount: asInt(m['ratingCount']) ?? 0,
      allocateViaOrg: asBool(m['allocateViaOrg']),
      locationOn: asBool(m['locationOn']),
      languagesConfirmed: asBool(m['languagesConfirmed']),
      signupCity: m['signupCity'] as String?,
      signupInServiceArea:
          m['signupInServiceArea'] == null ? null : asBool(m['signupInServiceArea']),
      currentLat: asDouble(pick(m, ['currentLatitude'])),
      currentLng: asDouble(pick(m, ['currentLongitude'])),
      aadhar: ProviderDocument(url: m['aadharDocUrl'] as String?),
      policeVerification: ProviderDocument(
        url: m['policeVerificationUrl'] as String?,
        validFrom: asDate(m['policeVerificationValidFrom']),
        validTo: asDate(m['policeVerificationValidTo']),
      ),
      medicalCertificate: ProviderDocument(
        url: m['medicalCertificateUrl'] as String?,
        validFrom: asDate(m['medicalCertificateValidFrom']),
        validTo: asDate(m['medicalCertificateValidTo']),
      ),
      workCertificate: ProviderDocument(url: m['workCertificateUrl'] as String?),
    );
  }

  @override
  Future<List<BookingMessage>> bookingMessages(String bookingId) async {
    final res = await _c.get('/providers/me/bookings/$bookingId/messages') as Map;
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
    final m = await _c.post('/providers/me/bookings/$bookingId/messages', {'body': body}) as Map;
    return BookingMessage(
      id: '${m['id']}',
      sender: BookingMessage.senderFromWire('${m['senderType']}'),
      body: '${m['body'] ?? ''}',
      sentAt: asDate(m['createdAt']) ?? DateTime.now(),
    );
  }

  ProviderBooking _bookingFrom(Map r) {
    final start = asDate(pick(r, ['startDate', 'start_date'])) ?? DateTime.now();
    final end = asDate(pick(r, ['endDate', 'end_date'])) ?? start;
    return ProviderBooking(
      id: '${pick(r, ['bookingId', 'booking_id', 'id'])}',
      customerId: '${pick(r, ['customerId', 'customer_id']) ?? ''}',
      customerName: '${pick(r, ['customerName', 'customer_name']) ?? 'Customer'}',
      unreadMessages: asInt(pick(r, ['unreadMessages', 'unread_messages'])) ?? 0,
      forName: pick(r, ['forName', 'for_name'])?.toString(),
      forRelationship: pick(r, ['forRelationship', 'for_relationship'])?.toString(),
      forContactNumber: pick(r, ['forContactNumber', 'for_contact_number'])?.toString(),
      forDateOfBirth: asDate(pick(r, ['forDateOfBirth', 'for_date_of_birth'])),
      forNotes: pick(r, ['forNotes', 'for_notes'])?.toString(),
      providerId: '${pick(r, ['providerId', 'provider_id']) ?? currentProvider?.id ?? ''}',
      assignedEmployeeId: pick(r, ['assignedEmployeeId', 'assigned_employee_id'])?.toString(),
      serviceType: _serviceFromWire('${pick(r, ['serviceType', 'service_type'])}') ?? ServiceType.companion,
      startDate: start,
      endDate: end,
      timeFrom: shortTime(pick(r, ['timeFrom', 'time_from'])),
      timeTo: shortTime(pick(r, ['timeTo', 'time_to'])),
      customerAddress: '${pick(r, ['customer_address', 'customerAddress', 'address']) ?? ''}',
      customerMobile: pick(r, ['customer_mobile', 'customerMobile'])?.toString(),
      customerBloodGroup: pick(r, ['customer_blood_group', 'customerBloodGroup'])?.toString(),
      customerCommMode: pick(r, ['customer_comm_mode', 'customerCommMode'])?.toString(),
      customerCommTimeframe: pick(r, ['customer_comm_timeframe', 'customerCommTimeframe'])?.toString(),
      customerLat: asDouble(pick(r, ['latitude', 'customerLat'])) ?? 0,
      customerLng: asDouble(pick(r, ['longitude', 'customerLng'])) ?? 0,
      status: _statusFromWire('${pick(r, ['status'])}'),
      totalHours: asDouble(pick(r, ['totalHours', 'total_hours'])),
      amountDue: asDouble(pick(r, ['amountDue', 'amount_due'])) ?? 0,
      amountReceived: asDouble(pick(r, ['amountReceived', 'amount_received'])) ?? 0,
      paymentStatus: _paymentFromWire('${pick(r, ['paymentStatus', 'payment_status'])}'),
    );
  }

  CalendarBlock _blockFrom(Map r) => CalendarBlock(
        id: '${pick(r, ['id', 'blockId'])}',
        from: asDate(pick(r, ['blockStart', 'block_start'])) ?? DateTime.now(),
        to: asDate(pick(r, ['blockEnd', 'block_end'])) ?? DateTime.now(),
        reason: '${pick(r, ['reason']) ?? ''}',
      );

  TimeBankEntry _timeBankFrom(Map r) => TimeBankEntry(
        id: '${pick(r, ['id']) ?? ''}',
        date: asDate(pick(r, ['sessionDate', 'session_date', 'createdAt', 'created_at'])) ?? DateTime.now(),
        serviceType: _serviceFromWire('${pick(r, ['serviceType', 'service_type'])}') ?? ServiceType.companion,
        hours: asDouble(pick(r, ['hours', 'totalHours', 'total_hours'])) ?? 0,
        points: asDouble(pick(r, ['points', 'pointsCredited'])) ?? 0,
      );

  /// The languages column is JSON, and comes back as a List from MySQL's
  /// JSON type or as a string from a driver that did not parse it. Both
  /// happen, so both are handled rather than one being assumed.
  static List<String> _languagesFrom(dynamic raw) {
    if (raw is List) return raw.map((e) => '$e').where((s) => s.isNotEmpty).toList();
    if (raw is String && raw.trim().startsWith('[')) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is List) return parsed.map((e) => '$e').toList();
      } catch (_) {
        // Not JSON after all; fall through to the default.
      }
    }
    return List<String>.from(kDefaultLanguages);
  }

  Employee _employeeFrom(Map r) => Employee(
        id: '${pick(r, ['providerId', 'provider_id', 'id'])}',
        name: '${r['name'] ?? ''}',
        gender: _titleCase('${r['gender'] ?? ''}'),
        mobile: '${pick(r, ['mobileNumber', 'mobile']) ?? ''}',
        dob: asDate(r['dob']),
        languages: _languagesFrom(r['languages']),
        address: '${(r['address'] is Map ? pick(r['address'] as Map, ['line1']) : r['address']) ?? ''}',
        lat: r['address'] is Map ? asDouble((r['address'] as Map)['latitude']) : null,
        lng: r['address'] is Map ? asDouble((r['address'] as Map)['longitude']) : null,
        approvalStatus: '${r['approvalStatus'] ?? 'pending'}',
        workPref: _workPrefFrom(r['workHours']),
        distanceFromHomeKm: asDouble(pick(r, ['distanceFromHomePrefKm'])),
        distanceFromOfficeKm: asDouble(pick(r, ['distanceFromOfficePrefKm'])),
        status: '${r['status']}' == 'blocked' ? EmployeeStatus.blocked : EmployeeStatus.active,
        // Read back so the staff list can say who is actually allocatable.
        aadhar: ProviderDocument(url: pick(r, ['aadharDocUrl']) as String?),
        policeVerification: ProviderDocument(
          url: pick(r, ['policeVerificationUrl']) as String?,
          validFrom: asDate(pick(r, ['policeVerificationValidFrom'])),
          validTo: asDate(pick(r, ['policeVerificationValidTo'])),
        ),
        medicalCertificate: ProviderDocument(
          url: pick(r, ['medicalCertificateUrl']) as String?,
          validFrom: asDate(pick(r, ['medicalCertificateValidFrom'])),
          validTo: asDate(pick(r, ['medicalCertificateValidTo'])),
        ),
      );

  /// Turns the server's work-hours rows back into a [WorkPreference].
  ///
  /// The app has always sent these and never read them back, so reopening a
  /// carer to edit anything showed an empty week and saving wrote that empty
  /// week over what was there.
  static WorkPreference _workPrefFrom(dynamic raw) {
    if (raw is! List || raw.isEmpty) return WorkPreference();
    const names = {
      'sun': 'Sun', 'mon': 'Mon', 'tue': 'Tue', 'wed': 'Wed',
      'thu': 'Thu', 'fri': 'Fri', 'sat': 'Sat',
    };
    final days = <String>[];
    final perDay = <String, DayHours>{};
    for (final row in raw) {
      if (row is! Map) continue;
      final day = names['${row['dayOfWeek']}'.toLowerCase()];
      if (day == null) continue;
      final from = '${row['startTime'] ?? '09:00'}';
      final to = '${row['endTime'] ?? '18:00'}';
      days.add(day);
      perDay[day] = DayHours(from.substring(0, 5), to.substring(0, 5));
    }
    if (days.isEmpty) return WorkPreference();
    // The common window, so a carer who works the same hours every day does
    // not open the form with seven identical rows expanded.
    final first = perDay[days.first]!;
    final uniform = perDay.values.every((h) => h == first);
    return WorkPreference(
      days: days,
      timeFrom: first.from,
      timeTo: first.to,
      perDay: uniform ? {} : perDay,
    );
  }

  static String? _d(DateTime? d) => d == null ? null : ymd(d);

  static String _kindWire(ProviderKind k) {
    switch (k) {
      case ProviderKind.freelancer:
        return 'freelancer';
      case ProviderKind.organization:
        return 'organization';
      case ProviderKind.orgEmployee:
        return 'org_employee';
    }
  }

  static ProviderKind _kindFromWire(String w) {
    switch (w) {
      case 'organization':
        return ProviderKind.organization;
      case 'org_employee':
        return ProviderKind.orgEmployee;
      default:
        return ProviderKind.freelancer;
    }
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
      case 'pending_payment':
      case 'pending':
        return BookingStatus.requested;
      case 'confirmed':
      case 'accepted':
        return BookingStatus.accepted;
      case 'in_progress':
        return BookingStatus.inProgress;
      case 'completed':
        return BookingStatus.completed;
      case 'cancelled':
      case 'expired':
      case 'rejected':
      case 'invalidated':
        return BookingStatus.cancelled;
      default:
        return BookingStatus.requested;
    }
  }

  static PaymentStatus _paymentFromWire(String w) {
    switch (w) {
      case 'paid':
        return PaymentStatus.paid;
      case 'partial':
        return PaymentStatus.partial;
      default:
        return PaymentStatus.unpaid;
    }
  }

  static String _titleCase(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1).toLowerCase()}';
}

/// Start of the window for the dashboard's period selector. Shared by both
/// backends so the two agree on what "this quarter" means.
DateTime periodStart(String period, DateTime now) {
  switch (period) {
    case 'Week':
      return DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    case 'Month':
      return DateTime(now.year, now.month, 1);
    case 'Quarter':
      return DateTime(now.year, ((now.month - 1) ~/ 3) * 3 + 1, 1);
    case 'Annual':
      return DateTime(now.year, 1, 1);
    default: // Today
      return DateTime(now.year, now.month, now.day);
  }
}

/// Hours between two `HH:mm` strings, never negative.
double hoursBetween(String from, String to) {
  List<int> parse(String t) => t.split(':').map((v) => int.tryParse(v) ?? 0).toList();
  final f = parse(from);
  final t = parse(to);
  if (f.length < 2 || t.length < 2) return 0;
  final mins = (t[0] * 60 + t[1]) - (f[0] * 60 + f[1]);
  return mins <= 0 ? 0 : mins / 60.0;
}
