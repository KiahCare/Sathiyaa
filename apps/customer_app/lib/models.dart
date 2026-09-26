// Data models for the Sathiyaa Customer app. Kept as plain Dart classes with
// mutable fields so the in-memory mock store (mock_data.dart) can update them
// directly, the same way the real backend would update database rows.

import 'utils/dates.dart';
import 'i18n/l10n.dart';

enum ServiceType { companion, medicalCompanion, nurse, physiotherapy }

extension ServiceTypeLabel on ServiceType {
  /// Whether a customer can book this today.
  ///
  /// Nurse and Physiotherapy are off: there are no verified carers in either
  /// category, so a request would be taken, charged for, and never filled.
  /// This is deliberately a property of the type rather than a filter on the
  /// list, so every screen that offers a choice of care gets the same answer
  /// -- and turning one on later is one word here.
  ///
  /// Note this is the CUSTOMER side only. Carers can still register their
  /// expertise as a nurse or physiotherapist, which is the thing that has to
  /// happen before the category can open.
  bool get bookable =>
      this == ServiceType.companion || this == ServiceType.medicalCompanion;

  String get label {
    switch (this) {
      case ServiceType.companion:
        return t('Companion');
      case ServiceType.medicalCompanion:
        return t('Medical Companion');
      case ServiceType.nurse:
        return t('Nurse');
      case ServiceType.physiotherapy:
        return t('Physiotherapy');
    }
  }
}

/// A booking's life. `searching` is the gap the app used to skip: the request
/// has fanned out to every matching provider and nobody has accepted yet, so
/// there is nothing to pay for. Only once somebody accepts does it become
/// `pendingPayment`, with the spec's 15-minute window to pay.
enum BookingStatus { searching, pendingPayment, confirmed, providerOnWay, inProgress, completed, cancelled }

extension BookingStatusLabel on BookingStatus {
  String get label {
    switch (this) {
      case BookingStatus.searching:
        return t('Finding a provider');
      case BookingStatus.pendingPayment:
        return t('Payment due');
      case BookingStatus.confirmed:
        return t('Confirmed');
      case BookingStatus.providerOnWay:
        return t('On the way');
      case BookingStatus.inProgress:
        return t('In progress');
      case BookingStatus.completed:
        return t('Completed');
      case BookingStatus.cancelled:
        return t('Cancelled');
    }
  }
}

/// How the customer wants to be contacted, and when. Required by the profile
/// spec ("Preferred mode of communication: Email, Call, SMS with timeframe").
enum ContactMode { email, call, sms }

extension ContactModeLabel on ContactMode {
  String get label {
    switch (this) {
      case ContactMode.email:
        return t('Email');
      case ContactMode.call:
        return t('Call');
      case ContactMode.sms:
        return t('SMS');
    }
  }
}

/// What the customer searched for: service, the date *range*, the daily time
/// window and where the service is needed. Carried from the search screen
/// through provider selection into the booking so the booking reflects what
/// was actually asked for rather than a hardcoded slot.
class BookingCriteria {
  final ServiceType serviceType;
  final DateTime startDate;
  final DateTime endDate;
  final String timeFrom; // "HH:mm"
  final String timeTo;
  final double lat;
  final double lng;
  final String locationLabel;

  /// Who the visit is for. Null means the account holder, which is the common
  /// case — but the case this app exists for is somebody arranging care for a
  /// parent, and a carer who knocks asking for the wrong name has already lost
  /// the family.
  final FamilyMember? forMember;

  const BookingCriteria({
    required this.serviceType,
    required this.startDate,
    required this.endDate,
    required this.timeFrom,
    required this.timeTo,
    required this.lat,
    required this.lng,
    required this.locationLabel,
    this.forMember,
  });

  /// The name to put in front of a carer.
  String get forLabel => forMember?.name ?? 'Myself';

  BookingCriteria withMember(FamilyMember? member) => BookingCriteria(
        serviceType: serviceType,
        startDate: startDate,
        endDate: endDate,
        timeFrom: timeFrom,
        timeTo: timeTo,
        lat: lat,
        lng: lng,
        locationLabel: locationLabel,
        forMember: member,
      );

  int get days => endDate.difference(startDate).inDays + 1;

  double get hoursPerDay {
    final f = timeFrom.split(':');
    final t = timeTo.split(':');
    final mins = (int.parse(t[0]) * 60 + int.parse(t[1])) - (int.parse(f[0]) * 60 + int.parse(f[1]));
    return mins <= 0 ? 0 : mins / 60.0;
  }

  double get totalHours => hoursPerDay * days;

  String get dateLabel => startDate == endDate
      ? prettyDate(startDate)
      : '${prettyDay(startDate)} – ${prettyDate(endDate)}';
}

/// Outcome of a cancellation, computed against the spec's fee tiers so the
/// customer sees the fee and refund before confirming.
class CancellationQuote {
  final double hoursBeforeStart;
  final double feeAmount;
  final double refundAmount;
  final String rule;
  const CancellationQuote({
    required this.hoursBeforeStart,
    required this.feeAmount,
    required this.refundAmount,
    required this.rule,
  });
}

class Address {
  String label; // Primary / Secondary
  String line1;
  String city;
  double lat;
  double lng;
  bool isPrimary;
  Address({
    required this.label,
    required this.line1,
    required this.city,
    required this.lat,
    required this.lng,
    this.isPrimary = false,
  });
}

/// The four vital signs the spec asks for. One reading records one of these,
/// matching how the backend stores them (`customer_vitals.vital_type`) so the
/// 5-record cap means the same thing in both places.
enum VitalType { bp, spo2, pulse, glucose }

extension VitalTypeMeta on VitalType {
  String get label {
    switch (this) {
      case VitalType.bp:
        return t('Blood pressure');
      case VitalType.spo2:
        return t('SpO2');
      case VitalType.pulse:
        return t('Pulse');
      case VitalType.glucose:
        return t('Blood glucose');
    }
  }

  String get unit {
    switch (this) {
      case VitalType.bp:
        return 'mmHg';
      case VitalType.spo2:
        return '%';
      case VitalType.pulse:
        return 'bpm';
      case VitalType.glucose:
        return 'mg/dL';
    }
  }

  /// Wire value, matching the backend enum.
  String get wire => name;

  static VitalType fromWire(String v) =>
      VitalType.values.firstWhere((t) => t.name == v, orElse: () => VitalType.bp);
}

class VitalRecord {
  final String id;
  DateTime date;
  VitalType type;
  double valuePrimary; // systolic for BP, the reading for everything else
  double? valueSecondary; // diastolic, BP only

  VitalRecord({
    required this.id,
    required this.date,
    required this.type,
    required this.valuePrimary,
    this.valueSecondary,
  });

  String get display => type == VitalType.bp
      ? '${valuePrimary.toStringAsFixed(0)}/${valueSecondary?.toStringAsFixed(0) ?? '-'} ${type.unit}'
      : '${valuePrimary.toStringAsFixed(valuePrimary.truncateToDouble() == valuePrimary ? 0 : 1)} ${type.unit}';
}

class MedicationRecord {
  final String id;
  String name;
  String frequency;

  /// Either a local file path (just picked, not yet uploaded) or the URL the
  /// server serves it from once it has been.
  String? prescriptionUrl;

  MedicationRecord({
    required this.id,
    required this.name,
    required this.frequency,
    this.prescriptionUrl,
  });

  bool get prescriptionUploaded => prescriptionUrl != null && prescriptionUrl!.isNotEmpty;
}

class SurgeryRecord {
  final String id;
  String name;
  DateTime date;
  SurgeryRecord({required this.id, required this.name, required this.date});
}

class AllergyRecord {
  final String id;
  String name;
  DateTime onsetDate;
  bool active;
  AllergyRecord({required this.id, required this.name, required this.onsetDate, this.active = true});
}

class InsuranceRecord {
  final String id;
  String insuredWith;
  String policyNumber;
  DateTime startDate;
  DateTime endDate;
  InsuranceRecord({
    required this.id,
    required this.insuredWith,
    required this.policyNumber,
    required this.startDate,
    required this.endDate,
  });
}


/// One line in a booking's conversation.
///
/// `system` is the app's own note — "visit started", "running late" — written
/// into the same thread so the history reads as one sequence rather than two
/// that have to be merged in the reader's head.
enum MessageSender { customer, provider, system }

class BookingMessage {
  final String id;
  final MessageSender sender;
  final String body;
  final DateTime sentAt;
  final bool read;

  const BookingMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.sentAt,
    this.read = false,
  });

  static MessageSender senderFromWire(String s) => switch (s) {
        'customer' => MessageSender.customer,
        'provider' => MessageSender.provider,
        _ => MessageSender.system,
      };
}

/// What came back from raising an emergency alert.
///
/// [smsIsLive] is the field that matters. With no SMS provider configured the
/// alert is still recorded — it has to be — but nothing was sent, and the
/// screen has to say so. Telling somebody their family has been notified when
/// no message left is worse than telling them nothing, because it stops them
/// picking up the phone themselves.
class SosResult {
  final String alertId;
  final String delivery; // sent | partial | failed | simulated
  final bool smsIsLive;
  final int notifiedCount;
  final List<SosRecipient> recipients;

  const SosResult({
    required this.alertId,
    required this.delivery,
    required this.smsIsLive,
    required this.notifiedCount,
    this.recipients = const [],
  });

  bool get anythingSent => smsIsLive && notifiedCount > 0;
}

class SosRecipient {
  final String name;
  final String? relationship;
  final String number;
  final bool notified;
  const SosRecipient({
    required this.name,
    this.relationship,
    required this.number,
    this.notified = false,
  });
}

class FamilyMember {
  final String id;
  String name;
  String relationship;
  String contact;
  bool active;
  FamilyMember({required this.id, required this.name, required this.relationship, required this.contact, this.active = true});
}

class Customer {
  String id; // e.g. CUST-000013
  String name;
  String mobile;
  String? email;
  String? photoUrl;
  DateTime? dob;
  String? gender;
  String? bloodGroup;
  List<String> preferredLanguages;
  double? heightCm;
  double? weightKg;
  double? get bmi => (heightCm != null && weightKg != null && heightCm! > 0)
      ? weightKg! / ((heightCm! / 100) * (heightCm! / 100))
      : null;
  List<Address> addresses;
  List<VitalRecord> vitals;
  List<MedicationRecord> medications;
  List<SurgeryRecord> surgeries;
  List<AllergyRecord> allergies;
  List<InsuranceRecord> insurance;
  List<FamilyMember> family;
  List<String> linkedProviderIds; // up to 10
  Set<ContactMode> contactModes;
  String? contactTimeframe; // e.g. "09:00-18:00"
  String? referenceCode; // Business Partner referral code, entered by the customer

  /// The partner's own name, once the server has confirmed the code. Null
  /// when nothing has been applied, or when it has not been checked yet.
  String? referencePartner;

  /// Where this account registered from, and what the server made of it.
  /// Null means the question has never been asked -- everybody who signed up
  /// before the service-area gate existed, and anybody who refused the
  /// location prompt.
  String? signupCity;
  bool? signupInServiceArea;

  bool registrationFeePaid;

  /// What this customer would pay NEXT: the joining fee before they have
  /// paid, the renewal rate afterwards. Read from the server rather than
  /// compiled in — an admin changes it, and the app showing one number while
  /// the server charges another is the one mismatch nobody forgives.
  double registrationFeeAmount;

  /// When the paid year runs out. Null when they have never paid, or when
  /// the row is marked paid with no transaction behind it.
  DateTime? registrationRenewsAt;

  /// Whether that year is up and a renewal can be paid now. Nothing lapses:
  /// the account keeps working either way.
  bool registrationRenewalDue;
  bool termsAccepted;
  bool blocked;
  double ratingAvg;
  int ratingCount;

  Customer({
    required this.id,
    required this.name,
    required this.mobile,
    this.email,
    this.photoUrl,
    this.dob,
    this.gender,
    this.bloodGroup,
    List<String>? preferredLanguages,
    this.heightCm,
    this.weightKg,
    List<Address>? addresses,
    List<VitalRecord>? vitals,
    List<MedicationRecord>? medications,
    List<SurgeryRecord>? surgeries,
    List<AllergyRecord>? allergies,
    List<InsuranceRecord>? insurance,
    List<FamilyMember>? family,
    List<String>? linkedProviderIds,
    Set<ContactMode>? contactModes,
    this.contactTimeframe,
    this.referenceCode,
    this.referencePartner,
    this.signupCity,
    this.signupInServiceArea,
    this.registrationFeePaid = false,
    this.registrationFeeAmount = 499,
    this.registrationRenewsAt,
    this.registrationRenewalDue = false,
    this.termsAccepted = false,
    this.blocked = false,
    this.ratingAvg = 0,
    this.ratingCount = 0,
  })  : preferredLanguages = preferredLanguages ?? [],
        addresses = addresses ?? [],
        vitals = vitals ?? [],
        medications = medications ?? [],
        surgeries = surgeries ?? [],
        allergies = allergies ?? [],
        insurance = insurance ?? [],
        family = family ?? [],
        linkedProviderIds = linkedProviderIds ?? [],
        contactModes = contactModes ?? <ContactMode>{};
}

class Provider {
  final String id; // e.g. PROV-000042
  String name;
  String gender;
  String? photoUrl;
  List<ServiceType> expertise;
  double ratingAvg;
  int ratingCount;
  double? hourlyRate; // null when noFees is true
  bool noFees;
  double lat;
  double lng;
  String city;
  List<String> languages;
  bool approved;
  /// Distance from the searched-for address, when the server ranked it.
  double? distanceKm;

  Provider({
    required this.id,
    required this.name,
    required this.gender,
    this.photoUrl,
    required this.expertise,
    this.ratingAvg = 4.5,
    this.ratingCount = 12,
    this.hourlyRate,
    this.noFees = false,
    required this.lat,
    required this.lng,
    required this.city,
    List<String>? languages,
    this.approved = true,
    this.distanceKm,
  }) : languages = languages ?? ['English', 'Hindi'];
}

class Booking {
  final String id; // e.g. BKG-000123
  final String customerId;

  /// Empty until somebody accepts. The request goes to several carers at once
  /// and the first to take it fills this in, so it cannot be final and cannot
  /// be set hopefully at creation — naming a carer who never answered is worse
  /// than naming nobody.
  String providerId;
  ServiceType serviceType;
  DateTime startDate;
  DateTime endDate;
  String timeFrom;
  String timeTo;
  BookingStatus status;
  double bookingCharge;
  bool bookingChargePaid;
  DateTime? paymentDeadline;
  double amountDue;
  double amountReceived;
  String? otp;
  DateTime? serviceStartedAt;
  DateTime? serviceEndedAt;
  double? totalHours;
  double? totalAmount;
  double? customerRating;
  String? customerComment;
  double? providerRatingOfCustomer;
  String? providerCommentOfCustomer;
  DateTime? cancelledAt;
  double? cancellationFee;
  double? refundAmount;
  /// Set when the server sends the confirmed provider's name alongside the
  /// booking; lets list rows render without a second request.
  String? providerName;

  /// How many providers the request was sent to. Worth showing while waiting:
  /// "asked 4 providers" is reassuring, "asked 0" explains the silence.
  int? providersNotified;

  /// The carers the request actually went to, in the order the server returned
  /// them. Naming them while the request is out is the difference between
  /// "somebody will get back to you" and "Lakshmi, Meera and Anjali have been
  /// asked" — the second is a thing a person can wait for.
  List<String> askedNames;

  /// True when the customer picked the shortlist rather than the request going
  /// to everybody in range. The waiting screen says a different sentence for
  /// each, because they are different promises.
  bool chosenByCustomer;

  /// Chosen but not asked, because they were not free for that window. Zero
  /// most of the time; when it is not, saying so stops somebody waiting for a
  /// first choice who was never contacted.
  int unavailableCount;

  /// Messages from the carer that have not been opened yet. Drives the badge
  /// on the booking row.
  int unreadMessages;

  /// Who the visit is for, as the server reports it. Null means the account
  /// holder. The carer's job sheet reads this before they knock.
  String? forName;
  String? forRelationship;
  String? forContactNumber;

  Booking({
    required this.id,
    required this.customerId,
    required this.providerId,
    required this.serviceType,
    required this.startDate,
    required this.endDate,
    required this.timeFrom,
    required this.timeTo,
    this.status = BookingStatus.pendingPayment,
    this.bookingCharge = 99,
    this.bookingChargePaid = false,
    this.paymentDeadline,
    this.amountDue = 0,
    this.amountReceived = 0,
    this.otp,
    this.serviceStartedAt,
    this.serviceEndedAt,
    this.totalHours,
    this.totalAmount,
    this.customerRating,
    this.customerComment,
    this.providerRatingOfCustomer,
    this.providerCommentOfCustomer,
    this.cancelledAt,
    this.cancellationFee,
    this.refundAmount,
    this.providerName,
    this.providersNotified,
    this.askedNames = const [],
    this.chosenByCustomer = false,
    this.unavailableCount = 0,
    this.unreadMessages = 0,
    this.forName,
    this.forRelationship,
    this.forContactNumber,
  });
}


/// The cancellation fee tiers from the requirements doc, in one place:
/// under 24 hours before the start there is no refund; between 24 and 36
/// hours half the booking charge is kept; earlier than that it is refunded
/// in full.
CancellationQuote defaultCancellationQuote(Booking b) {
  final parts = b.timeFrom.split(':');
  final start = DateTime(
    b.startDate.year,
    b.startDate.month,
    b.startDate.day,
    int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0,
    int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
  );
  final hours = start.difference(DateTime.now()).inMinutes / 60.0;
  final paid = b.bookingChargePaid ? b.bookingCharge : 0.0;

  if (hours < 24) {
    return CancellationQuote(
      hoursBeforeStart: hours,
      feeAmount: paid,
      refundAmount: 0,
      rule: 'Cancelled less than 24 hours before the service start \u2014 no refund.',
    );
  }
  if (hours < 36) {
    final fee = paid * 0.5;
    return CancellationQuote(
      hoursBeforeStart: hours,
      feeAmount: fee,
      refundAmount: paid - fee,
      rule: 'Cancelled 24\u201336 hours before the service start \u2014 50% cancellation fee.',
    );
  }
  return CancellationQuote(
    hoursBeforeStart: hours,
    feeAmount: 0,
    refundAmount: paid,
    rule: 'Cancelled more than 36 hours before the service start \u2014 full refund.',
  );
}
