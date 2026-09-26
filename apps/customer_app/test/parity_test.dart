@Timeout(Duration(minutes: 3))
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:sathiyaa_customer/api/api_backend.dart';
import 'package:sathiyaa_customer/api/api_client.dart';
import 'package:sathiyaa_customer/backend.dart';
import 'package:sathiyaa_customer/mock_data.dart';
import 'package:sathiyaa_customer/models.dart';

/// Demo and live must behave the same.
///
/// The complaint that started this file was "the app works differently when I
/// use live" — and it did: offline you could pay for a booking the moment you
/// made it, while the server put new bookings in `searching` and refused
/// payment until a provider accepted. Two backends, two flows, one UI written
/// against the wrong one.
///
/// So rather than test each backend against its own expectations, this runs
/// one script against both and asserts they agree at every step. A future
/// change that drifts them apart fails here instead of on a phone.
const _base = String.fromEnvironment('SATHIYAA_API', defaultValue: 'http://localhost:4000/api/v1');

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

DateTime _nextWeekday({int inDays = 3}) {
  var d = DateTime.now().add(Duration(days: inDays));
  while (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
    d = d.add(const Duration(days: 1));
  }
  return d;
}

/// What both backends must agree on, gathered by running the same steps.
class Observed {
  final List<String> steps = [];
  void record(String step) => steps.add(step);
}

/// Signs in, searches, books, and tries to pay too early — the exact sequence
/// a person follows on the booking screen.
Future<Observed> runScript(SathiyaaBackend b, {required bool live}) async {
  final o = Observed();
  final mobile = '9${DateTime.now().microsecondsSinceEpoch % 900000000 + 100000000}';

  final otp = await b.registerCustomer(name: 'Parity Tester', mobile: mobile);
  o.record('register returns otp: ${otp != null}');
  await b.verifyOtp(mobile, otp ?? '123456');
  o.record('signed in: ${b.currentCustomer != null}');

  // The combination that used to fail against the server and succeed offline:
  // every contact mode ticked at once.
  var savedAllModes = false;
  try {
    await b.setContactPreference(
      modes: {ContactMode.email, ContactMode.call, ContactMode.sms},
      timeframe: '09:00-18:00',
    );
    savedAllModes = true;
  } catch (_) {
    savedAllModes = false;
  }
  o.record('all three contact modes save: $savedAllModes');
  o.record('and are remembered: ${b.currentCustomer?.contactModes.length == 3}');

  // Picking exactly one must work too -- that was the only case that used to.
  var savedOneMode = false;
  try {
    await b.setContactPreference(modes: {ContactMode.call}, timeframe: '10:00-17:00');
    savedOneMode = true;
  } catch (_) {
    savedOneMode = false;
  }
  o.record('a single contact mode saves: $savedOneMode');

  // Picking none is a mistake, not a valid choice, and both sides say so.
  var refusedEmpty = false;
  try {
    await b.setContactPreference(modes: <ContactMode>{});
  } catch (_) {
    refusedEmpty = true;
  }
  o.record('no contact mode at all is refused: $refusedEmpty');

  final day = _nextWeekday();
  final found = await b.search(
    type: ServiceType.nurse,
    dateFrom: day,
    dateTo: day,
    timeFrom: '09:00',
    timeTo: '13:00',
    lat: 23.0494,
    lng: 72.5388,
    radiusKm: 25,
  );
  o.record('search returns results: ${found.isNotEmpty}');
  o.record('results carry a distance: ${found.every((p) => p.distanceKm != null)}');
  // hourlyRate is null for a No-Fees provider, which is a valid rate, not a gap.
  o.record('results carry a rate or are no-fees: ${found.every((p) => p.noFees || (p.hourlyRate ?? 0) > 0)}');

  final booking = await b.createBooking(
    providerIds: [found.first.id],
    type: ServiceType.nurse,
    start: day,
    end: day,
    timeFrom: '09:00',
    timeTo: '13:00',
  );
  o.record('new booking status: ${booking.status.name}');
  o.record('new booking is not yet payable: ${booking.status != BookingStatus.pendingPayment}');

  // The bug this file exists for: offline this used to succeed.
  var refusedEarly = false;
  try {
    await b.payBookingCharge(booking.id);
  } catch (_) {
    refusedEarly = true;
  }
  o.record('paying before acceptance is refused: $refusedEarly');

  // Deliberately not compared past this point: offline, a simulated provider
  // accepts after a few seconds so the demo can be walked through on one
  // phone, whereas live it stays in `searching` until a real provider taps
  // Accept in the other app. That difference is the point of demo mode, not a
  // defect -- what has to match is everything above, which is the part the
  // customer's screen depends on.
  final current = await b.refreshBooking(booking.id);
  o.record('booking is readable after creation: ${current.id == booking.id}');

  return o;
}

void main() {
  test('demo and live agree on the booking flow', () async {
    if (!await _serverUp()) {
      markTestSkipped('no backend on $_base — start it to run the parity check');
      return;
    }

    final mock = await runScript(MockBackend.instance, live: false);
    final live = await runScript(ApiBackend(_base), live: true);

    // Printed as well as compared: a green tick that says nothing is hard to
    // trust, and this makes it obvious which steps were actually exercised.
    // ignore: avoid_print
    print('demo and live agreed on:');
    for (final step in mock.steps) {
      // ignore: avoid_print
      print('    - $step');
    }

    // Compared step by step so a failure names the step that diverged rather
    // than just saying two lists differ.
    expect(live.steps.length, mock.steps.length);
    for (var i = 0; i < mock.steps.length; i++) {
      expect(live.steps[i], mock.steps[i], reason: 'demo and live disagree at step ${i + 1}');
    }
  });
}
