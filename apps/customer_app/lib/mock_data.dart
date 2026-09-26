// In-memory "backend" for the Customer app: seeded dummy data plus a set of
// async methods that mirror the real API contract (docs/api-contract.md)
// closely enough that swapping this for real http calls later is a
// find-and-replace, not a rewrite. Everything here is a mock — the point of
// this file is to make the app fully testable on a device without a server.

import 'dart:async';
import 'dart:math';

import 'backend.dart';
import 'models.dart';
import 'broadcasts.dart';
import 'service_area.dart';
import './i18n/l10n.dart';

/// The offline backend: seeded demo data, held in memory, with the same
/// surface as the live one so every screen works identically with no server.
class MockBackend implements SathiyaaBackend {

  /// Demo mode has no server, so a picked file is shown straight from disk and
  /// there is nothing to resolve.
  @override
  String? absoluteUrl(String? ref) => null;
  MockBackend._internal() {
    _seed();
  }
  static final MockBackend instance = MockBackend._internal();

  final _rand = Random();

  @override
  bool get supportsSimulation => true;

  /// The seeded account in demo data.
  ///
  /// Public because three places need the same number and they must not each
  /// keep their own copy: the welcome screen offers it, the login screen
  /// pre-fills it, and the tests sign in as it.
  static const demoMobile = '9876500013';

  /// Reference codes issued by Business Partners. In the real backend these
  /// live in `business_agents.referral_code`; the customer types one in and it
  /// links their account to that partner for revenue-sharing.
  static const Map<String, String> referralCodes = {
    'APOL2337': 'Apollo Pharmacy — Bodakdev',
    'CARE8891': 'CareFirst Diagnostics',
    'SENI4402': 'SeniorLife Wellness Centre',
  };

  @override
  Customer? currentCustomer;

  /// Every account this demo run knows about, keyed by mobile number — the
  /// stand-in for the customers table.
  ///
  /// Without it, signing out dropped the only reference to the account and the
  /// next login built a blank "New Customer": log out of Anita Verma's demo
  /// profile and you could never get back to it, bookings, health record and
  /// all. A mobile number is the account here exactly as it is on the server.
  final Map<String, Customer> _accounts = {};

  final List<Provider> providers = [];
  final List<Booking> bookings = [];
  String? _pendingOtp;
  String? _pendingMobile;
  String? _pendingName;

  Future<void> _delay([int ms = 350]) => Future.delayed(Duration(milliseconds: ms));

  void _seed() {
    providers.addAll([
      Provider(
        id: 'PROV-000101',
        name: 'Lakshmi Iyer',
        gender: 'Female',
        expertise: [ServiceType.companion, ServiceType.medicalCompanion],
        hourlyRate: 200,
        lat: 23.0225,
        lng: 72.5714,
        city: 'Ahmedabad',
        ratingAvg: 4.8,
        ratingCount: 34,
        languages: ['English', 'Hindi', 'Gujarati'],
      ),
      Provider(
        id: 'PROV-000102',
        name: 'Ramesh Nair',
        gender: 'Male',
        expertise: [ServiceType.nurse],
        hourlyRate: 450,
        lat: 22.9861,
        lng: 72.6013,
        city: 'Ahmedabad',
        ratingAvg: 4.6,
        ratingCount: 21,
        languages: ['English', 'Malayalam', 'Hindi'],
      ),
      Provider(
        id: 'PROV-000103',
        name: 'Farah Sheikh',
        gender: 'Female',
        expertise: [ServiceType.physiotherapy],
        hourlyRate: 600,
        lat: 23.0293,
        lng: 72.6176,
        city: 'Ahmedabad',
        ratingAvg: 4.9,
        ratingCount: 47,
        languages: ['English', 'Hindi', 'Urdu'],
      ),
      Provider(
        id: 'PROV-000104',
        name: 'Karuna Companion Services (Org)',
        gender: 'N/A',
        expertise: [ServiceType.companion, ServiceType.nurse],
        hourlyRate: 240,
        lat: 23.0807,
        lng: 72.5704,
        city: 'Ahmedabad',
        ratingAvg: 4.7,
        ratingCount: 60,
        languages: ['English', 'Hindi', 'Gujarati'],
      ),
      Provider(
        id: 'PROV-000105',
        name: 'Suresh Patel',
        gender: 'Male',
        expertise: [ServiceType.companion],
        noFees: true,
        lat: 23.0207,
        lng: 72.7268,
        city: 'Ahmedabad',
        ratingAvg: 5.0,
        ratingCount: 9,
        languages: ['Gujarati', 'Hindi'],
      ),
      // --- The rest of the demo directory --------------------------------
      //
      // Demo data used to hold five providers, so a search for a companion
      // came back with three results while the same search against a live
      // server returned twenty-seven. Anyone shown the app on demo data
      // would have concluded the directory was nearly empty.
      //
      // Coordinates are real Ahmedabad neighbourhoods, so the distances the
      // search reports are plausible rather than noise. Four of these give
      // their time free, which is roughly the live proportion.
      Provider(
        id: 'PROV-000106',
        name: 'Meena Krishnan',
        gender: 'Female',
        expertise: [ServiceType.companion],
        hourlyRate: 190,
        lat: 22.9759,
        lng: 72.5706,
        city: 'Ahmedabad',
        ratingAvg: 4.5,
        ratingCount: 18,
        languages: ['English', 'Tamil', 'Hindi'],
      ),
      Provider(
        id: 'PROV-000107',
        name: 'Arun Deshpande',
        gender: 'Male',
        expertise: [ServiceType.companion, ServiceType.medicalCompanion],
        hourlyRate: 230,
        lat: 22.959,
        lng: 72.6244,
        city: 'Ahmedabad',
        ratingAvg: 4.4,
        ratingCount: 26,
        languages: ['English', 'Marathi', 'Hindi'],
      ),
      Provider(
        id: 'PROV-000108',
        name: "Sister Grace D'Souza",
        gender: 'Female',
        expertise: [ServiceType.nurse],
        hourlyRate: 520,
        lat: 23.012,
        lng: 72.6155,
        city: 'Ahmedabad',
        ratingAvg: 4.9,
        ratingCount: 63,
        languages: ['English', 'Konkani', 'Hindi'],
      ),
      Provider(
        id: 'PROV-000109',
        name: 'Vijay Rao',
        gender: 'Male',
        expertise: [ServiceType.physiotherapy],
        hourlyRate: 550,
        lat: 23.0577,
        lng: 72.546,
        city: 'Ahmedabad',
        ratingAvg: 4.6,
        ratingCount: 31,
        languages: ['English', 'Kannada', 'Hindi'],
      ),
      Provider(
        id: 'PROV-000110',
        name: 'Padma Subramanian',
        gender: 'Female',
        expertise: [ServiceType.companion, ServiceType.medicalCompanion],
        hourlyRate: 210,
        lat: 22.9854,
        lng: 72.5869,
        city: 'Ahmedabad',
        ratingAvg: 4.7,
        ratingCount: 42,
        languages: ['English', 'Tamil', 'Telugu'],
      ),
      Provider(
        id: 'PROV-000111',
        name: 'Imran Qureshi',
        gender: 'Male',
        expertise: [ServiceType.nurse, ServiceType.medicalCompanion],
        hourlyRate: 480,
        lat: 23.0408,
        lng: 72.6986,
        city: 'Ahmedabad',
        ratingAvg: 4.3,
        ratingCount: 15,
        languages: ['English', 'Hindi', 'Urdu'],
      ),
      Provider(
        id: 'PROV-000112',
        name: 'Shalini Gupta',
        gender: 'Female',
        expertise: [ServiceType.physiotherapy],
        hourlyRate: 640,
        lat: 22.963,
        lng: 72.6214,
        city: 'Ahmedabad',
        ratingAvg: 4.8,
        ratingCount: 55,
        languages: ['English', 'Hindi'],
      ),
      Provider(
        id: 'PROV-000113',
        name: 'Joseph Mathew',
        gender: 'Male',
        expertise: [ServiceType.companion],
        noFees: true,
        lat: 23.0225,
        lng: 72.618,
        city: 'Ahmedabad',
        ratingAvg: 5.0,
        ratingCount: 12,
        languages: ['English', 'Malayalam'],
      ),
      Provider(
        id: 'PROV-000114',
        name: 'Nandini Shetty',
        gender: 'Female',
        expertise: [ServiceType.nurse],
        hourlyRate: 465,
        lat: 23.0047,
        lng: 72.4635,
        city: 'Ahmedabad',
        ratingAvg: 4.5,
        ratingCount: 29,
        languages: ['English', 'Kannada', 'Tulu'],
      ),
      Provider(
        id: 'PROV-000115',
        name: 'Harish Menon',
        gender: 'Male',
        expertise: [ServiceType.companion, ServiceType.physiotherapy],
        hourlyRate: 380,
        lat: 23.0868,
        lng: 72.5738,
        city: 'Ahmedabad',
        ratingAvg: 4.2,
        ratingCount: 11,
        languages: ['English', 'Malayalam', 'Hindi'],
      ),
      Provider(
        id: 'PROV-000116',
        name: 'Zoya Ansari',
        gender: 'Female',
        expertise: [ServiceType.medicalCompanion],
        hourlyRate: 275,
        lat: 23.0293,
        lng: 72.5713,
        city: 'Ahmedabad',
        ratingAvg: 4.6,
        ratingCount: 37,
        languages: ['English', 'Hindi', 'Urdu'],
      ),
      Provider(
        id: 'PROV-000117',
        name: 'Rekha Prabhu',
        gender: 'Female',
        expertise: [ServiceType.companion],
        noFees: true,
        lat: 22.9788,
        lng: 72.6039,
        city: 'Ahmedabad',
        ratingAvg: 4.9,
        ratingCount: 21,
        languages: ['English', 'Kannada', 'Hindi'],
      ),
      Provider(
        id: 'PROV-000118',
        name: 'Dr. Anil Bhat',
        gender: 'Male',
        expertise: [ServiceType.physiotherapy, ServiceType.medicalCompanion],
        hourlyRate: 720,
        lat: 23.0207,
        lng: 72.6267,
        city: 'Ahmedabad',
        ratingAvg: 4.9,
        ratingCount: 88,
        languages: ['English', 'Kannada', 'Hindi'],
      ),
      Provider(
        id: 'PROV-000119',
        name: 'Sunita Yadav',
        gender: 'Female',
        expertise: [ServiceType.nurse],
        hourlyRate: 440,
        lat: 23.0689,
        lng: 72.6179,
        city: 'Ahmedabad',
        ratingAvg: 4.1,
        ratingCount: 9,
        languages: ['English', 'Hindi', 'Bengali'],
      ),
      Provider(
        id: 'PROV-000120',
        name: 'Kavitha Reddy',
        gender: 'Female',
        expertise: [ServiceType.companion, ServiceType.nurse],
        hourlyRate: 410,
        lat: 22.9507,
        lng: 72.5713,
        city: 'Ahmedabad',
        ratingAvg: 4.7,
        ratingCount: 44,
        languages: ['English', 'Telugu', 'Kannada'],
      ),
      Provider(
        id: 'PROV-000121',
        name: 'Faizal Rahman',
        gender: 'Male',
        expertise: [ServiceType.companion],
        hourlyRate: 185,
        lat: 23.042,
        lng: 72.5836,
        city: 'Ahmedabad',
        ratingAvg: 4.3,
        ratingCount: 16,
        languages: ['English', 'Malayalam', 'Urdu'],
      ),
      Provider(
        id: 'PROV-000122',
        name: 'Sarala Bai',
        gender: 'Female',
        expertise: [ServiceType.companion, ServiceType.medicalCompanion],
        noFees: true,
        lat: 22.9972,
        lng: 72.5494,
        city: 'Ahmedabad',
        ratingAvg: 4.8,
        ratingCount: 33,
        languages: ['Kannada', 'Hindi'],
      ),
      Provider(
        id: 'PROV-000123',
        name: 'Ganesh Pillai',
        gender: 'Male',
        expertise: [ServiceType.medicalCompanion],
        hourlyRate: 265,
        lat: 22.9591,
        lng: 72.5623,
        city: 'Ahmedabad',
        ratingAvg: 4.4,
        ratingCount: 24,
        languages: ['English', 'Tamil', 'Malayalam'],
      ),
      Provider(
        id: 'PROV-000124',
        name: 'Maya Verghese',
        gender: 'Female',
        expertise: [ServiceType.physiotherapy],
        hourlyRate: 590,
        lat: 23.01,
        lng: 72.6781,
        city: 'Ahmedabad',
        ratingAvg: 4.6,
        ratingCount: 39,
        languages: ['English', 'Malayalam', 'Hindi'],
      ),
      Provider(
        id: 'PROV-000125',
        name: 'Tarun Malhotra',
        gender: 'Male',
        expertise: [ServiceType.nurse],
        hourlyRate: 505,
        lat: 22.9854,
        lng: 72.6568,
        city: 'Ahmedabad',
        ratingAvg: 4.5,
        ratingCount: 27,
        languages: ['English', 'Hindi', 'Punjabi'],
      ),
    ]);

    final seededCustomer = Customer(
      id: 'CUST-000013',
      name: 'Anita Verma',
      mobile: '9876500013',
      email: 'anita.verma@example.com',
      dob: DateTime(1958, 4, 12),
      gender: 'Female',
      bloodGroup: 'B+',
      preferredLanguages: ['English', 'Hindi'],
      heightCm: 160,
      weightKg: 68,
      termsAccepted: true,
      addresses: [
        Address(label: t('Primary'), line1: '12 Shanti Nagar, CG Road', city: 'Ahmedabad', lat: 23.0293, lng: 72.6176, isPrimary: true),
        Address(label: t('Secondary'), line1: '4B Riverside Apts, Navrangpura', city: 'Ahmedabad', lat: 22.9861, lng: 72.6013),
      ],
      contactModes: {ContactMode.call, ContactMode.sms},
      contactTimeframe: '09:00-18:00',
      registrationFeePaid: true,
      // Enough of each to show what the section is for, and no more.
      //
      // Three readings of one metric used to mean the graph had a line for
      // blood pressure and an empty panel for everything else, so whoever was
      // looking concluded the chart was broken rather than that there was
      // nothing to draw. Every metric now has a short series with a shape to
      // it — hers drifts down, which is what somebody taking the medication
      // below would expect to see.
      // Four, not twelve.
      //
      // Every health section is capped at five records — in the app and on the
      // server, from the requirements — so a first attempt at "more demo data"
      // that seeded twelve readings put the app in a state a real customer
      // could never reach, and the section badge read a cheerful "12/5".
      //
      // Four is the most useful arrangement inside the rule: blood pressure
      // gets a three-point trend that visibly comes down, pulse gets a single
      // reading so the "add a second one to see a trend" state is on screen,
      // the other two metrics show the empty state, and a slot is left free so
      // adding a record actually works during a demo instead of hitting the
      // cap.
      vitals: [
        VitalRecord(id: 'v1', date: _daysAgo(26), type: VitalType.bp, valuePrimary: 146, valueSecondary: 92),
        VitalRecord(id: 'v2', date: _daysAgo(12), type: VitalType.bp, valuePrimary: 138, valueSecondary: 88),
        VitalRecord(id: 'v3', date: _daysAgo(4), type: VitalType.bp, valuePrimary: 128, valueSecondary: 82),
        VitalRecord(id: 'v4', date: _daysAgo(3), type: VitalType.pulse, valuePrimary: 74),
      ],
      medications: [
        MedicationRecord(id: 'm1', name: 'Metformin 500mg', frequency: 'Twice daily, after food'),
        MedicationRecord(id: 'm2', name: 'Amlodipine 5mg', frequency: 'Once daily, morning'),
        MedicationRecord(id: 'm3', name: 'Vitamin D3 60,000 IU', frequency: 'Once a week'),
      ],
      surgeries: [
        SurgeryRecord(id: 's1', name: 'Cataract — right eye', date: DateTime(2023, 11, 8)),
        SurgeryRecord(id: 's2', name: 'Knee arthroscopy', date: DateTime(2019, 2, 21)),
      ],
      // One that still matters and one that has settled, so the active/past
      // distinction on the row has something to show.
      allergies: [
        AllergyRecord(id: 'a1', name: 'Penicillin', onsetDate: DateTime(2001, 6, 1)),
        AllergyRecord(id: 'a2', name: 'Dust — seasonal', onsetDate: DateTime(2018, 9, 15), active: false),
      ],
      family: [
        FamilyMember(id: 'f1', name: 'Rohan Verma', relationship: 'Son', contact: '9876500099'),
        // The case booking-for-a-dependent exists for. Without somebody on the
        // account to book for, the picker has one option and never appears.
        FamilyMember(
            id: 'f2', name: 'Kamala Devi', relationship: 'Mother', contact: '9845011223'),
        FamilyMember(
            id: 'f3', name: 'Priya Nair', relationship: 'Daughter', contact: '9845077341'),
      ],
      // Two policies, one of which runs out inside the year — the expiry
      // treatment on the row is invisible while every policy is current.
      insurance: [
        InsuranceRecord(
          id: 'i1',
          insuredWith: 'Star Health',
          policyNumber: 'SH-2291837',
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 12, 31),
        ),
        InsuranceRecord(
          id: 'i2',
          insuredWith: 'HDFC Ergo — top-up',
          policyNumber: 'HE-7741260',
          startDate: DateTime(2025, 7, 1),
          endDate: DateTime(2026, 6, 30),
        ),
      ],
    );
    // Seeded into the account list but deliberately *not* signed in. The app
    // used to open as Anita Verma, so a first-time viewer never saw the
    // welcome screen, the sign-up or the one-time code — the journey the whole
    // app is for. Welcome offers a one-tap way in, and Backend.load() restores
    // the session on later launches, so the convenience is kept and the first
    // impression is the real one.
    _accounts[seededCustomer.mobile] = seededCustomer;

    // Bookings across all three tabs.
    //
    // One confirmed booking meant Current held a card and Future and Past were
    // both empty, so two thirds of the screen taught you nothing and the
    // rating, the receipt and the cancellation treatment were unreachable
    // without making a booking and waiting. These are the states somebody
    // showing the app needs to be able to point at.
    final me = seededCustomer.id;
    bookings.addAll([
      // Current — happening in two days, paid for, with a carer.
      Booking(
        id: 'BKG-000501',
        customerId: me,
        providerId: 'PROV-000101',
        providerName: 'Lakshmi Iyer',
        serviceType: ServiceType.companion,
        startDate: _daysFromNow(2),
        endDate: _daysFromNow(2),
        timeFrom: '10:00',
        timeTo: '14:00',
        status: BookingStatus.confirmed,
        bookingCharge: 99,
        bookingChargePaid: true,
        unreadMessages: 1,
      ),
      // Future — a nurse for her mother, which also shows a dependent booking
      // on the list without anybody having to make one.
      Booking(
        id: 'BKG-000502',
        customerId: me,
        providerId: 'PROV-000107',
        providerName: 'Sister Grace',
        serviceType: ServiceType.nurse,
        startDate: _daysFromNow(9),
        endDate: _daysFromNow(9),
        timeFrom: '08:00',
        timeTo: '12:00',
        status: BookingStatus.confirmed,
        bookingCharge: 99,
        bookingChargePaid: true,
        forName: 'Kamala Devi',
        forRelationship: 'Mother',
        forContactNumber: '9845011223',
      ),
      // Past, finished and rated — the receipt and the stars.
      Booking(
        id: 'BKG-000497',
        customerId: me,
        providerId: 'PROV-000101',
        providerName: 'Lakshmi Iyer',
        serviceType: ServiceType.companion,
        startDate: _daysAgo(6),
        endDate: _daysAgo(6),
        timeFrom: '10:00',
        timeTo: '15:00',
        status: BookingStatus.completed,
        bookingCharge: 99,
        bookingChargePaid: true,
        totalHours: 5,
        totalAmount: 2250,
        amountDue: 2250,
        amountReceived: 2250,
        serviceStartedAt: _daysAgo(6),
        serviceEndedAt: _daysAgo(6),
        customerRating: 5,
        customerComment: 'Kind, early, and wonderful with my mother.',
      ),
      // Past, finished, not yet rated — so the "rate this visit" prompt has
      // something to attach to.
      Booking(
        id: 'BKG-000494',
        customerId: me,
        providerId: 'PROV-000112',
        providerName: 'Fatima Sheikh',
        serviceType: ServiceType.medicalCompanion,
        startDate: _daysAgo(13),
        endDate: _daysAgo(13),
        timeFrom: '09:00',
        timeTo: '12:00',
        status: BookingStatus.completed,
        bookingCharge: 99,
        bookingChargePaid: true,
        totalHours: 3,
        totalAmount: 1260,
        amountDue: 1260,
        amountReceived: 1260,
        serviceStartedAt: _daysAgo(13),
        serviceEndedAt: _daysAgo(13),
      ),
      // Cancelled, with the fee the policy actually charges.
      Booking(
        id: 'BKG-000489',
        customerId: me,
        providerId: 'PROV-000119',
        providerName: 'Anjali Rao',
        serviceType: ServiceType.physiotherapy,
        startDate: _daysAgo(20),
        endDate: _daysAgo(20),
        timeFrom: '16:00',
        timeTo: '18:00',
        status: BookingStatus.cancelled,
        bookingCharge: 99,
        bookingChargePaid: true,
        cancelledAt: _daysAgo(21),
        cancellationFee: 0,
        refundAmount: 99,
      ),
    ]);

    // Two carers she has used before, so "My regular carers" is a list rather
    // than an empty state on a first look.
    seededCustomer.linkedProviderIds.addAll(['PROV-000101', 'PROV-000107']);
  }

  /// Demo dates are written relative to now, not as calendar dates. A fixed
  /// date is correct for a week and then quietly becomes a booking in the past
  /// sitting under "Future".
  static DateTime _daysAgo(int n) => DateTime.now().subtract(Duration(days: n));
  static DateTime _daysFromNow(int n) => DateTime.now().add(Duration(days: n));

  /// Six digits, matching the backend's generateOtp().
  String _genOtp() => (100000 + _rand.nextInt(900000)).toString();

  /// Sign straight into the demo account, skipping the code.
  ///
  /// Demo mode only, and it is not on [SathiyaaBackend] for that reason: there
  /// is no server here to have sent a code, so asking somebody to type one
  /// back is theatre. Anyone who wants to see the real sign-up does it from
  /// the same screen, which is the point of the change.
  Future<void> openDemoAccount() async {
    final account = _accounts[demoMobile];
    if (account == null) return;
    currentCustomer = account;
    await Backend.rememberDemoSession(account.mobile);
  }

  /// Puts the session back after a restart. Called by [Backend.load].
  ///
  /// Silent when the number is not one this run knows about: accounts created
  /// during a demo run live in memory and do not survive a restart, and
  /// landing on Welcome is the right answer for one of those.
  void restoreSession(String mobile) {
    final account = _accounts[mobile];
    if (account != null) currentCustomer = account;
  }

  // ---- Auth -------------------------------------------------------------
  @override
  Future<String?> registerCustomer({required String name, required String mobile}) async {
    await _delay();
    if (_accounts.containsKey(mobile)) {
      throw Exception('That mobile number already has an account. Log in instead.');
    }
    _pendingOtp = _genOtp();
    _pendingMobile = mobile;
    _pendingName = name;
    return _pendingOtp!; // dev aid, shown on-screen exactly like the web prototype
  }

  @override
  Future<void> verifyOtp(String mobile, String otp) async {
    await _delay();
    if (otp != _pendingOtp || mobile != _pendingMobile) {
      throw Exception('Invalid OTP. Please try again.');
    }
    final known = _accounts[mobile];
    if (known != null) {
      // Logging back in: the same account, with everything it had.
      currentCustomer = known;
      await Backend.rememberDemoSession(mobile);
      return;
    }
    final fresh = Customer(
      id: 'CUST-${100000 + _rand.nextInt(899999)}',
      name: _pendingName ?? 'New Customer',
      mobile: mobile,
    );
    _accounts[mobile] = fresh;
    currentCustomer = fresh;
    await Backend.rememberDemoSession(mobile);
  }

  @override
  Future<void> acceptTerms() async {
    await _delay(150);
    currentCustomer?.termsAccepted = true;
  }

  @override
  Future<String?> loginRequestOtp(String mobile) async {
    await _delay();
    _pendingOtp = _genOtp();
    _pendingMobile = mobile;
    return _pendingOtp!;
  }

  // ---- Search / booking ---------------------------------------------------
  /// Provider search. Mirrors `GET /providers/search` — filters on service
  /// type, gender, language and distance from the booking address, and skips
  /// providers whose calendar is already taken for any day in the requested
  /// range. `radiusKm` of null means "don't filter by distance".
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
    await _delay(500);
    final results = providers.where((p) {
      if (!p.approved) return false;
      if (!p.expertise.contains(type)) return false;
      if (gender != null && gender != 'Any' && p.gender != gender) return false;
      if (language != null && language != 'Any' && !p.languages.contains(language)) return false;
      if (lat != null && lng != null && radiusKm != null) {
        if (distanceKm(lat, lng, p.lat, p.lng) > radiusKm) return false;
      }
      if (dateFrom != null) {
        final to = dateTo ?? dateFrom;
        if (_hasClashingBooking(p.id, dateFrom, to)) return false;
      }
      return true;
    }).toList();
    if (lat != null && lng != null) {
      // The server returns a distance on every result and the cards show it,
      // so offline results have to carry one too — otherwise the same screen
      // reads "3.5 km away" live and shows nothing in demo.
      for (final p in results) {
        p.distanceKm = distanceKm(lat, lng, p.lat, p.lng);
      }
      results.sort((a, b) => (a.distanceKm ?? 0).compareTo(b.distanceKm ?? 0));
    }
    return results;
  }

  bool _hasClashingBooking(String providerId, DateTime from, DateTime to) {
    return bookings.any((b) {
      if (b.providerId != providerId) return false;
      if (b.status == BookingStatus.cancelled || b.status == BookingStatus.completed) return false;
      return !(b.endDate.isBefore(_dayOnly(from)) || b.startDate.isAfter(_dayOnly(to)));
    });
  }

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Great-circle distance in km. The same haversine the backend uses for
  /// its location filter, so search results rank identically.
  static double distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusKm = 6371.0;
    double toRad(double deg) => deg * pi / 180;
    final dLat = toRad(lat2 - lat1);
    final dLng = toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(toRad(lat1)) * cos(toRad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return earthRadiusKm * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  /// Threads per booking, so a conversation survives leaving the screen.
  final Map<String, List<BookingMessage>> _threads = {};

  @override
  Future<List<BookingMessage>> bookingMessages(String bookingId) async {
    await _delay(250);
    final b = bookings.firstWhere((x) => x.id == bookingId);
    // Same rule as the server: nobody to talk to before somebody accepted.
    if (b.status == BookingStatus.searching || b.status == BookingStatus.pendingPayment) {
      throw Exception('Messages open once a carer has accepted and the booking is confirmed.');
    }
    final thread = _threads.putIfAbsent(bookingId, () => [
          BookingMessage(
            id: 'm-seed',
            sender: MessageSender.system,
            body: 'Booking confirmed. You can message each other here.',
            sentAt: DateTime.now().subtract(const Duration(minutes: 40)),
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
      sender: MessageSender.customer,
      body: body.trim(),
      sentAt: DateTime.now(),
    );
    _threads.putIfAbsent(bookingId, () => []).add(m);

    // A reply, so the screen can be seen working without a second device.
    Future<void>.delayed(const Duration(seconds: 3), () {
      _threads[bookingId]?.add(BookingMessage(
        id: 'm-${DateTime.now().microsecondsSinceEpoch}',
        sender: MessageSender.provider,
        body: 'Noted, thank you.',
        sentAt: DateTime.now(),
      ));
      final b = bookings.where((x) => x.id == bookingId).firstOrNull;
      if (b != null) b.unreadMessages += 1;
    });

    return m;
  }

  @override
  Future<SosResult> raiseSos({
    double? lat,
    double? lng,
    String? addressText,
    String? note,
  }) async {
    await _delay(600);
    // Demo data has no SMS gateway either, and says so rather than pretending.
    // The alert is still "recorded", because that is the behaviour the live
    // server has and the screen has to look the same in both.
    final family = currentCustomer?.family.where((f) => f.active).toList() ??
        const <FamilyMember>[];
    return SosResult(
      alertId: 'SOS-${100000 + _rand.nextInt(899999)}',
      delivery: 'simulated',
      smsIsLive: false,
      notifiedCount: 0,
      recipients: family
          .map((f) => SosRecipient(
                name: f.name,
                relationship: f.relationship,
                number: f.contact,
                notified: false,
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
    await _delay(400);

    // Mirror the server rather than being more permissive: the shortlist is
    // intersected with who could actually take it, so demo mode refuses the
    // same bookings a real one would. A demo that accepts what production
    // rejects teaches the wrong thing.
    final eligible = providers
        .where((p) => p.expertise.contains(type) && p.approved)
        .toList();
    final chosen = providerIds.isEmpty
        ? eligible
        : eligible.where((p) => providerIds.contains(p.id)).toList();

    if (chosen.isEmpty) {
      throw Exception(
        'None of the carers you chose are free for that time. '
        'Pick somebody else, or change the day.',
      );
    }

    final b = Booking(
      id: 'BKG-${100000 + _rand.nextInt(899999)}',
      customerId: currentCustomer!.id,
      // Nobody has it yet. It is filled in below by whichever of the chosen
      // carers "accepts" — leaving the first one here would have the tracking
      // screen name somebody who never answered.
      providerId: '',
      serviceType: type,
      startDate: start,
      endDate: end,
      timeFrom: timeFrom,
      timeTo: timeTo,
      // Same as the live server: nobody has accepted yet, so there is nothing
      // to pay for.
      status: BookingStatus.searching,
      providersNotified: chosen.length,
      askedNames: chosen.map((p) => p.name).toList(),
      chosenByCustomer: providerIds.isNotEmpty,
      unavailableCount: providerIds.isEmpty ? 0 : providerIds.length - chosen.length,
      forName: forMember?.name,
      forRelationship: forMember?.relationship,
      forContactNumber: forMember?.contact,
    );
    bookings.insert(0, b);

    // Offline, there is no second phone to accept it, so one of the carers who
    // was asked "accepts" shortly after — long enough to see the waiting state,
    // short enough not to be irritating. Picked at random from the shortlist,
    // because that is the one thing about asking several people that a demo
    // should actually show: you do not get to choose which one says yes.
    final winner = chosen[_rand.nextInt(chosen.length)];
    Future.delayed(const Duration(seconds: 4), () {
      if (b.status != BookingStatus.searching) return;
      b.providerId = winner.id;
      b.providerName = winner.name;
      b.status = BookingStatus.pendingPayment;
      b.paymentDeadline = DateTime.now().add(const Duration(minutes: 15));
    });

    return b;
  }

  @override
  Future<void> payBookingCharge(String bookingId) async {
    await _delay(600);
    final b = bookings.firstWhere((b) => b.id == bookingId);
    // Mirror the server's rule rather than being more permissive, so a flow
    // that works offline also works against a real backend.
    if (b.status != BookingStatus.pendingPayment) {
      throw Exception('This booking cannot be paid for yet (${b.status.label}).');
    }
    b.bookingChargePaid = true;
    b.status = BookingStatus.confirmed;
  }

  @override
  Future<void> startServiceSimulation(String bookingId) async {
    // Simulates the provider starting service and the OTP being generated.
    await _delay(300);
    final b = bookings.firstWhere((b) => b.id == bookingId);
    b.otp = _genOtp();
    b.serviceStartedAt = DateTime.now();
    b.status = BookingStatus.inProgress;
  }

  @override
  Future<void> completeService(String bookingId) async {
    await _delay(400);
    final b = bookings.firstWhere((b) => b.id == bookingId);
    b.serviceEndedAt = DateTime.now();
    final hours = b.serviceStartedAt == null ? 4.0 : max(1.0, b.serviceEndedAt!.difference(b.serviceStartedAt!).inMinutes / 60.0);
    b.totalHours = double.parse(hours.toStringAsFixed(1));
    final provider = providers.firstWhere((p) => p.id == b.providerId);
    b.totalAmount = provider.noFees ? 0 : (provider.hourlyRate ?? 0) * b.totalHours!;
    b.status = BookingStatus.completed;
  }

  /// Cancellation fee tiers, straight from the requirements doc:
  ///   * cancelled less than 24h before the service starts (or after it has
  ///     started) -> no refund at all;
  ///   * cancelled between 24h and 36h before the start -> 50% fee;
  ///   * earlier than 36h -> full refund.
  /// Quoting is separate from cancelling so the customer sees the cost first.
  @override
  CancellationQuote quoteCancellation(Booking b) => defaultCancellationQuote(b);

  @override
  Future<CancellationQuote> cancelBooking(String bookingId) async {
    await _delay(300);
    final b = bookings.firstWhere((b) => b.id == bookingId);
    final quote = defaultCancellationQuote(b);
    b.status = BookingStatus.cancelled;
    b.cancelledAt = DateTime.now();
    b.cancellationFee = quote.feeAmount;
    b.refundAmount = quote.refundAmount;
    return quote;
  }

  @override
  Future<void> rateProvider(String bookingId, double rating, String comment) async {
    await _delay(300);
    final b = bookings.firstWhere((b) => b.id == bookingId);
    b.customerRating = rating;
    b.customerComment = comment;
    final provider = providers.firstWhere((p) => p.id == b.providerId);
    provider.ratingCount += 1;
    provider.ratingAvg = ((provider.ratingAvg * (provider.ratingCount - 1)) + rating) / provider.ratingCount;
  }

  @override
  Future<void> linkProvider(String providerId) async {
    await _delay(250);
    final c = currentCustomer!;
    if (c.linkedProviderIds.length >= 10) {
      throw Exception('You can link up to 10 providers.');
    }
    if (!c.linkedProviderIds.contains(providerId)) c.linkedProviderIds.add(providerId);
  }

  @override
  Future<void> unlinkProvider(String providerId) async {
    await _delay(250);
    currentCustomer!.linkedProviderIds.remove(providerId);
  }

  // ---- Record-limited health sections (cap of 5) --------------------------
  void _assertUnder5(int currentCount) {
    if (currentCount >= 5) throw Exception('Limit of 5 records reached. Delete one to add another.');
  }

  @override
  Future<void> addVital(VitalRecord v) async {
    await _delay(200);
    _assertUnder5(currentCustomer!.vitals.length);
    currentCustomer!.vitals.add(v);
  }

  @override
  Future<void> deleteVital(String id) async {
    await _delay(150);
    currentCustomer!.vitals.removeWhere((v) => v.id == id);
  }

  @override
  Future<void> addMedication(MedicationRecord m) async {
    await _delay(200);
    _assertUnder5(currentCustomer!.medications.length);
    currentCustomer!.medications.add(m);
  }

  @override
  Future<void> deleteMedication(String id) async {
    await _delay(150);
    currentCustomer!.medications.removeWhere((m) => m.id == id);
  }

  @override
  Future<void> addSurgery(SurgeryRecord s) async {
    await _delay(200);
    _assertUnder5(currentCustomer!.surgeries.length);
    currentCustomer!.surgeries.add(s);
  }

  @override
  Future<void> deleteSurgery(String id) async {
    await _delay(150);
    currentCustomer!.surgeries.removeWhere((s) => s.id == id);
  }

  @override
  Future<void> addAllergy(AllergyRecord a) async {
    await _delay(200);
    _assertUnder5(currentCustomer!.allergies.length);
    currentCustomer!.allergies.add(a);
  }

  @override
  Future<void> deleteAllergy(String id) async {
    await _delay(150);
    currentCustomer!.allergies.removeWhere((a) => a.id == id);
  }

  @override
  Future<void> addFamilyMember(FamilyMember f) async {
    await _delay(200);
    _assertUnder5(currentCustomer!.family.length);
    currentCustomer!.family.add(f);
  }

  @override
  Future<void> removeFamilyMember(String id) async {
    await _delay(150);
    final active = currentCustomer!.family.where((f) => f.active).length;
    final target = currentCustomer!.family.firstWhere((f) => f.id == id);
    if (target.active && active <= 1) {
      throw Exception('At least one family contact must remain.');
    }
    target.active = false;
  }

  @override
  Future<void> addInsurance(InsuranceRecord i) async {
    await _delay(200);
    currentCustomer!.insurance.add(i);
  }

  // ---- Profile: basic details, address, contact preference ---------------

  /// Saves the mandatory + optional basic-details fields in one call, the way
  /// `PUT /customers/me` does. BMI isn't stored — it's derived from height and
  /// weight by `Customer.bmi`, matching the DB's generated column.
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
    await _delay(300);
    final c = currentCustomer!;
    if (name.trim().isEmpty) throw Exception('Name is required.');
    if (dob == null) throw Exception('Date of birth is required.');
    if (gender == null || gender.isEmpty) throw Exception('Gender is required.');
    if ((photoPath ?? c.photoUrl) == null) throw Exception('A profile photo is required.');
    c.name = name.trim();
    c.email = email;
    if (photoPath != null) c.photoUrl = photoPath;
    c.dob = dob;
    c.gender = gender;
    c.bloodGroup = bloodGroup;
    if (languages != null) c.preferredLanguages = languages;
    c.heightCm = heightCm;
    c.weightKg = weightKg;
  }

  /// Primary and Secondary addresses. At least one is mandatory, and the
  /// primary is the one bookings default to, so an empty primary is rejected.
  @override
  Future<void> saveAddresses({required Address primary, Address? secondary}) async {
    await _delay(300);
    if (primary.line1.trim().isEmpty || primary.city.trim().isEmpty) {
      throw Exception('A primary address (street and city) is required.');
    }
    final c = currentCustomer!;
    primary.isPrimary = true;
    primary.label = 'Primary';
    final list = <Address>[primary];
    if (secondary != null && secondary.line1.trim().isNotEmpty) {
      secondary.isPrimary = false;
      secondary.label = 'Secondary';
      list.add(secondary);
    }
    c.addresses = list;
  }

  @override
  Address? primaryAddress() {
    final list = currentCustomer?.addresses ?? [];
    for (final a in list) {
      if (a.isPrimary) return a;
    }
    return list.isEmpty ? null : list.first;
  }

  @override
  Future<void> setContactPreference({required Set<ContactMode> modes, String? timeframe}) async {
    await _delay(200);
    if (modes.isEmpty) throw Exception('Pick at least one way to be contacted.');
    currentCustomer!
      ..contactModes = modes
      ..contactTimeframe = timeframe;
  }

  // ---- Reference code & registration fee ---------------------------------

  /// Applies a Business Partner reference code. Returns the partner's name so
  /// the UI can confirm which partner the customer has been linked to.
  @override
  Future<String> applyReferenceCode(String code) async {
    await _delay(400);
    final normalised = code.trim().toUpperCase();
    final partner = referralCodes[normalised];
    if (partner == null) throw Exception("That reference code isn't recognised.");
    currentCustomer!.referenceCode = normalised;
    return partner;
  }

  // Demo mode has no server and no real city, so the gate is not applied --
  // see ServiceAreaGate.bypass. These exist to satisfy the interface and to
  // behave sensibly if anything does call them.

  // Demo mode has no admin to send anything.
  @override
  Future<List<Broadcast>> loadBroadcasts() async => const [];

  @override
  Future<void> markBroadcastsRead() async {}

  @override
  Future<ServiceArea> loadServiceArea() async => ServiceArea.fallback;

  @override
  Future<bool> reportSignupPlace(SignupPlace place) async {
    currentCustomer
      ?..signupInServiceArea = true
      ..signupCity = place.city;
    return true;
  }

  @override
  Future<void> clearReferenceCode() async {
    await _delay(150);
    currentCustomer!.referenceCode = null;
  }

  /// Marks the annual registration as settled. Nothing is charged — no
  /// payment provider is connected yet; the integration point when there is
  /// one is backend/src/integrations/payment.js.
  @override
  Future<void> payRegistrationFee() async {
    await _delay(800);
    // Offline, the renewal date is set the same way the server sets it, so
    // the card behaves identically in demo mode rather than sitting on
    // "Recorded as paid." forever.
    currentCustomer!
      ..registrationFeePaid = true
      ..registrationRenewalDue = false
      ..registrationRenewsAt = DateTime.now().add(const Duration(days: 365));
  }

  // ---- Edits on the health-profile sections ------------------------------

  @override
  Future<void> updateVital(VitalRecord v) async {
    await _delay(200);
    final i = currentCustomer!.vitals.indexWhere((x) => x.id == v.id);
    if (i >= 0) currentCustomer!.vitals[i] = v;
  }

  @override
  Future<void> updateMedication(MedicationRecord m) async {
    await _delay(200);
    final i = currentCustomer!.medications.indexWhere((x) => x.id == m.id);
    if (i >= 0) currentCustomer!.medications[i] = m;
  }

  @override
  Future<void> updateSurgery(SurgeryRecord su) async {
    await _delay(200);
    final i = currentCustomer!.surgeries.indexWhere((x) => x.id == su.id);
    if (i >= 0) currentCustomer!.surgeries[i] = su;
  }

  @override
  Future<void> updateAllergy(AllergyRecord a) async {
    await _delay(200);
    final i = currentCustomer!.allergies.indexWhere((x) => x.id == a.id);
    if (i >= 0) currentCustomer!.allergies[i] = a;
  }

  @override
  Future<void> updateFamilyMember(FamilyMember f) async {
    await _delay(200);
    final i = currentCustomer!.family.indexWhere((x) => x.id == f.id);
    if (i >= 0) currentCustomer!.family[i] = f;
  }

  @override
  Future<void> updateInsurance(InsuranceRecord ins) async {
    await _delay(200);
    final i = currentCustomer!.insurance.indexWhere((x) => x.id == ins.id);
    if (i >= 0) currentCustomer!.insurance[i] = ins;
  }

  @override
  Future<void> deleteInsurance(String id) async {
    await _delay(150);
    currentCustomer!.insurance.removeWhere((x) => x.id == id);
  }

  /// Vitals filtered to a trailing window, for the trend graph's
  /// 7 / 30 / 90-day selector.
  @override
  List<VitalRecord> vitalsWithin(int days, {VitalType? type}) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final list = currentCustomer!.vitals
        .where((v) => v.date.isAfter(cutoff) && (type == null || v.type == type))
        .toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  @override
  Provider? cachedProvider(String id) {
    for (final p in providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<Provider> providerById(String id) async {
    await _delay(120);
    final p = cachedProvider(id);
    if (p == null) throw Exception('Provider not found.');
    return p;
  }

  @override
  Future<List<Provider>> linkedProviders() async {
    await _delay(150);
    return currentCustomer!.linkedProviderIds
        .map(cachedProvider)
        .whereType<Provider>()
        .toList();
  }

  @override
  Future<List<Booking>> allBookings() async {
    await _delay(150);
    final id = currentCustomer?.id;
    if (id == null) return const [];
    return bookings.where((b) => b.customerId == id).toList();
  }

  @override
  Future<Booking> refreshBooking(String bookingId) async {
    await _delay(120);
    return bookings.firstWhere((b) => b.id == bookingId);
  }

  /// Nothing to fetch offline — the seeded customer is always current.
  @override
  Future<void> refreshProfile() async {}

  @override
  Future<void> signOut() async {
    // The account stays in _accounts, and its bookings stay in `bookings`
    // keyed by customer id, so logging back in finds everything where it was.
    currentCustomer = null;
    _pendingOtp = null;
    _pendingMobile = null;
    _pendingName = null;
    await Backend.rememberDemoSession(null);
  }

  List<Booking> bookingsFor(String customerId) =>
      bookings.where((b) => b.customerId == customerId).toList();
}
