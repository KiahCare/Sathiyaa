import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sathiyaa_customer/backend.dart';
import 'package:sathiyaa_customer/main.dart';
import 'package:sathiyaa_customer/mock_data.dart';
import 'package:sathiyaa_customer/models.dart';
import 'package:sathiyaa_customer/city_defaults.dart';
import 'package:sathiyaa_customer/widgets/sathiyaa_ui.dart';

void main() {
  // The default 800x600 test surface is shorter than a phone, and these are
  // long scrolling forms; a taller surface keeps the whole profile built so
  // finders don't miss widgets that are merely off-screen.
  setUp(() async {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 2400);
    view.devicePixelRatio = 1.0;

    // Demo sign-in is remembered across restarts now, which means the store has
    // to exist even in a unit test — signing in or out writes to it.
    SharedPreferences.setMockInitialValues({});

    // And the app no longer opens already signed in, so anything below that
    // expects a customer has to say so. One place, so a test that signs out
    // cannot leave the next one wondering why its profile is null.
    await MockBackend.instance.openDemoAccount();
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('a first run opens on Welcome, not already signed in', (tester) async {
    // The app used to open as Anita Verma on demo data, so a first-time viewer
    // never saw the welcome screen, the sign-up or the one-time code — the
    // journey the app exists to show.
    await MockBackend.instance.signOut();

    await tester.pumpWidget(const SathiyaaCustomerApp());
    await tester.pumpAndSettle();

    expect(find.text('Create an account'), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);
    expect(find.text('EMERGENCY SOS'), findsNothing);
  });

  testWidgets('and the demo account is still one tap away', (tester) async {
    // The other half of it: making somebody register before they can look at
    // anything would be a worse app, not a more honest one.
    await MockBackend.instance.signOut();

    await tester.pumpWidget(const SathiyaaCustomerApp());
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Open the demo account'));
    await tester.pumpAndSettle();

    expect(find.text('EMERGENCY SOS'), findsOneWidget);
    expect(MockBackend.instance.currentCustomer?.name, 'Anita Verma');
  });

  testWidgets('boots into Home, and the Companion tab carries the search inputs',
      (tester) async {
    await tester.pumpWidget(const SathiyaaCustomerApp());
    await tester.pumpAndSettle();

    // Home is the first tab. The SOS card is the one thing always on it.
    expect(find.text('EMERGENCY SOS'), findsOneWidget);

    await tester.tap(find.text('Companion'));
    await tester.pumpAndSettle();

    // Distance used to be a fourth search input, a "Within N km" slider. It
    // was asking the customer to solve the app's problem -- nobody arranging
    // care for a parent thinks in kilometres -- and every value it offered
    // other than the widest could only hide carers. It is a default now.
    expect(find.text('Within'), findsNothing);
    // Not findsOneWidget: now the demo directory is a realistic size, a result
    // card's skill tag can carry the same word as the care-type card above it.
    expect(find.text('Physiotherapy'), findsWidgets);
    // Nurse and Physiotherapy are shown but cannot be booked yet, and say so
    // rather than being quietly missing.
    expect(find.text('Coming soon'), findsNWidgets(2));
    expect(find.text('Search'), findsOneWidget);
  });

  testWidgets('profile shows the six collapsible sections and expands one', (tester) async {
    await tester.pumpWidget(const SathiyaaCustomerApp());
    await tester.pumpAndSettle();

    // Profile is reached from the avatar in the header now, not a nav tab —
    // the fourth slot earns more as Help.
    await tester.tap(find.byType(InitialsAvatar).first);
    await tester.pumpAndSettle();
    // The AppBar title went when the profile got a brand header — the
    // customer's own name is the heading now.
    expect(find.text('Health record'), findsOneWidget);

    final list = find.byType(ListView).first;
    final scrollable = find.descendant(of: list, matching: find.byType(Scrollable)).first;
    for (final section in ['Vitals', 'Medications', 'Surgeries', 'Allergies', 'Insurance', 'Family details']) {
      await tester.scrollUntilVisible(find.text(section), 200, scrollable: scrollable);
      expect(find.text(section), findsOneWidget, reason: '$section section missing');
    }

    await tester.tap(find.text('Medications'));
    await tester.pumpAndSettle();
    expect(find.text('Add medication'), findsOneWidget);
  });

  test('the app defaults to the offline demo backend', () {
    expect(Backend.mode, BackendMode.mock);
    expect(Backend.instance, isA<MockBackend>());
    expect(Backend.instance.supportsSimulation, isTrue);
  });

  test('server addresses are normalised the way people type them', () {
    expect(Backend.normaliseForDisplay('192.168.1.5:4000'), 'http://192.168.1.5:4000/api/v1');
    expect(Backend.normaliseForDisplay('http://192.168.1.5:4000/'), 'http://192.168.1.5:4000/api/v1');
    expect(Backend.normaliseForDisplay('http://192.168.1.5:4000/api/v1'), 'http://192.168.1.5:4000/api/v1');
    expect(Backend.normaliseForDisplay('https://api.sathiyaa.in'), 'https://api.sathiyaa.in/api/v1');
  });

  test('cancellation fee follows the spec tiers', () {
    Booking seed(String id, Duration untilStart) {
      final start = DateTime.now().add(untilStart);
      return Booking(
        id: id,
        customerId: 'c',
        providerId: 'PROV-000101',
        serviceType: ServiceType.companion,
        startDate: start,
        endDate: start,
        timeFrom: '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
        timeTo: '23:59',
        status: BookingStatus.confirmed,
        bookingCharge: 100,
        bookingChargePaid: true,
      );
    }

    // Under 24 hours out: no refund.
    final soon = defaultCancellationQuote(seed('T-soon', const Duration(hours: 6)));
    expect(soon.feeAmount, 100);
    expect(soon.refundAmount, 0);

    // Between 24 and 36 hours: half the charge is kept.
    final mid = defaultCancellationQuote(seed('T-mid', const Duration(hours: 30)));
    expect(mid.feeAmount, 50);
    expect(mid.refundAmount, 50);

    // More than 36 hours out: full refund.
    final early = defaultCancellationQuote(seed('T-early', const Duration(hours: 72)));
    expect(early.feeAmount, 0);
    expect(early.refundAmount, 100);
  });

  test('health sections cap at five records', () async {
    final back = MockBackend.instance;
    back.currentCustomer!.surgeries.clear();
    for (var i = 0; i < 5; i++) {
      await back.addSurgery(SurgeryRecord(id: 'cap$i', name: 'Op $i', date: DateTime.now()));
    }
    await expectLater(
      back.addSurgery(SurgeryRecord(id: 'cap5', name: 'One too many', date: DateTime.now())),
      throwsA(isA<Exception>()),
    );

    // Deleting one frees a slot again.
    await back.deleteSurgery('cap0');
    await back.addSurgery(SurgeryRecord(id: 'cap5', name: 'Now it fits', date: DateTime.now()));
    expect(back.currentCustomer!.surgeries.length, 5);
  });

  test('vitals are stored per metric and filtered per metric for the graph', () async {
    final back = MockBackend.instance;
    back.currentCustomer!.vitals.clear();
    await back.addVital(VitalRecord(
      id: 'x1', date: DateTime.now().subtract(const Duration(days: 3)), type: VitalType.bp, valuePrimary: 130, valueSecondary: 85));
    await back.addVital(VitalRecord(
      id: 'x2', date: DateTime.now().subtract(const Duration(days: 1)), type: VitalType.bp, valuePrimary: 126, valueSecondary: 80));
    await back.addVital(VitalRecord(
      id: 'x3', date: DateTime.now(), type: VitalType.pulse, valuePrimary: 72));

    expect(back.vitalsWithin(30, type: VitalType.bp).length, 2);
    expect(back.vitalsWithin(30, type: VitalType.pulse).length, 1);
    expect(back.vitalsWithin(30).length, 3);
    // BP renders as systolic/diastolic; single-value metrics don't.
    expect(back.vitalsWithin(30, type: VitalType.bp).first.display, contains('/'));
    expect(back.vitalsWithin(30, type: VitalType.pulse).first.display, isNot(contains('/')));
  });

  test('offline, a new booking also waits for a provider before payment', () async {
    final back = MockBackend.instance;
    final day = DateTime.now().add(const Duration(days: 2));
    final b = await back.createBooking(
      providerIds: ['PROV-000101'],
      type: ServiceType.companion,
      start: day,
      end: day,
      timeFrom: '10:00',
      timeTo: '14:00',
    );

    // Demo mode mirrors the server rather than being more permissive, so a
    // flow that works offline also works against a real backend.
    expect(b.status, BookingStatus.searching);
    await expectLater(back.payBookingCharge(b.id), throwsA(isA<Exception>()));

    // A provider "accepts" a few seconds later, since there is no second phone.
    await Future<void>.delayed(const Duration(seconds: 5));
    expect(b.status, BookingStatus.pendingPayment);
    expect(b.paymentDeadline, isNotNull);

    await back.payBookingCharge(b.id);
    expect(b.status, BookingStatus.confirmed);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('search narrows by distance and service type', () async {
    final back = MockBackend.instance;
    final near = await back.search(
      type: ServiceType.companion,
      lat: kDefaultLat,
      lng: kDefaultLng,
      radiusKm: 50,
    );
    expect(near, isNotEmpty);
    expect(near.every((p) => p.expertise.contains(ServiceType.companion)), isTrue);

    final tooFar = await back.search(
      type: ServiceType.companion,
      lat: 19.0760, // Mumbai — 440 km from the seeded Ahmedabad providers
      lng: 72.8777,
      radiusKm: 25,
    );
    expect(tooFar, isEmpty);
  });

  test('on demo data a mobile number is an account, not a fresh start', () async {
    final back = MockBackend.instance;
    final before = back.currentCustomer!;
    expect(before.name, 'Anita Verma');

    // Signing out used to drop the only reference to the account, so the next
    // login minted a blank "New Customer" and the seeded profile, bookings and
    // health record were gone for good.
    await back.signOut();
    expect(back.currentCustomer, isNull);

    final otp = await back.loginRequestOtp(before.mobile);
    await back.verifyOtp(before.mobile, otp!);

    expect(back.currentCustomer!.id, before.id);
    expect(back.currentCustomer!.name, 'Anita Verma');
    expect(back.currentCustomer!.addresses, isNotEmpty);
  });

  test('registering on a number that already has an account is refused', () async {
    final back = MockBackend.instance;
    await expectLater(
      back.registerCustomer(name: 'Someone Else', mobile: back.currentCustomer!.mobile),
      throwsA(isA<Exception>()),
    );
    // Still signed in as whoever we were.
    expect(back.currentCustomer!.name, 'Anita Verma');
  });


  test('a booking can be made for somebody other than the account holder', () async {
    final back = MockBackend.instance;
    final mother = back.currentCustomer!.family.firstWhere((f) => f.relationship == 'Mother');

    final forThem = await back.createBooking(
      providerIds: [back.providers.first.id],
      type: ServiceType.companion,
      start: DateTime.now().add(const Duration(days: 3)),
      end: DateTime.now().add(const Duration(days: 3)),
      timeFrom: '10:00',
      timeTo: '14:00',
      forMember: mother,
    );
    // The name the carer knocks and asks for.
    expect(forThem.forName, mother.name);
    expect(forThem.forRelationship, 'Mother');
    expect(forThem.forContactNumber, isNotNull);

    final forSelf = await back.createBooking(
      providerIds: [back.providers.first.id],
      type: ServiceType.companion,
      start: DateTime.now().add(const Duration(days: 4)),
      end: DateTime.now().add(const Duration(days: 4)),
      timeFrom: '10:00',
      timeTo: '14:00',
    );
    // Null, not an empty string: "for the account holder" is the absence of a
    // dependent, and every screen keys off that.
    expect(forSelf.forName, isNull);
  });

  test('seeded demo data stays inside the five-record cap', () async {
    // Demo data that breaks the app's own rules teaches the wrong thing, and
    // this is how it happens: filling a section out to look rich puts it in a
    // state no real customer can reach. A first pass at this seeded twelve
    // vitals against a cap of five, and the section badge read "12/5".
    //
    // The cap is enforced in both backends and comes from the requirements, so
    // it is the seed that has to give way, not the rule.
    final c = MockBackend.instance.currentCustomer!;
    expect(c.vitals.length, lessThanOrEqualTo(5), reason: 'vitals over the cap');
    expect(c.medications.length, lessThanOrEqualTo(5), reason: 'medications over the cap');
    expect(c.surgeries.length, lessThanOrEqualTo(5), reason: 'surgeries over the cap');
    expect(c.allergies.length, lessThanOrEqualTo(5), reason: 'allergies over the cap');
    expect(c.insurance.length, lessThanOrEqualTo(5), reason: 'insurance over the cap');
    expect(c.family.length, lessThanOrEqualTo(5), reason: 'family over the cap');

    // And a slot left free, so adding a record works in a demo rather than
    // hitting the cap on the first tap.
    expect(c.vitals.length, lessThan(5), reason: 'no room to add a vital');
  });

  test('several carers can be asked at once, and the first to accept takes it', () async {
    final back = MockBackend.instance;
    final three = back.providers
        .where((p) => p.approved && p.expertise.contains(ServiceType.companion))
        .take(3)
        .toList();
    expect(three.length, 3, reason: 'demo directory should hold three companions');

    final b = await back.createBooking(
      providerIds: three.map((p) => p.id).toList(),
      type: ServiceType.companion,
      start: DateTime.now().add(const Duration(days: 5)),
      end: DateTime.now().add(const Duration(days: 5)),
      timeFrom: '10:00',
      timeTo: '14:00',
    );

    expect(b.providersNotified, 3);
    expect(b.chosenByCustomer, isTrue);
    expect(b.askedNames.toSet(), three.map((p) => p.name).toSet());

    // Nobody has it yet. Naming a carer here — the first of the three, say —
    // would have the tracking screen announce somebody who never answered.
    expect(b.providerId, isEmpty);
    expect(b.status, BookingStatus.searching);

    // One of the three accepts, and it is one of the three.
    await Future<void>.delayed(const Duration(seconds: 5));
    expect(b.status, BookingStatus.pendingPayment);
    expect(three.map((p) => p.id), contains(b.providerId));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('asking only carers who cannot take it is refused, not silently emptied', () async {
    final back = MockBackend.instance;
    await expectLater(
      back.createBooking(
        providerIds: const ['PROV-does-not-exist', 'PROV-nor-this-one'],
        type: ServiceType.companion,
        start: DateTime.now().add(const Duration(days: 6)),
        end: DateTime.now().add(const Duration(days: 6)),
        timeFrom: '10:00',
        timeTo: '14:00',
      ),
      throwsA(isA<Exception>()),
    );
  });

}
