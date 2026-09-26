import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sathiyaa_provider/main.dart';
import 'package:sathiyaa_provider/api/api_backend.dart' show periodStart;
import 'package:sathiyaa_provider/backend.dart';
import 'package:sathiyaa_provider/mock_data.dart';
import 'package:sathiyaa_provider/models.dart';

void main() {
  // A taller-than-default surface so long scrolling screens stay fully built.
  setUp(() async {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 2400);
    view.devicePixelRatio = 1.0;

    // Demo sign-in is remembered across restarts now, which means the store has
    // to exist even in a unit test — signing in or out writes to it.
    SharedPreferences.setMockInitialValues({});

    // And the app no longer opens already signed in, so anything below that
    // expects a provider has to say so. One place, so a test that signs out
    // cannot leave the next one wondering why its account is null.
    await MockBackend.instance.openDemoAccount();
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('a first run opens on Welcome, not already signed in', (tester) async {
    // The app used to open as Karuna Companion Services on demo data, so a
    // first-time viewer never saw the welcome screen or the sign-in.
    await MockBackend.instance.signOut();

    await tester.pumpWidget(const SathiyaaProviderApp());
    await tester.pumpAndSettle();

    expect(find.text('Register as a provider'), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);
  });

  testWidgets('and the demo account is still one tap away', (tester) async {
    // The skip button used to walk into the home shell without signing in,
    // which was harmless only while demo data opened already signed in. It
    // has to actually sign in now, or the first screen reads currentProvider!
    // and the app dies.
    await MockBackend.instance.signOut();

    await tester.pumpWidget(const SathiyaaProviderApp());
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('look around with the demo account'));
    // Not pumpAndSettle: the on-duty card's pulse repeats for as long as the
    // provider is on duty, so nothing on the dashboard ever settles. Pumped in
    // steps rather than one long frame because the tap handler signs in first,
    // and the route transition only starts once that has finished.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    expect(MockBackend.instance.currentProvider?.name, 'Karuna Companion Services');
    expect(find.text('Register as a provider'), findsNothing);
    // The demo account is an ORGANISATION, and an agency does not go on duty
    // -- its carers do. Where a freelancer sees a duty switch, an agency sees
    // how many of its people can be sent to a family, which is the thing it
    // opens this screen for.
    expect(find.textContaining('DUTY'), findsNothing);
    expect(find.text('YOUR CARERS'), findsOneWidget);
  });

  testWidgets('dashboard shows the location gate and the period selector', (tester) async {
    await tester.pumpWidget(const SathiyaaProviderApp());
    // Not pumpAndSettle: the on-duty card's pulse repeats for as long as the
    // provider is on duty, so nothing ever "settles" here.
    await tester.pump(const Duration(milliseconds: 600));

    // The demo account is an organisation, so the top card is about its
    // carers rather than its own availability.
    expect(find.text('YOUR CARERS'), findsOneWidget);
    expect(find.text("Today's work"), findsOneWidget);
    expect(find.text('Earnings'), findsOneWidget);
  });

  testWidgets('a freelancer gets the duty switch, and only once approved',
      (tester) async {
    // The other half of the same change. A carer whose application is still
    // being checked could switch themselves on duty, watch nothing arrive,
    // and have nothing on screen connecting the two.
    final back = MockBackend.instance;
    await back.openDemoAccount();
    final p = back.currentProvider!;
    p.kind = ProviderKind.freelancer;
    p.approvalStatus = 'pending';
    p.approved = false;

    await tester.pumpWidget(const SathiyaaProviderApp());
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('You cannot go on duty yet'), findsOneWidget);
    expect(find.byType(Switch), findsNothing,
        reason: 'a switch that cannot work should not be offered');
    expect(find.textContaining('DUTY'), findsNothing);

    // Approved, and the switch is back.
    p.approvalStatus = 'approved';
    p.approved = true;
    // Pump something else in between. `const SathiyaaProviderApp()` is a
    // canonicalised constant, so pumping it twice hands the framework the
    // identical widget and it rebuilds nothing -- the screen would still be
    // showing the pending state and the test would pass or fail for the wrong
    // reason.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const SathiyaaProviderApp());
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.textContaining('DUTY'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);

    // Put the demo account back as the other tests expect to find it.
    p.kind = ProviderKind.organization;
  });

  testWidgets('calendar tab renders the month grid and the legend', (tester) async {
    await tester.pumpWidget(const SathiyaaProviderApp());
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.text('Calendar'));
    // The dashboard stays mounted behind the IndexedStack, pulse and all.
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('My calendar'), findsOneWidget);
    expect(find.text('Booked'), findsOneWidget);
    expect(find.text('Blocked'), findsOneWidget);
    expect(find.text('Not a work day'), findsWidgets);
  });

  test('a request cannot be accepted while location sharing is off', () async {
    final back = MockBackend.instance;
    final booking = back.myBookings.firstWhere((b) => b.status == BookingStatus.requested);

    await back.setLocationOn(false);
    await expectLater(back.acceptBooking(booking.id), throwsA(isA<Exception>()));
    expect(booking.status, BookingStatus.requested);

    await back.setLocationOn(true);
    await back.acceptBooking(booking.id);
    expect(booking.status, BookingStatus.accepted);
  });

  test('the start OTP is withheld until the face and geofence check passes', () async {
    final back = MockBackend.instance;
    await back.setLocationOn(true);
    final booking = back.myBookings.firstWhere((b) => b.status == BookingStatus.accepted);
    booking.faceVerifiedAt = null;

    await expectLater(back.startService(booking.id), throwsA(isA<Exception>()));

    // Standing far away fails the geofence half of the check.
    await back.pingLocation(booking.customerLat + 1, booking.customerLng + 1);
    final away = await back.verifyFaceAndGeofence(booking.id);
    expect(away.passed, isFalse);

    // On site, it passes and the OTP is issued.
    await back.pingLocation(booking.customerLat, booking.customerLng);
    final onSite = await back.verifyFaceAndGeofence(booking.id);
    expect(onSite.passed, isTrue);
    final otp = await back.startService(booking.id);
    expect(otp.length, 6);
  });

  test('dashboard figures respond to the period selector', () {
    final back = MockBackend.instance;
    final now = DateTime.now();

    expect(periodStart('Annual', now), DateTime(now.year, 1, 1));
    expect(periodStart('Month', now), DateTime(now.year, now.month, 1));
    expect(periodStart('Today', now), DateTime(now.year, now.month, now.day));
    expect(periodStart('Quarter', now), DateTime(now.year, ((now.month - 1) ~/ 3) * 3 + 1, 1));

    // The seeded completed booking is three days old, so it counts for the
    // year but not for today.
    expect(back.statsFor('Annual').appointments >= back.statsFor('Today').appointments, isTrue);
  });

  test('blocking a date range refuses to run over live bookings', () async {
    final back = MockBackend.instance;
    final live = back.myBookings.firstWhere((b) => b.status == BookingStatus.accepted);
    await expectLater(
      back.blockCalendar(from: live.startDate, to: live.endDate),
      throwsA(isA<Exception>()),
    );

    final free = DateTime.now().add(const Duration(days: 200));
    final block = await back.blockCalendar(from: free, to: free, reason: 'Holiday');
    expect(back.isBlocked(free), isTrue);
    expect(back.freeHoursOn(free), 0);

    await back.unblockCalendar(block.id);
    expect(back.isBlocked(free), isFalse);
  });

  test('the app defaults to the offline demo backend', () {
    expect(Backend.mode, BackendMode.mock);
    expect(Backend.instance, isA<MockBackend>());
  });

  test('server addresses are normalised the way people type them', () {
    expect(Backend.normaliseForDisplay('192.168.1.5:4000'), 'http://192.168.1.5:4000/api/v1');
    expect(Backend.normaliseForDisplay('http://192.168.1.5:4000/'), 'http://192.168.1.5:4000/api/v1');
    expect(Backend.normaliseForDisplay('http://192.168.1.5:4000/api/v1'), 'http://192.168.1.5:4000/api/v1');
  });

  test('free hours on a day subtract what is already booked', () {
    final back = MockBackend.instance;
    final booked = back.myBookings.firstWhere((b) => b.status == BookingStatus.accepted);
    final onDay = back.bookingsOn(booked.startDate);
    expect(onDay, isNotEmpty);

    if (back.worksOn(booked.startDate)) {
      // Work window is 09:00-18:00 (9h) and the booking runs 08:00-12:00 (4h).
      expect(back.freeHoursOn(booked.startDate), lessThan(9));
    }
  });

  test('a provider can sign back in on demo data after signing out', () async {
    final back = MockBackend.instance;
    final before = back.currentProvider!;
    final mobile = before.mobile;
    final pin = before.pin!;

    // loginWithPin used to compare against currentProvider, which signOut had
    // just set to null — so every PIN came back "Incorrect PIN" and logging out
    // of the demo was a one-way door.
    await back.signOut();
    expect(back.currentProvider, isNull);

    await expectLater(
      back.loginWithPin(mobile, '000000'),
      throwsA(isA<Exception>()),
    );

    await back.loginWithPin(mobile, pin);
    expect(back.currentProvider!.id, before.id);
    expect(back.currentProvider!.name, before.name);
  });


  test('a job for a dependent names the person being visited', () {
    final back = MockBackend.instance;
    final job = back.bookings.firstWhere((b) => b.isForSomeoneElse);

    // The carer knocks and asks for the person being visited, not the person
    // who paid. Getting that the wrong way round is the whole risk here.
    expect(job.visitingName, job.forName);
    expect(job.visitingName, isNot(job.customerName));
    expect(job.forContactNumber, isNotNull);

    final ordinary = back.bookings.firstWhere((b) => !b.isForSomeoneElse);
    expect(ordinary.visitingName, ordinary.customerName);
  });

}
