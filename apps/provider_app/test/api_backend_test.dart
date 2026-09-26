@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:sathiyaa_provider/api/api_backend.dart';
import 'package:sathiyaa_provider/api/api_client.dart';
import 'package:sathiyaa_provider/models.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Exercises the real HTTP layer against a running backend.
///
/// Point it elsewhere with `--dart-define=SATHIYAA_API=http://host:4000/api/v1`.
/// If nothing is listening the tests skip rather than fail, so `flutter test`
/// still passes on a machine with no server running.
///
/// Each test registers its own provider rather than reusing a seeded one: the
/// backend binds an account to a single device by design, so sharing an
/// account across runs would (correctly) be rejected.
const _base = String.fromEnvironment('SATHIYAA_API', defaultValue: 'http://localhost:4000/api/v1');

final _rand = Random();

Future<bool> _serverUp() async {
  try {
    await ApiClient(_base).get('/providers/search', query: {'service_type': 'companion'});
    return true;
  } on ApiException catch (e) {
    return e.status != 0;
  } catch (_) {
    return false;
  }
}

String _mobile() => '96${_rand.nextInt(90000000) + 10000000}';

/// Real files on disk, because registration uploads them.
///
/// These used to be the string 'app://police.pdf'. That was never a file, and
/// the code let it through: the old "is this already on the server" test was
/// `!startsWith('/') && !contains('://')`, and a fake scheme satisfies it. So
/// the upload was skipped and the literal 'app://police.pdf' was stored as the
/// document URL -- and this test asserted only that the field was not null, so
/// it passed.
///
/// That is the same hole a real provider fell through. Android's image picker
/// returns `/data/user/0/<pkg>/cache/scaled_1234.jpg`, which starts with a
/// slash, so it was also judged "already uploaded", and the phone's own path
/// went into the database. Nothing was ever uploaded and the admin console had
/// nothing to open.
///
/// Uploading a real file is what makes this test able to see that again.
late Directory _docsDir;

/// The smallest valid PNG, so the server's content-type check is satisfied.
final _pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

String _docPath(String name) {
  final f = File('${_docsDir.path}/$name');
  if (!f.existsSync()) f.writeAsBytesSync(_pngBytes);
  return f.path;
}

ProviderProfile _draft(String mobile, {bool noFees = false}) => ProviderProfile(
      id: '',
      kind: ProviderKind.freelancer,
      name: 'Flutter Integration Provider',
      gender: 'Female',
      dob: DateTime(1990, 6, 15),
      mobile: mobile,
      email: 'provider@example.com',
      address: '4 Integration Lane',
      lat: 23.0225,
      lng: 72.5714,
      workPref: WorkPreference(days: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'], timeFrom: '09:00', timeTo: '18:00'),
      expertise: [ServiceType.companion],
      hourlyRate: noFees ? null : 300,
      noFees: noFees,
      pin: '246810',
      policeVerification: ProviderDocument(
        url: _docPath('police.png'),
        validFrom: DateTime(2026, 1, 1),
        validTo: DateTime(2027, 1, 1),
      ),
      medicalCertificate: ProviderDocument(
        url: _docPath('medical.png'),
        validFrom: DateTime(2026, 2, 1),
        validTo: DateTime(2027, 2, 1),
      ),
    );

/// A fresh backend with its own device id, already registered and signed in.
Future<ApiBackend> _registered({bool noFees = false}) async {
  final api = ApiBackend(_base, deviceId: 'flutter-test-${DateTime.now().microsecondsSinceEpoch}');
  await api.completeRegistration(_draft(_mobile(), noFees: noFees));
  final id = _numericId(api.currentProvider?.id);
  if (id != null) _createdProviderIds.add(id);
  return api;
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


/// Registers and notes the id, so tearDownAll can remove the account again.
/// Tests that call completeRegistration directly must go through this, or the
/// row is left behind in the live directory.
Future<void> _registerAndRecord(ApiBackend api, ProviderProfile draft) async {
  await api.completeRegistration(draft);
  final id = _numericId(api.currentProvider?.id);
  if (id != null) _createdProviderIds.add(id);
}

void main() {
  late bool up;

  setUpAll(() async {
    _docsDir = Directory.systemTemp.createTempSync('sathiyaa-provider-docs');
    up = await _serverUp();
    if (!up) {
      // ignore: avoid_print
      print('No Sathiyaa API at $_base — skipping the live integration tests.');
    }
  });

  tearDownAll(() async {
    await _cleanUpCreatedAccounts();
    if (_docsDir.existsSync()) _docsDir.deleteSync(recursive: true);
  });

  group('provider ApiBackend against a live server', () {
    test('registers a provider and reads the profile back', () async {
      if (!up) return;
      final api = await _registered();

      expect(api.currentProvider, isNotNull);
      expect(api.currentProvider!.id, startsWith('SP-'));
      expect(api.currentProvider!.name, 'Flutter Integration Provider');
      expect(api.currentProvider!.workPref.days.length, 5);
      expect(api.currentProvider!.expertise, contains(ServiceType.companion));
      // Registration is not self-approving — an admin still has to review.
      expect(api.currentProvider!.approvalStatus, 'pending');
      // Fields the register endpoint drops are backfilled through PUT.
      expect(api.currentProvider!.medicalCertificate.url, isNotNull);
      // And it is a path on the SERVER, not the path the file had on this
      // machine. Storing the local path is precisely the bug that shipped.
      expect(api.currentProvider!.medicalCertificate.url, startsWith('/uploads/'),
          reason: 'the document was not uploaded; the local path was stored instead');
      expect(api.currentProvider!.policeVerification.url, startsWith('/uploads/'));
      expect(api.currentProvider!.policeVerification.validTo, isNotNull);
    });

    test('a No Fees provider is stored as donating, not as a zero rate', () async {
      if (!up) return;
      final api = await _registered(noFees: true);
      expect(api.currentProvider!.noFees, isTrue);
    });

    test('signs in again with the PIN from the same device', () async {
      if (!up) return;
      final mobile = _mobile();
      final device = 'flutter-test-pin-${DateTime.now().microsecondsSinceEpoch}';
      final api = ApiBackend(_base, deviceId: device);
      await _registerAndRecord(api, _draft(mobile));

      final again = ApiBackend(_base, deviceId: device);
      await again.loginWithPin(mobile, '246810');
      expect(again.currentProvider!.mobile, mobile);
    });

    test('rejects a wrong PIN', () async {
      if (!up) return;
      final mobile = _mobile();
      final device = 'flutter-test-badpin-${DateTime.now().microsecondsSinceEpoch}';
      final api = ApiBackend(_base, deviceId: device);
      await _registerAndRecord(api, _draft(mobile));

      final again = ApiBackend(_base, deviceId: device);
      await expectLater(again.loginWithPin(mobile, '000000'), throwsA(isA<ApiException>()));
    });

    test('binds the account to one device, as the spec requires', () async {
      if (!up) return;
      final mobile = _mobile();
      final api = ApiBackend(_base, deviceId: 'flutter-device-A-${DateTime.now().microsecondsSinceEpoch}');
      await _registerAndRecord(api, _draft(mobile));
      await api.loginWithPin(mobile, '246810');

      // A second phone with the right PIN is still refused.
      final other = ApiBackend(_base, deviceId: 'flutter-device-B-${DateTime.now().microsecondsSinceEpoch}');
      await expectLater(other.loginWithPin(mobile, '246810'), throwsA(isA<ApiException>()));
    });

    test('turns location sharing on and records a position', () async {
      if (!up) return;
      final api = await _registered();

      await api.setLocationOn(true);
      expect(api.currentProvider!.locationOn, isTrue);

      await api.pingLocation(23.0225, 72.5714);
      expect(api.currentProvider!.currentLat, closeTo(23.0225, 0.001));
      expect(api.currentProvider!.currentLng, closeTo(72.5714, 0.001));
    });

    test('refuses to accept a request while location sharing is off', () async {
      if (!up) return;
      final api = await _registered();
      await api.setLocationOn(false);

      await expectLater(
        api.acceptBooking('1'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('location sharing on'))),
      );
    });

    test('blocks and unblocks calendar dates', () async {
      if (!up) return;
      final api = await _registered();

      final far = DateTime.now().add(const Duration(days: 240));
      expect(api.isBlocked(far), isFalse);

      final block = await api.blockCalendar(from: far, to: far, reason: 'integration test');
      expect(api.isBlocked(far), isTrue);
      expect(api.freeHoursOn(far), 0);

      await api.unblockCalendar(block.id);
      expect(api.isBlocked(far), isFalse);
    });

    test('reads calendar blocks back from the server after a refresh', () async {
      if (!up) return;
      final mobile = _mobile();
      final device = 'flutter-blocks-${DateTime.now().microsecondsSinceEpoch}';
      final api = ApiBackend(_base, deviceId: device);
      await _registerAndRecord(api, _draft(mobile));

      final far = DateTime.now().add(const Duration(days: 300));
      await api.blockCalendar(from: far, to: far.add(const Duration(days: 2)), reason: 'Away');

      // A fresh client for the same account - nothing carried over in memory -
      // must still see the block. This is what was missing before the GET
      // endpoint existed.
      final fresh = ApiBackend(_base, deviceId: device);
      await fresh.loginWithPin(mobile, '246810');
      expect(fresh.calendarBlocks, hasLength(1));
      expect(fresh.calendarBlocks.first.reason, 'Away');
      expect(fresh.isBlocked(far), isTrue);
      expect(fresh.isBlocked(far.add(const Duration(days: 1))), isTrue);
      expect(fresh.isBlocked(far.add(const Duration(days: 5))), isFalse);
      expect(fresh.freeHoursOn(far), 0);

      await fresh.unblockCalendar(fresh.calendarBlocks.first.id);
      final again = ApiBackend(_base, deviceId: device);
      await again.loginWithPin(mobile, '246810');
      expect(again.calendarBlocks, isEmpty);
    });

    test('derives free hours from the work window it registered with', () async {
      if (!up) return;
      final api = await _registered();

      // Registered Mon-Fri 09:00-18:00, so a weekday is nine free hours and a
      // Sunday is not a working day at all.
      var weekday = DateTime.now().add(const Duration(days: 30));
      while (weekday.weekday > DateTime.friday) {
        weekday = weekday.add(const Duration(days: 1));
      }
      expect(api.worksOn(weekday), isTrue);
      expect(api.freeHoursOn(weekday), 9);

      var sunday = weekday;
      while (sunday.weekday != DateTime.sunday) {
        sunday = sunday.add(const Duration(days: 1));
      }
      expect(api.worksOn(sunday), isFalse);
      expect(api.freeHoursOn(sunday), 0);
    });

    test('dashboard periods bracket each other', () async {
      if (!up) return;
      final api = await _registered();
      final today = api.statsFor('Today');
      final year = api.statsFor('Annual');
      expect(year.appointments, greaterThanOrEqualTo(today.appointments));
      expect(year.revenue, greaterThanOrEqualTo(today.revenue));
    });

    test('shares the period boundaries with the offline backend', () {
      final now = DateTime.now();
      expect(periodStart('Annual', now), DateTime(now.year, 1, 1));
      expect(periodStart('Month', now), DateTime(now.year, now.month, 1));
      expect(periodStart('Quarter', now), DateTime(now.year, ((now.month - 1) ~/ 3) * 3 + 1, 1));
      expect(hoursBetween('09:00', '18:00'), 9);
      expect(hoursBetween('18:00', '09:00'), 0); // never negative
    });

    test('a token keeps working on a fresh client, as after an app restart', () async {
      if (!up) return;
      final api = await _registered();
      final id = api.currentProvider!.id;

      // A brand-new client holding only the saved token — the state the app is
      // in on its next launch. Crucially this must NOT trip device binding,
      // because it is the same device.
      final restarted = ApiBackend(_base, deviceId: 'restart-check');
      restarted.restoreToken(api.currentToken);
      await restarted.refresh();

      expect(restarted.currentProvider, isNotNull);
      expect(restarted.currentProvider!.id, id);
    });

    test('reports a useful error when the server is unreachable', () async {
      final broken = ApiBackend('http://127.0.0.1:1/api/v1');
      await expectLater(
        broken.loginWithPin('9600000000', '123456'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'NETWORK')
            .having((e) => e.message, 'message', contains('Cannot reach the server'))),
      );
    });
  });
}
