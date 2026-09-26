import 'dart:async';
import 'dart:math';

import 'api/api_backend.dart' show periodStart, hoursBetween;
import 'backend.dart';
import 'models.dart';
import 'broadcasts.dart';
import 'service_area.dart';
import './i18n/l10n.dart';

/// The offline backend: seeded demo data held in memory, with the same surface
/// as the live one so every screen works identically with no server.
class MockBackend implements SathiyaaProviderBackend {

  /// Demo mode has no server, so a picked file is shown straight from disk and
  /// there is nothing to resolve.
  @override
  String? absoluteUrl(String? ref) => null;

  @override
  Future<String> uploadDocument(String filePath, {String category = 'photo'}) async {
    await _delay(400);
    // Offline there is nowhere to upload to; the local path is the reference,
    // which is exactly what avatarImage falls back to reading.
    return filePath;
  }
  MockBackend._internal() {
    _seed();
  }
  static final MockBackend instance = MockBackend._internal();

  final _rand = Random();
  @override
  ProviderProfile? currentProvider;
  final List<ProviderBooking> bookings = [];

  @override
  Future<void> refresh() async {}

  /// Threads per booking, so a conversation survives leaving the screen.
  final Map<String, List<BookingMessage>> _threads = {};

  @override
  Future<List<BookingMessage>> bookingMessages(String bookingId) async {
    await _delay(250);
    final b = bookings.firstWhere((x) => x.id == bookingId);
    if (b.status == BookingStatus.requested) {
      throw Exception('Messages open once you have accepted the job.');
    }
    final thread = _threads.putIfAbsent(bookingId, () => [
          BookingMessage(
            id: 'm-seed',
            sender: MessageSender.system,
            body: 'Booking confirmed. You can message each other here.',
            sentAt: DateTime.now().subtract(const Duration(minutes: 50)),
            read: true,
          ),
          BookingMessage(
            id: 'm-seed-2',
            sender: MessageSender.customer,
            body: 'The gate code is 4417. Please knock rather than ring.',
            sentAt: DateTime.now().subtract(const Duration(minutes: 35)),
            read: true,
          ),
        ]);
    b.unreadMessages = 0;
    return List.of(thread);
  }

  @override
  Future<BookingMessage> sendBookingMessage(String bookingId, String body) async {
    await _delay(220);
    final m = BookingMessage(
      id: 'm-${DateTime.now().microsecondsSinceEpoch}',
      sender: MessageSender.provider,
      body: body.trim(),
      sentAt: DateTime.now(),
    );
    _threads.putIfAbsent(bookingId, () => []).add(m);
    return m;
  }

  @override
  Future<void> signOut() async {
    // The account stays in _accounts. Before this, signing out dropped the only
    // reference to it and loginWithPin — which checked the PIN against
    // currentProvider — answered "Incorrect PIN" to every PIN forever. On demo
    // data, logging out was a one-way door.
    currentProvider = null;
    _pendingMobile = null;
    _pendingName = null;
    await Backend.rememberDemoSession(null);
  }

  /// The seeded account in demo data, and its PIN.
  ///
  /// Public because the welcome screen offers it, the sign-in screen pre-fills
  /// it and the tests use it — three copies of a number is two too many.
  static const demoMobile = '9998800201';
  static const demoPin = '135790';

  /// Sign straight into the demo account, skipping the PIN.
  ///
  /// Demo mode only, and not on [SathiyaaProviderBackend] for that reason.
  /// Anyone who wants to see the real sign-in does it from the same screen,
  /// which is the point of the change.
  Future<void> openDemoAccount() async {
    final account = _accounts[demoMobile];
    if (account == null) return;
    currentProvider = account;
    await Backend.rememberDemoSession(account.mobile);
  }

  /// Puts the session back after a restart. Called by [Backend.load].
  ///
  /// Silent when the number is not one this run knows about: accounts created
  /// during a demo run live in memory and do not survive a restart, and
  /// landing on Welcome is the right answer for one of those.
  void restoreSession(String mobile) {
    final account = _accounts[mobile];
    if (account != null) currentProvider = account;
  }

  /// Every provider account this demo run knows about, keyed by mobile number.
  final Map<String, ProviderProfile> _accounts = {};
  @override
  final List<TimeBankEntry> timeBank = [];
  @override
  final List<CalendarBlock> calendarBlocks = [];
  String? _pendingMobile;
  String? _pendingName;

  Future<void> _delay([int ms = 350]) => Future.delayed(Duration(milliseconds: ms));

  void _seed() {
    final provider = ProviderProfile(
      id: 'PROV-000201',
      kind: ProviderKind.organization,
      name: 'Karuna Companion Services',
      gender: 'N/A',
      mobile: '9998800201',
      email: 'karuna@example.com',
      address: 'B-14 Paldi, Ahmedabad',
      lat: 22.9759,
      lng: 72.5706,
      locationOn: true,
      currentLat: 12.9250,
      currentLng: 77.5938,
      expertise: [ServiceType.companion, ServiceType.nurse],
      hourlyRate: 260,
      pin: '135790',
      ratingAvg: 4.7,
      ratingCount: 58,
      allocateViaOrg: true,
      aadhar: ProviderDocument(url: 'uploaded.jpg'),
      policeVerification: ProviderDocument(url: 'uploaded.jpg', validFrom: DateTime(2026, 1, 1), validTo: DateTime(2027, 1, 1)),
      medicalCertificate: ProviderDocument(url: 'uploaded.jpg', validFrom: DateTime(2026, 1, 1), validTo: DateTime(2026, 12, 31)),
      // One of each state, so the staff screen can be seen doing its job
      // offline: checked and allocatable, waiting on Sathiyaa, and blocked by
      // the organisation itself.
      employees: [
        Employee(
          id: 'EMP-001', name: 'Deepa Shah', gender: 'Female', mobile: '9998800301',
          address: 'Vastrapur, Ahmedabad', lat: 23.0395, lng: 72.5290,
          approvalStatus: 'approved',
          languages: ['English', 'Gujarati', 'Hindi'],
          aadhar: ProviderDocument(url: 'uploaded.jpg'),
          policeVerification: ProviderDocument(
              url: 'uploaded.jpg', validFrom: DateTime(2026, 1, 1), validTo: DateTime(2027, 1, 1)),
        ),
        Employee(
          id: 'EMP-002', name: 'Vikram Rao', gender: 'Male', mobile: '9998800302',
          address: 'Navrangpura, Ahmedabad', lat: 23.0376, lng: 72.5601,
          approvalStatus: 'pending',
          languages: ['English', 'Hindi'],
          aadhar: ProviderDocument(url: 'uploaded.jpg'),
          policeVerification: ProviderDocument(
              url: 'uploaded.jpg', validFrom: DateTime(2026, 1, 1), validTo: DateTime(2027, 1, 1)),
          status: EmployeeStatus.active,
        ),
        Employee(
          id: 'EMP-003', name: 'Nisha Desai', gender: 'Female', mobile: '9998800303',
          address: 'Maninagar, Ahmedabad', lat: 22.9967, lng: 72.6047,
          languages: ['Gujarati'],
          status: EmployeeStatus.blocked,
        ),
      ],
    );
    // Seeded into the account list but deliberately *not* signed in. The app
    // used to open as Karuna Companion Services, so a first-time viewer never
    // saw the welcome screen or the sign-in. Welcome offers a one-tap way in,
    // and Backend.load() restores the session on later launches, so the
    // convenience is kept and the first impression is the real one.
    _accounts[provider.mobile] = provider;

    bookings.addAll([
      ProviderBooking(
        id: 'BKG-000601',
        customerId: 'CUST-000013',
        customerName: 'Anita Verma',
        // Booked by Anita, for her mother. The carer knocks and asks for
        // Kamala, not Anita — which is the entire reason this is recorded.
        forName: 'Kamala Devi',
        forRelationship: 'Mother',
        forContactNumber: '9845011223',
        forDateOfBirth: DateTime(1941, 7, 3),
        forNotes: 'Hard of hearing. Knock twice and wait — she takes a while to the door.',
        unreadMessages: 1,
        providerId: provider.id,
        serviceType: ServiceType.companion,
        startDate: DateTime.now(),
        endDate: DateTime.now(),
        timeFrom: '10:00',
        timeTo: '14:00',
        customerAddress: '22 Shanti Nagar, CG Road, Ahmedabad',
        customerMobile: '9845010101',
        customerBloodGroup: 'B+',
        customerCommMode: 'call,sms',
        customerCommTimeframe: '09:00-18:00',
        customerLat: 12.9784,
        customerLng: 77.6408,
        status: BookingStatus.requested,
      ),
      ProviderBooking(
        id: 'BKG-000602',
        customerId: 'CUST-000021',
        customerName: 'Prakash Mehta',
        providerId: provider.id,
        assignedEmployeeId: 'EMP-001',
        serviceType: ServiceType.nurse,
        startDate: DateTime.now().add(const Duration(days: 1)),
        endDate: DateTime.now().add(const Duration(days: 1)),
        timeFrom: '08:00',
        timeTo: '12:00',
        customerAddress: '7 Riverside Apts, Navrangpura, Ahmedabad',
        customerMobile: '9845020202',
        customerBloodGroup: 'O+',
        customerCommMode: 'call',
        customerCommTimeframe: '10:00-19:00',
        customerLat: 12.9352,
        customerLng: 77.6245,
        status: BookingStatus.accepted,
      ),
      ProviderBooking(
        id: 'BKG-000598',
        customerId: 'CUST-000009',
        customerName: 'Geeta Joshi',
        providerId: provider.id,
        assignedEmployeeId: 'EMP-002',
        serviceType: ServiceType.companion,
        startDate: DateTime.now().subtract(const Duration(days: 3)),
        endDate: DateTime.now().subtract(const Duration(days: 3)),
        timeFrom: '09:00',
        timeTo: '13:00',
        customerAddress: '3 Vastrapur Cross Rd, Ahmedabad',
        customerMobile: '9845030303',
        customerBloodGroup: 'A+',
        customerCommMode: 'email,call,sms',
        customerCommTimeframe: '08:00-20:00',
        customerLat: 13.0035,
        customerLng: 77.5709,
        status: BookingStatus.completed,
        totalHours: 4,
        amountDue: 1040,
        amountReceived: 1040,
        paymentStatus: PaymentStatus.paid,
      ),
      // A second new request, so the Jobs tab's count is not permanently 1 and
      // somebody can accept one and still have another to look at.
      ProviderBooking(
        id: 'BKG-000603',
        customerId: 'CUST-000031',
        customerName: 'Ramesh Pillai',
        providerId: provider.id,
        serviceType: ServiceType.companion,
        startDate: DateTime.now().add(const Duration(days: 2)),
        endDate: DateTime.now().add(const Duration(days: 2)),
        timeFrom: '15:00',
        timeTo: '19:00',
        customerAddress: '19 Satellite Road, Ahmedabad',
        customerMobile: '9845040404',
        customerBloodGroup: 'AB+',
        customerCommMode: 'call',
        customerCommTimeframe: '09:00-21:00',
        customerLat: 12.9121,
        customerLng: 77.6446,
        status: BookingStatus.requested,
      ),
      // A visit already running, which is the only way to see the OTP screen,
      // the "running late" control and the live pulse without starting one.
      ProviderBooking(
        id: 'BKG-000599',
        customerId: 'CUST-000017',
        customerName: 'Sudha Krishnan',
        providerId: provider.id,
        assignedEmployeeId: 'EMP-002',
        serviceType: ServiceType.medicalCompanion,
        startDate: DateTime.now(),
        endDate: DateTime.now(),
        timeFrom: '09:00',
        timeTo: '13:00',
        customerAddress: '5 Maninagar Main Rd, Ahmedabad',
        customerMobile: '9845050505',
        customerBloodGroup: 'B-',
        customerCommMode: 'call,sms',
        customerCommTimeframe: '08:00-20:00',
        customerLat: 12.9422,
        customerLng: 77.5731,
        status: BookingStatus.inProgress,
        serviceStartedAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 20)),
      ),
      // Finished but not yet paid, so the payment block has something to
      // collect rather than always reading "settled".
      ProviderBooking(
        id: 'BKG-000596',
        customerId: 'CUST-000024',
        customerName: 'Harish Bhatt',
        providerId: provider.id,
        serviceType: ServiceType.nurse,
        startDate: DateTime.now().subtract(const Duration(days: 6)),
        endDate: DateTime.now().subtract(const Duration(days: 6)),
        timeFrom: '07:00',
        timeTo: '11:00',
        customerAddress: '44 Naranpura 5th Block, Ahmedabad',
        customerMobile: '9845060606',
        customerBloodGroup: 'O-',
        customerCommMode: 'call',
        customerCommTimeframe: '09:00-18:00',
        customerLat: 12.9916,
        customerLng: 77.5526,
        status: BookingStatus.completed,
        totalHours: 4,
        amountDue: 1400,
        amountReceived: 0,
        paymentStatus: PaymentStatus.unpaid,
      ),
      // Cancelled by the customer — the one state that explains a gap in the
      // day that is nobody's fault.
      ProviderBooking(
        id: 'BKG-000592',
        customerId: 'CUST-000028',
        customerName: 'Meera Joshi',
        providerId: provider.id,
        serviceType: ServiceType.companion,
        startDate: DateTime.now().subtract(const Duration(days: 11)),
        endDate: DateTime.now().subtract(const Duration(days: 11)),
        timeFrom: '14:00',
        timeTo: '17:00',
        customerAddress: '8 Bopal Main Rd, Ahmedabad',
        customerMobile: '9845070707',
        customerBloodGroup: 'A-',
        customerCommMode: 'sms',
        customerCommTimeframe: '10:00-18:00',
        customerLat: 12.9698,
        customerLng: 77.7500,
        status: BookingStatus.cancelled,
      ),
    ]);

    // Enough entries to make Impact read as a record of work rather than two
    // rows, and spread far enough back that the period selector has something
    // different to show for week, month and year.
    timeBank.addAll([
      TimeBankEntry(id: 't1', date: DateTime.now().subtract(const Duration(days: 96)), serviceType: ServiceType.companion, hours: 5, points: 1250),
      TimeBankEntry(id: 't2', date: DateTime.now().subtract(const Duration(days: 61)), serviceType: ServiceType.nurse, hours: 4, points: 1000),
      TimeBankEntry(id: 't3', date: DateTime.now().subtract(const Duration(days: 38)), serviceType: ServiceType.companion, hours: 6, points: 1500),
      TimeBankEntry(id: 't4', date: DateTime.now().subtract(const Duration(days: 20)), serviceType: ServiceType.companion, hours: 6, points: 1500),
      TimeBankEntry(id: 't5', date: DateTime.now().subtract(const Duration(days: 12)), serviceType: ServiceType.physiotherapy, hours: 2, points: 500),
      TimeBankEntry(id: 't6', date: DateTime.now().subtract(const Duration(days: 5)), serviceType: ServiceType.medicalCompanion, hours: 3, points: 900),
      TimeBankEntry(id: 't7', date: DateTime.now().subtract(const Duration(days: 2)), serviceType: ServiceType.companion, hours: 4, points: 1000),
    ]);

    // A couple of days already blocked, so the calendar is not a blank grid and
    // the "this clashes with a booking" guard has something to bump into.
    calendarBlocks.addAll([
      CalendarBlock(
        id: 'blk-1',
        from: DateTime.now().add(const Duration(days: 5)),
        to: DateTime.now().add(const Duration(days: 6)),
        reason: 'Family wedding',
      ),
      CalendarBlock(
        id: 'blk-2',
        from: DateTime.now().add(const Duration(days: 18)),
        to: DateTime.now().add(const Duration(days: 18)),
        reason: 'Doctor’s appointment',
      ),
    ]);
  }

  /// Six digits, matching the backend's generateOtp().
  String _genOtp() => (100000 + _rand.nextInt(900000)).toString();

  // ---- Auth ---------------------------------------------------------------
  @override
  Future<void> registerStart({required String name, required String mobile}) async {
    await _delay();
    _pendingMobile = mobile;
    _pendingName = name;
  }

  @override
  Future<ProviderProfile> completeRegistration(ProviderProfile draft) async {
    await _delay(500);
    // Carry over whatever registerStart captured, so step one isn't lost if
    // the later form left those fields untouched.
    if (draft.name.trim().isEmpty && _pendingName != null) draft.name = _pendingName!;
    if (draft.mobile.trim().isEmpty && _pendingMobile != null) draft.mobile = _pendingMobile!;
    draft.approvalStatus = 'pending';
    draft.approved = false;
    currentProvider = draft;
    if (draft.mobile.trim().isNotEmpty) {
      _accounts[draft.mobile.trim()] = draft;
      await Backend.rememberDemoSession(draft.mobile.trim());
    }
    return draft;
  }

  @override
  Future<void> loginWithPin(String mobile, String pin) async {
    await _delay(400);
    final account = _accounts[mobile.trim()];
    if (account == null) {
      throw Exception('No account on this device for that number. Register first.');
    }
    if (account.pin != pin) {
      throw Exception('Incorrect PIN.');
    }
    currentProvider = account;
    await Backend.rememberDemoSession(account.mobile);
  }

  // ---- Bookings -------------------------------------------------------------
  @override
  List<ProviderBooking> get myBookings => bookings.where((b) => b.providerId == currentProvider!.id).toList();

  @override
  Future<void> acceptBooking(String id) async {
    await _delay(300);
    if (!currentProvider!.locationOn) {
      throw Exception('Turn location sharing on before accepting a request.');
    }
    final b = bookings.firstWhere((b) => b.id == id);
    if (isBlocked(b.startDate)) {
      throw Exception('Your calendar is blocked on that date. Unblock it first.');
    }
    b.status = BookingStatus.accepted;
  }

  @override
  Future<void> rejectBooking(String id) async {
    await _delay(300);
    bookings.firstWhere((b) => b.id == id).status = BookingStatus.cancelled;
  }

  @override
  Future<void> transferBooking(String id, String toEmployeeId) async {
    await _delay(300);
    bookings.firstWhere((b) => b.id == id).assignedEmployeeId = toEmployeeId;
  }

  /// "Running late" message. The spec offers the provider a 10/15/30-minute
  /// choice, so the chosen ETA travels with the message rather than being a
  /// bare flag.
  @override
  Future<void> sendRunningLate(String id, String eta) async {
    await _delay(250);
    final b = bookings.firstWhere((b) => b.id == id);
    b.runningLateSent = true;
    b.runningLateEta = eta;
  }

  /// Face match + geofence, then the start OTP. Facial recognition is a
  /// documented integration stub (backend/src/integrations/faceMatch.js
  /// always returns a match); the distance check against the customer's
  /// address is real arithmetic, so a provider who is nowhere near the
  /// booking is refused.
  @override
  Future<FaceCheckResult> verifyFaceAndGeofence(String id, {String? selfiePath}) async {
    await _delay(900);
    final b = bookings.firstWhere((b) => b.id == id);
    final p = currentProvider!;
    if (!p.locationOn) {
      return FaceCheckResult(passed: false, message: t('Location sharing is off — turn it on to start the service.'));
    }
    final lat = p.currentLat ?? p.lat;
    final lng = p.currentLng ?? p.lng;
    final km = distanceKm(lat, lng, b.customerLat, b.customerLng);
    if (km > geofenceKm) {
      return FaceCheckResult(
        passed: false,
        distanceKm: km,
        message: t(
            'You are {km} km from the customer. Get within {limit} km to start.', {
          'km': km.toStringAsFixed(1),
          'limit': geofenceKm.toStringAsFixed(1),
        }),
      );
    }
    b.faceVerifiedAt = DateTime.now();
    return FaceCheckResult(passed: true, distanceKm: km, message: t('Face matched (stub) and you are on site.'));
  }

  /// Issues the start OTP to the customer. Only valid once the face+geofence
  /// check has passed for this booking.
  @override
  Future<String> startService(String id) async {
    await _delay(300);
    final b = bookings.firstWhere((b) => b.id == id);
    if (b.faceVerifiedAt == null) {
      throw Exception('Complete the face and location check first.');
    }
    b.otp = _genOtp();
    return b.otp!;
  }

  /// Radius within which a provider counts as "at the customer's address".
  /// Matches START_SERVICE_GEOFENCE_KM in the backend's .env.
  static const double geofenceKm = 0.5;

  static double distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusKm = 6371.0;
    double toRad(double deg) => deg * pi / 180;
    final dLat = toRad(lat2 - lat1);
    final dLng = toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(toRad(lat1)) * cos(toRad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return earthRadiusKm * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  @override
  Future<void> confirmOtpAndStart(String id, String enteredOtp) async {
    await _delay(300);
    final b = bookings.firstWhere((b) => b.id == id);
    if (enteredOtp != b.otp) throw Exception('OTP does not match.');
    b.serviceStartedAt = DateTime.now();
    b.status = BookingStatus.inProgress;
  }

  @override
  Future<void> endService(String id) async {
    await _delay(400);
    final b = bookings.firstWhere((b) => b.id == id);
    b.serviceEndedAt = DateTime.now();
    final hours = b.serviceStartedAt == null ? 4.0 : max(1.0, b.serviceEndedAt!.difference(b.serviceStartedAt!).inMinutes / 60.0);
    b.totalHours = double.parse(hours.toStringAsFixed(1));
    final rate = currentProvider!.noFees ? 0.0 : (currentProvider!.orgServiceFeeOverride ?? currentProvider!.hourlyRate ?? 0);
    b.amountDue = rate * b.totalHours!;
    b.status = BookingStatus.completed;
    if (currentProvider!.noFees) {
      timeBank.insert(0, TimeBankEntry(id: 'tb-${timeBank.length + 1}', date: DateTime.now(), serviceType: b.serviceType, hours: b.totalHours!, points: b.totalHours! * 250));
    }
  }

  @override
  Future<void> recordPayment(String id, double amount, {required bool full}) async {
    await _delay(300);
    final b = bookings.firstWhere((b) => b.id == id);
    b.amountReceived += amount;
    if (full || b.amountReceived >= b.amountDue) {
      b.amountReceived = b.amountDue;
      b.paymentStatus = PaymentStatus.paid;
    } else if (b.amountReceived > 0) {
      b.paymentStatus = PaymentStatus.partial;
    }
  }

  @override
  Future<void> sendPaymentReminder(String id) async {
    await _delay(250);
    bookings.firstWhere((b) => b.id == id).paymentReminderSentAt = DateTime.now();
  }

  @override
  Future<void> rateCustomer(String id, double rating, String comment) async {
    await _delay(300);
    final b = bookings.firstWhere((b) => b.id == id);
    b.customerRatingByProvider = rating;
    b.customerCommentByProvider = comment;
  }

  @override
  Future<void> orgCancel(String id) async {
    await _delay(300);
    bookings.firstWhere((b) => b.id == id).status = BookingStatus.cancelled;
  }

  // ---- Organization: employees --------------------------------------------
  @override
  Future<void> addEmployee(Employee e) async {
    await _delay(300);
    // Pending, exactly as on the server. The offline app should not teach an
    // organisation that adding somebody makes them verified.
    e.approvalStatus = 'pending';
    currentProvider!.employees.add(e);
  }

  @override
  Future<void> updateEmployee(Employee e) async {
    await _delay(250);
    final idx = currentProvider!.employees.indexWhere((x) => x.id == e.id);
    if (idx != -1) currentProvider!.employees[idx] = e;
  }

  @override
  Future<void> setEmployeeStatus(String id, EmployeeStatus status) async {
    await _delay(200);
    currentProvider!.employees.firstWhere((e) => e.id == id).status = status;
  }

  @override
  Future<void> toggleAllocateViaOrg(bool value) async {
    await _delay(200);
    currentProvider!.allocateViaOrg = value;
  }

  // ---- Location sharing ---------------------------------------------------

  @override
  Future<void> setLanguages(List<String> languages) async {
    await _delay(200);
    currentProvider!
      ..languages = List<String>.from(languages)
      ..languagesConfirmed = true;
  }

  @override
  Future<void> setLocationOn(bool on) async {
    await _delay(200);
    final p = currentProvider!;
    p.locationOn = on;
    if (on) {
      p.currentLat ??= p.lat;
      p.currentLng ??= p.lng;
    }
  }

  /// Simulates a GPS ping. Used by the "I'm at the customer's address" action
  /// so the geofence check has something realistic to measure against.
  // Demo mode has no server and no real city, so the gate is not applied --
  // see ServiceAreaGate.bypass.

  // Demo mode has no admin to send anything.
  @override
  Future<List<Broadcast>> loadBroadcasts() async => const [];

  @override
  Future<void> markBroadcastsRead() async {}

  @override
  Future<ServiceArea> loadServiceArea() async => ServiceArea.fallback;

  @override
  Future<bool> reportSignupPlace(SignupPlace place) async {
    currentProvider
      ?..signupInServiceArea = true
      ..signupCity = place.city;
    return true;
  }

  @override
  Future<void> pingLocation(double lat, double lng) async {
    await _delay(200);
    currentProvider!
      ..currentLat = lat
      ..currentLng = lng;
  }

  // ---- Calendar -----------------------------------------------------------

  @override
  bool isBlocked(DateTime day) => calendarBlocks.any((b) => b.covers(day));

  /// Bookings that occupy [day] — a multi-day booking shows on every day it
  /// spans, which is what the calendar needs.
  @override
  List<ProviderBooking> bookingsOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return myBookings.where((b) {
      if (b.status == BookingStatus.cancelled) return false;
      final from = DateTime(b.startDate.year, b.startDate.month, b.startDate.day);
      final to = DateTime(b.endDate.year, b.endDate.month, b.endDate.day);
      return !d.isBefore(from) && !d.isAfter(to);
    }).toList();
  }

  /// Whether the provider works that weekday at all, from their work
  /// preference — a day they don't work isn't a "free slot", it's a day off.
  @override
  bool worksOn(DateTime day) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return currentProvider!.workPref.days.contains(names[day.weekday - 1]);
  }

  /// Free hours left on a day: the working window minus whatever is booked.
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
    await _delay(250);
    final clash = myBookings.where((b) {
      if (b.status == BookingStatus.cancelled || b.status == BookingStatus.completed) return false;
      return !(b.endDate.isBefore(from) || b.startDate.isAfter(to));
    }).toList();
    if (clash.isNotEmpty) {
      throw Exception('You have ${clash.length} booking(s) in that range — transfer or finish them first.');
    }
    final block = CalendarBlock(id: 'blk-${calendarBlocks.length + 1}', from: from, to: to, reason: reason);
    calendarBlocks.add(block);
    return block;
  }

  @override
  Future<void> unblockCalendar(String id) async {
    await _delay(200);
    calendarBlocks.removeWhere((b) => b.id == id);
  }

  // ---- Dashboard ----------------------------------------------------------

  /// Dashboard figures for the selected period. Previously the period
  /// dropdown existed but every number ignored it; these actually filter.
  @override
  DashboardStats statsFor(String period, {String? employeeId}) {
    final now = DateTime.now();
    final from = periodStart(period, now);
    var scoped = myBookings.where((b) => !b.startDate.isBefore(from)).toList();
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
    final done = bookings.where((b) => b.assignedEmployeeId == employeeId && b.status == BookingStatus.completed).toList();
    final pending = done.fold<double>(0, (sum, b) => sum + (b.amountDue - b.amountReceived));
    final ratings = done.where((b) => b.customerRatingByProvider != null).map((b) => b.customerRatingByProvider!).toList();
    final avgRating = ratings.isEmpty ? 0.0 : ratings.reduce((a, b) => a + b) / ratings.length;
    return {'completedBookings': done.length, 'pendingPayment': pending, 'avgCustomerRating': avgRating};
  }
}
