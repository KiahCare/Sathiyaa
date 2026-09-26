@Timeout(Duration(minutes: 2))
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:sathiyaa_customer/api/api_backend.dart';
import 'package:sathiyaa_customer/api/api_client.dart';
import 'package:sathiyaa_customer/models.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Exercises the real HTTP layer against a running backend.
///
/// Point it somewhere else with `--dart-define=SATHIYAA_API=http://host:4000/api/v1`.
/// If nothing is listening the whole group is skipped rather than failed, so
/// `flutter test` still passes on a machine with no server running.
const _base = String.fromEnvironment('SATHIYAA_API', defaultValue: 'http://localhost:4000/api/v1');

Future<bool> _serverUp() async {
  try {
    await ApiClient(_base).get('/providers/search', query: {'service_type': 'companion'});
    return true;
  } on ApiException catch (e) {
    // A structured error still proves the API answered.
    return e.status != 0;
  } catch (_) {
    return false;
  }
}

/// The seeded providers work weekdays, so a weekend date legitimately matches
/// nobody and would make a green test look red.
DateTime _nextWeekday({int inDays = 3}) {
  var d = DateTime.now().add(Duration(days: inDays));
  while (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
    d = d.add(const Duration(days: 1));
  }
  return d;
}


/// Accounts this run created, so they can be removed again afterwards.
///
/// These tests talk to the real server and really do register people. Without
/// this, every `flutter test` left another row behind, and the admin console
/// filled up with dozens of "Flutter Integration ..." accounts that crowded
/// out the real directory. Cleaning up is part of the test.
final _createdProviderIds = <int>[];
final _createdCustomerIds = <int>[];

Future<void> _cleanUpCreatedAccounts() async {
  if (_createdProviderIds.isEmpty && _createdCustomerIds.isEmpty) return;
  try {
    final login = await http.post(
      Uri.parse('$_base/auth/admin/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': 'admin@sathiyaa.com', 'password': 'Admin@123'}),
    );
    if (login.statusCode != 200) return;
    final token = (jsonDecode(login.body) as Map)['token'];

    final targets = <MapEntry<String, int>>[
      for (final id in _createdProviderIds) MapEntry('providers', id),
      for (final id in _createdCustomerIds) MapEntry('customers', id),
    ];
    for (final entry in targets) {
      // Best effort: an account that picked up a booking during the run is
      // refused, and rightly so -- its history is worth more than a tidy list.
      await http.delete(
        Uri.parse('$_base/admin/${entry.key}/${entry.value}'),
        headers: {'Authorization': 'Bearer $token'},
      );
    }
  } catch (_) {
    // Never fail a test run over housekeeping.
  }
}

/// Pulls the numeric id out of a display id like SP-000042 or CUST-000042.
int? _numericId(String? displayId) {
  if (displayId == null) return null;
  final digits = RegExp(r'\d+').firstMatch(displayId)?.group(0);
  return digits == null ? null : int.tryParse(digits);
}

void main() {
  late bool up;

  setUpAll(() async {
    up = await _serverUp();
    if (!up) {
      // ignore: avoid_print
      print('No Sathiyaa API at $_base — skipping the live integration tests.');
    }
  });

  tearDownAll(_cleanUpCreatedAccounts);

  group('ApiBackend against a live server', () {
    late ApiBackend api;
    late String mobile;

    setUp(() async {
      if (!up) return;
      api = ApiBackend(_base);
      mobile = '97${(Random().nextInt(90000000) + 10000000)}';
    });

    // Each test signs up a fresh person; note who, so tearDownAll can remove
    // them again rather than leaving the customer directory full of
    // "Flutter ..." rows.
    tearDown(() {
      // The same guard every test body has. Without it `api` is an
      // uninitialised `late` on a machine with no server running, and every
      // test in this group failed in its tearDown with a
      // LateInitializationError -- while its body had correctly returned
      // early. The file promises to skip rather than fail when nothing is
      // listening, and this is the line that was missing to keep that
      // promise.
      if (!up) return;
      final id = _numericId(api.currentCustomer?.id);
      if (id != null) _createdCustomerIds.add(id);
    });

    test('registers, verifies an OTP and loads the profile', () async {
      if (!up) return;
      final otp = await api.registerCustomer(name: 'Flutter Integration', mobile: mobile);
      expect(otp, isNotNull, reason: 'dev builds echo the OTP back instead of sending an SMS');

      await api.verifyOtp(mobile, otp!);
      expect(api.currentCustomer, isNotNull);
      expect(api.currentCustomer!.mobile, mobile);
      expect(api.currentCustomer!.id, startsWith('CUST-'));
    });

    test('saves basic details and both addresses, and the server computes BMI', () async {
      if (!up) return;
      final otp = await api.registerCustomer(name: 'Flutter Profile', mobile: mobile);
      await api.verifyOtp(mobile, otp!);

      await api.updateBasicDetails(
        name: 'Flutter Profile',
        email: 'flutter@example.com',
        // Already an http URL, so nothing is uploaded — this test is about BMI.
        photoPath: 'http://example.com/photo.jpg',
        dob: DateTime(1958, 4, 12),
        gender: 'Female',
        bloodGroup: 'B+',
        languages: ['English', 'Hindi'],
        heightCm: 160,
        weightKg: 64,
      );
      // BMI is a generated column in MySQL, so this proves the round trip.
      expect(api.currentCustomer!.bmi, closeTo(25.0, 0.2));

      await api.saveAddresses(
        primary: Address(label: 'Primary', line1: '12 Test St', city: 'Ahmedabad', lat: 23.0225, lng: 72.5714, isPrimary: true),
        secondary: Address(label: 'Secondary', line1: '8 Second Rd', city: 'Ahmedabad', lat: 23.03, lng: 72.58),
      );
      expect(api.currentCustomer!.addresses.length, 2);
      expect(api.primaryAddress()!.city, 'Ahmedabad');
    });

    test('enforces the five-record cap server-side', () async {
      if (!up) return;
      final otp = await api.registerCustomer(name: 'Flutter Caps', mobile: mobile);
      await api.verifyOtp(mobile, otp!);

      for (var i = 0; i < 5; i++) {
        await api.addSurgery(SurgeryRecord(id: '', name: 'Procedure $i', date: DateTime(2020, 1, i + 1)));
      }
      expect(api.currentCustomer!.surgeries.length, 5);

      // The sixth is refused by the backend, not just by the UI.
      await expectLater(
        api.addSurgery(SurgeryRecord(id: '', name: 'Sixth', date: DateTime(2021, 1, 1))),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'DATA_LIMIT')),
      );

      final first = api.currentCustomer!.surgeries.first;
      await api.deleteSurgery(first.id);
      await api.addSurgery(SurgeryRecord(id: '', name: 'Now it fits', date: DateTime(2021, 1, 1)));
      expect(api.currentCustomer!.surgeries.length, 5);
    });

    test('stores vitals per metric and reads them back for the graph', () async {
      if (!up) return;
      final otp = await api.registerCustomer(name: 'Flutter Vitals', mobile: mobile);
      await api.verifyOtp(mobile, otp!);

      await api.addVital(VitalRecord(
        id: '', date: DateTime.now().subtract(const Duration(days: 5)), type: VitalType.bp, valuePrimary: 132, valueSecondary: 84));
      await api.addVital(VitalRecord(
        id: '', date: DateTime.now().subtract(const Duration(days: 1)), type: VitalType.bp, valuePrimary: 126, valueSecondary: 80));
      await api.addVital(VitalRecord(id: '', date: DateTime.now(), type: VitalType.pulse, valuePrimary: 74));

      expect(api.vitalsWithin(30, type: VitalType.bp).length, 2);
      expect(api.vitalsWithin(30, type: VitalType.pulse).length, 1);
      final bp = api.vitalsWithin(30, type: VitalType.bp).last;
      expect(bp.valuePrimary, 126);
      expect(bp.valueSecondary, 80);
    });

    test('searches providers and links one, capped at ten', () async {
      if (!up) return;
      final otp = await api.registerCustomer(name: 'Flutter Search', mobile: mobile);
      await api.verifyOtp(mobile, otp!);
      await api.saveAddresses(
        primary: Address(label: 'Primary', line1: '12 Test St', city: 'Ahmedabad', lat: 23.0225, lng: 72.5714, isPrimary: true),
      );

      final day = _nextWeekday();
      final results = await api.search(
        type: ServiceType.companion,
        dateFrom: day,
        dateTo: day,
        timeFrom: '09:00',
        timeTo: '12:00',
        lat: 23.0225,
        lng: 72.5714,
        radiusKm: 50,
      );
      expect(results, isNotEmpty, reason: 'the seeded providers should match a weekday morning in Ahmedabad');
      expect(results.first.distanceKm, isNotNull);
      // Search results are cached so list rows can render a name synchronously.
      expect(api.cachedProvider(results.first.id), isNotNull);

      await api.linkProvider(results.first.id);
      expect(api.currentCustomer!.linkedProviderIds, contains(results.first.id));
      final linked = await api.linkedProviders();
      expect(linked, isNotEmpty);

      await api.unlinkProvider(results.first.id);
      expect(api.currentCustomer!.linkedProviderIds, isEmpty);
    });

    test('creates a booking that the server records against the customer', () async {
      if (!up) return;
      final otp = await api.registerCustomer(name: 'Flutter Booking', mobile: mobile);
      await api.verifyOtp(mobile, otp!);
      await api.saveAddresses(
        primary: Address(label: 'Primary', line1: '12 Test St', city: 'Ahmedabad', lat: 23.0225, lng: 72.5714, isPrimary: true),
      );

      final day = _nextWeekday();
      final results = await api.search(
        type: ServiceType.companion,
        dateFrom: day,
        dateTo: day,
        timeFrom: '09:00',
        timeTo: '12:00',
        lat: 23.0225,
        lng: 72.5714,
        radiusKm: 50,
      );
      expect(results, isNotEmpty);

      final booking = await api.createBooking(
        providerIds: [results.first.id],
        type: ServiceType.companion,
        start: day,
        end: day,
        timeFrom: '09:00',
        timeTo: '12:00',
      );
      expect(booking.id, isNotEmpty);
      expect(booking.bookingCharge, greaterThan(0));

      final fetched = await api.refreshBooking(booking.id);
      expect(fetched.id, booking.id);
      expect(fetched.serviceType, ServiceType.companion);
      expect(fetched.timeFrom, '09:00');

      final all = await api.allBookings();
      expect(all.map((b) => b.id), contains(booking.id));
    });

    test('uploads a photo and stores the served URL on the profile', () async {
      if (!up) return;
      final otp = await api.registerCustomer(name: 'Flutter Photo', mobile: mobile);
      await api.verifyOtp(mobile, otp!);

      // A real 1x1 PNG written to a temp file, exactly as image_picker would
      // hand the app a path.
      final tmp = await File('${Directory.systemTemp.path}/sathiyaa-test-${DateTime.now().microsecondsSinceEpoch}.png')
          .writeAsBytes(_onePixelPng);

      await api.updateBasicDetails(
        name: 'Flutter Photo',
        photoPath: tmp.path,
        dob: DateTime(1960, 1, 1),
        gender: 'Female',
      );

      final stored = api.currentCustomer!.photoUrl;
      expect(stored, isNotNull);
      // The local path must not survive - it means nothing on another device.
      expect(stored, isNot(contains(tmp.path)));

      // What is stored is a path relative to the server root, not an absolute
      // URL. It used to be absolute, and an absolute one bakes in whichever
      // hostname answered the upload: behind CloudFront that is the origin
      // instance's own name, over plain http, on a port closed to everything
      // but CloudFront. Every photo uploaded through the deployed app was
      // stored with an address that nothing could ever load again.
      expect(stored, startsWith('/uploads/'));

      // absoluteUrl() is what every screen calls before showing one, so that
      // is what has to produce something fetchable.
      final resolved = api.absoluteUrl(stored);
      expect(resolved, isNotNull);
      expect(resolved, startsWith('http'));

      final fetched = await HttpClient().getUrl(Uri.parse(resolved!)).then((r) => r.close());
      expect(fetched.statusCode, 200);

      // It survives a fresh read of the profile.
      await api.refreshProfile();
      expect(api.currentCustomer!.photoUrl, stored);

      await tmp.delete();
    });

    test('uploads a prescription alongside a medication', () async {
      if (!up) return;
      final otp = await api.registerCustomer(name: 'Flutter Rx', mobile: mobile);
      await api.verifyOtp(mobile, otp!);

      final tmp = await File('${Directory.systemTemp.path}/sathiyaa-rx-${DateTime.now().microsecondsSinceEpoch}.png')
          .writeAsBytes(_onePixelPng);

      await api.addMedication(MedicationRecord(
        id: '',
        name: 'Metformin 500mg',
        frequency: 'Twice daily',
        prescriptionUrl: tmp.path,
      ));

      final saved = api.currentCustomer!.medications.first;
      expect(saved.name, 'Metformin 500mg');
      expect(saved.prescriptionUploaded, isTrue);
      // Relative, for the same reason as the photo above.
      expect(saved.prescriptionUrl, startsWith('/uploads/'));
      expect(api.absoluteUrl(saved.prescriptionUrl), startsWith('http'));

      // Editing without touching the prescription keeps the same URL rather
      // than re-uploading it.
      final url = saved.prescriptionUrl;
      saved.frequency = 'Once daily';
      await api.updateMedication(saved);
      expect(api.currentCustomer!.medications.first.prescriptionUrl, url);
      expect(api.currentCustomer!.medications.first.frequency, 'Once daily');

      await tmp.delete();
    });

    test('a token keeps working on a fresh client, as after an app restart', () async {
      if (!up) return;
      final otp = await api.registerCustomer(name: 'Flutter Restart', mobile: mobile);
      await api.verifyOtp(mobile, otp!);
      final id = api.currentCustomer!.id;

      // A brand-new client with nothing in memory but the saved token — which
      // is exactly the state the app is in on the next launch.
      final restarted = ApiBackend(_base);
      restarted.restoreToken(_tokenOf(api));
      await restarted.refreshProfile();

      expect(restarted.currentCustomer, isNotNull);
      expect(restarted.currentCustomer!.id, id);
    });

    test('a bad token is rejected, so a stale session cannot half-restore', () async {
      if (!up) return;
      final restarted = ApiBackend(_base);
      restarted.restoreToken('not-a-real-token');
      await expectLater(restarted.refreshProfile(), throwsA(isA<ApiException>()));
    });

    test('a new booking is still searching, and cannot be paid for yet', () async {
      if (!up) return;
      final otp = await api.registerCustomer(name: 'Flutter Flow', mobile: mobile);
      await api.verifyOtp(mobile, otp!);
      await api.saveAddresses(
        primary: Address(label: 'Primary', line1: '12 Test St', city: 'Ahmedabad', lat: 23.0225, lng: 72.5714, isPrimary: true),
      );

      final day = _nextWeekday();
      final results = await api.search(
        type: ServiceType.companion, dateFrom: day, dateTo: day,
        timeFrom: '09:00', timeTo: '12:00', lat: 23.0225, lng: 72.5714, radiusKm: 50,
      );
      expect(results, isNotEmpty);

      final booking = await api.createBooking(
        providerIds: [results.first.id], type: ServiceType.companion,
        start: day, end: day, timeFrom: '09:00', timeTo: '12:00',
      );

      // The request has gone out; nobody has taken it. The app used to claim
      // this was `pendingPayment` and immediately offer a Pay button, which the
      // server then refused.
      expect(booking.status, BookingStatus.searching);
      expect(booking.providersNotified, isNotNull);
      expect(booking.paymentDeadline, isNull, reason: 'the 15-minute window starts on acceptance, not on request');

      // And paying now is correctly refused rather than silently failing.
      await expectLater(
        api.payBookingCharge(booking.id),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_STATE')),
      );

      final fetched = await api.refreshBooking(booking.id);
      expect(fetched.status, BookingStatus.searching);
    });

    test('reports a useful error when the server is unreachable', () async {
      // Deliberately points at a closed port; no running server required.
      final broken = ApiBackend('http://127.0.0.1:1/api/v1');
      await expectLater(
        broken.search(type: ServiceType.companion),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'NETWORK')
            .having((e) => e.message, 'message', contains('Cannot reach the server'))),
      );
    }, skip: Platform.isAndroid || Platform.isIOS ? 'host-only test' : false);
  });
}

/// A 1x1 transparent PNG, so upload tests send something a server will
/// actually accept as an image.
final Uint8List _onePixelPng = Uint8List.fromList([
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
  0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137,
  0, 0, 0, 13, 73, 68, 65, 84, 120, 218, 99, 248, 207, 192, 80, 15, 0,
  3, 134, 1, 128, 90, 52, 125, 107, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

/// The token an ApiBackend is currently using. The app reads this from
/// storage on launch; the test needs the same value to simulate that.
String _tokenOf(ApiBackend api) => api.currentToken!;
