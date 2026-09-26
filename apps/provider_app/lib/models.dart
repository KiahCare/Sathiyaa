// Data models for the Sathiyaa Provider app.

import 'city_defaults.dart';
import 'languages.dart';
import 'i18n/l10n.dart';

enum ServiceType { companion, medicalCompanion, nurse, physiotherapy }

extension ServiceTypeLabel on ServiceType {
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

enum ProviderKind { freelancer, organization, orgEmployee }

enum BookingStatus { requested, accepted, inProgress, completed, cancelled }

/// What a provider should read on a card. `.name` gave "inProgress", which is
/// a variable name, not something to put in front of a carer.
extension BookingStatusLabel on BookingStatus {
  String get label => switch (this) {
        BookingStatus.requested => t('New request'),
        BookingStatus.accepted => t('Accepted'),
        BookingStatus.inProgress => t('In progress'),
        BookingStatus.completed => t('Completed'),
        BookingStatus.cancelled => t('Cancelled'),
      };
}

enum EmployeeStatus { active, blocked }

extension EmployeeStatusLabel on EmployeeStatus {
  String get label => this == EmployeeStatus.active ? t('Active') : t('Blocked');
}

enum PaymentStatus { unpaid, partial, paid }

/// The hours worked on one day.
class DayHours {
  final String from; // "HH:mm"
  final String to;
  const DayHours(this.from, this.to);

  @override
  bool operator ==(Object other) =>
      other is DayHours && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// Which days somebody works, and between what times.
///
/// [timeFrom]/[timeTo] are the usual window, and [perDay] holds the days that
/// differ from it. Two reasons it is shaped that way rather than as a map of
/// seven entries: most carers work the same hours every day and should only
/// have to say so once, and the rest of the app already reads timeFrom and
/// timeTo to work out a day's capacity.
///
/// The backend has always stored start and end times PER DAY
/// (service_provider_work_hours has a row per day_of_week), so this loses
/// nothing on the way out. Registration used to send a hardcoded 09:00-18:00
/// for every day a carer ticked, whatever hours they actually keep -- there
/// was nowhere on the form to say.
class WorkPreference {
  List<String> days; // Mon..Sun
  String timeFrom;
  String timeTo;
  Map<String, DayHours> perDay;

  WorkPreference({
    List<String>? days,
    this.timeFrom = '09:00',
    this.timeTo = '18:00',
    Map<String, DayHours>? perDay,
  })  : days = days ?? ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
        perDay = perDay ?? {};

  /// The hours for [day], falling back to the usual window.
  DayHours hoursFor(String day) => perDay[day] ?? DayHours(timeFrom, timeTo);

  /// True when at least one day departs from the usual window.
  bool get hasExceptions =>
      perDay.entries.any((e) => days.contains(e.key) && e.value != DayHours(timeFrom, timeTo));
}

class ProviderDocument {
  String? url; // simulated
  DateTime? validFrom;
  DateTime? validTo;
  ProviderDocument({this.url, this.validFrom, this.validTo});
  bool get uploaded => url != null;
}

/// Somebody who works for an organisation.
///
/// Carries the same documents as a freelance carer, and for the same reason:
/// a family letting somebody into their home is trusting that this person was
/// checked, and it makes no difference to them whether that person applied
/// directly or was added by an agency. Before this, an organisation could add
/// a carer with a name and a phone number and nothing else, and that carer
/// could be sent to a booking -- the verification the whole product promises
/// applied to freelancers only.
class Employee {
  final String id;
  String name;
  String gender;
  String mobile;
  DateTime? dob;

  /// Where this carer lives. Used to work out how far they are from a
  /// booking, which is separate from the organisation's own office address.
  String address;

  /// The pin for that address. Without coordinates the allocation query has
  /// no distance to measure, so a carer typed in with only a street name was
  /// never matched to anything nearby — the organisation's own office pin was
  /// used, wherever its carers actually live.
  double? lat;
  double? lng;

  WorkPreference workPref;
  List<ServiceType> expertise;

  /// What this carer speaks.
  ///
  /// A family filters on it and reads it off the card before choosing, so an
  /// organisation adding somebody has to say — the alternative is an agency's
  /// staff all silently claiming English.
  List<String> languages;
  double? distanceFromHomeKm;
  double? distanceFromOfficeKm;
  EmployeeStatus status;

  /// What Sathiyaa has decided about this carer: pending, approved, hold or
  /// rejected. An organisation adding somebody is not the same as that person
  /// being checked, and the staff screen has to be able to say which.
  String approvalStatus;

  ProviderDocument aadhar;
  ProviderDocument policeVerification;
  ProviderDocument medicalCertificate;

  Employee({
    required this.id,
    required this.name,
    required this.gender,
    required this.mobile,
    required this.address,
    this.lat,
    this.lng,
    this.dob,
    this.approvalStatus = 'pending',
    WorkPreference? workPref,
    List<ServiceType>? expertise,
    List<String>? languages,
    this.distanceFromHomeKm,
    this.distanceFromOfficeKm,
    this.status = EmployeeStatus.active,
    ProviderDocument? aadhar,
    ProviderDocument? policeVerification,
    ProviderDocument? medicalCertificate,
  })  : workPref = workPref ?? WorkPreference(),
        expertise = expertise ?? [ServiceType.companion],
        languages = languages ?? List<String>.from(kDefaultLanguages),
        aadhar = aadhar ?? ProviderDocument(),
        policeVerification = policeVerification ?? ProviderDocument(),
        medicalCertificate = medicalCertificate ?? ProviderDocument();

  /// Whether Sathiyaa has checked this carer and said yes.
  bool get verified => approvalStatus == 'approved';

  /// Whether the organisation has given Sathiyaa enough to review. Separate
  /// from [verified] on purpose: "we have not sent the police check" is the
  /// organisation's to fix and "Sathiyaa has not looked yet" is not, and the
  /// staff screen showed both as the same grey Pending.
  bool get documentsComplete =>
      aadhar.uploaded &&
      policeVerification.uploaded &&
      policeVerification.validTo != null &&
      policeVerification.validTo!.isAfter(DateTime.now());
}

class ProviderProfile {
  String id; // e.g. PROV-000042
  ProviderKind kind;
  String name; // person or org name
  String? photoUrl;
  String gender;
  DateTime? dob;
  String mobile;
  String? email;
  String address;
  double lat;
  double lng;
  WorkPreference workPref;
  List<ServiceType> expertise;

  /// What this carer speaks. Stored as the display name, because that is what
  /// the search filter matches on: JSON_CONTAINS(languages, '"Gujarati"').
  List<String> languages;

  /// Whether they have ever answered the language question, as opposed to
  /// sitting on the English-only default nobody chose. The picker is not on
  /// the registration form any more, so the profile screen asks -- and needs
  /// to know when to stop.
  bool languagesConfirmed;
  double? hourlyRate;
  bool noFees;
  ProviderDocument aadhar;
  ProviderDocument policeVerification;
  ProviderDocument medicalCertificate;
  ProviderDocument workCertificate;

  // ---- organisations only ----------------------------------------------
  //
  // An organisation is not a carer with a company name. Nobody runs a police
  // check on a company, and an Aadhaar card does not belong to one: what
  // verifies an agency is its registration, and what verifies the people it
  // sends is each carer's own paperwork, collected when that carer is added.
  // These three fields are what the org registration path collects instead.

  /// Certificate of incorporation, shops-and-establishment licence, society
  /// or trust registration -- whatever this organisation is registered as.
  ProviderDocument registrationCertificate;

  /// Optional. Organisations below the threshold do not have one.
  String? gstNumber;

  /// The person Sathiyaa talks to. An organisation has no date of birth and
  /// no gender, but it does have somebody who answers the phone.
  String? contactPerson;

  String? pin;
  bool approved;
  String approvalStatus; // pending | active | hold | blocked
  double ratingAvg;
  int ratingCount;
  bool allocateViaOrg; // org: route requests to org instead of showing employees
  /// Requests can only be accepted while location sharing is on — the spec
  /// makes this an explicit precondition, not a nicety.
  bool locationOn;
  double? currentLat;
  double? currentLng;

  /// Where this account registered from, and what the server made of it.
  /// Null means never asked -- everybody who signed up before the
  /// service-area gate existed, and anybody who refused the prompt.
  String? signupCity;
  bool? signupInServiceArea;
  List<Employee> employees;
  double? orgServiceFeeOverride;

  ProviderProfile({
    required this.id,
    required this.kind,
    required this.name,
    this.photoUrl,
    required this.gender,
    this.dob,
    required this.mobile,
    this.email,
    required this.address,
    required this.lat,
    required this.lng,
    WorkPreference? workPref,
    List<ServiceType>? expertise,
    List<String>? languages,
    this.hourlyRate,
    this.noFees = false,
    ProviderDocument? aadhar,
    ProviderDocument? policeVerification,
    ProviderDocument? medicalCertificate,
    ProviderDocument? workCertificate,
    ProviderDocument? registrationCertificate,
    this.gstNumber,
    this.contactPerson,
    this.pin,
    this.approved = true,
    this.approvalStatus = 'active',
    this.ratingAvg = 4.5,
    this.ratingCount = 10,
    this.allocateViaOrg = false,
    this.locationOn = false,
    this.languagesConfirmed = false,
    this.signupCity,
    this.signupInServiceArea,
    this.currentLat,
    this.currentLng,
    List<Employee>? employees,
    this.orgServiceFeeOverride,
  })  : workPref = workPref ?? WorkPreference(),
        expertise = expertise ?? [],
        languages = languages ?? List<String>.from(kDefaultLanguages),
        aadhar = aadhar ?? ProviderDocument(),
        policeVerification = policeVerification ?? ProviderDocument(),
        medicalCertificate = medicalCertificate ?? ProviderDocument(),
        workCertificate = workCertificate ?? ProviderDocument(),
        registrationCertificate = registrationCertificate ?? ProviderDocument(),
        employees = employees ?? [];

  /// True when this account is an agency rather than one carer. Read in
  /// enough places -- the dashboard, the registration form, the profile --
  /// that `kind == ProviderKind.organization` written out each time was
  /// asking for one of them to be missed.
  bool get isOrganisation => kind == ProviderKind.organization;
}

/// Outcome of the pre-service face + location check.
class FaceCheckResult {
  final bool passed;
  final double? distanceKm;
  final String message;
  const FaceCheckResult({required this.passed, this.distanceKm, required this.message});
}

/// Dashboard figures for one period, per the spec's Today / Week / Month /
/// Quarter / Annual selector.
class DashboardStats {
  final int appointments;
  final double revenue;
  final double pending;
  final double hours;
  const DashboardStats({
    required this.appointments,
    required this.revenue,
    required this.pending,
    required this.hours,
  });
}

/// A stretch of time the provider has marked unavailable. Blocked time is
/// excluded from customer search, so it is the provider's way of taking a few
/// hours or a few days off without cancelling anything.
class CalendarBlock {
  final String id;
  DateTime from;
  DateTime to;
  String reason;
  CalendarBlock({required this.id, required this.from, required this.to, this.reason = ''});

  bool covers(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final f = DateTime(from.year, from.month, from.day);
    final t = DateTime(to.year, to.month, to.day);
    return !d.isBefore(f) && !d.isAfter(t);
  }
}

class TimeBankEntry {
  final String id;
  DateTime date;
  ServiceType serviceType;
  double hours;
  double points;
  TimeBankEntry({required this.id, required this.date, required this.serviceType, required this.hours, required this.points});
}


/// One line in a booking's conversation.
///
/// The same shape as the customer app's, because it is the same thread read
/// from the other end. `system` is the app's own note — "visit started",
/// "running late" — written in so the history reads as one sequence.
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

class ProviderBooking {
  final String id;
  final String customerId;
  final String customerName;
  String providerId;
  String? assignedEmployeeId;
  ServiceType serviceType;
  DateTime startDate;
  DateTime endDate;
  String timeFrom;
  String timeTo;
  String customerAddress;

  /// How to reach the customer. Only populated once this provider has the
  /// booking -- a pending request deliberately carries no phone number, since
  /// one request fans out to every matching provider.
  String? customerMobile;

  /// Worth knowing before you knock: a blood group for a nurse, and how the
  /// customer prefers to be contacted.
  String? customerBloodGroup;
  String? customerCommMode;
  String? customerCommTimeframe;
  double customerLat;
  double customerLng;
  BookingStatus status;
  String? otp;
  /// Stamped once the face-match + geofence check passes; the start OTP is
  /// only issued to the customer after this.
  DateTime? faceVerifiedAt;
  String? runningLateEta;
  DateTime? serviceStartedAt;
  DateTime? serviceEndedAt;
  double? totalHours;
  double amountDue;
  double amountReceived;
  PaymentStatus paymentStatus;
  DateTime? paymentReminderSentAt;
  bool runningLateSent;
  double? customerRatingByProvider;
  String? customerCommentByProvider;

  /// Who the visit is actually for, when that is not the person who booked it.
  ///
  /// The commonest case this app serves is an adult child in another city
  /// arranging care for a parent: they hold the account, they pay, and the
  /// carer is visiting somebody else. Null means the two are the same person.
  final String? forName;
  final String? forRelationship;
  final String? forContactNumber;
  final DateTime? forDateOfBirth;
  final String? forNotes;

  /// Messages from the family that have not been opened yet.
  int unreadMessages;

  /// The name to knock and ask for.
  String get visitingName => forName ?? customerName;

  /// True when the person being visited is not the person who booked.
  bool get isForSomeoneElse => forName != null && forName!.trim().isNotEmpty;

  ProviderBooking({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.providerId,
    this.assignedEmployeeId,
    required this.serviceType,
    required this.startDate,
    required this.endDate,
    required this.timeFrom,
    required this.timeTo,
    this.customerAddress = '',
    this.customerMobile,
    this.customerBloodGroup,
    this.customerCommMode,
    this.customerCommTimeframe,
    this.customerLat = kDefaultLat,
    this.customerLng = kDefaultLng,
    this.unreadMessages = 0,
    this.forName,
    this.forRelationship,
    this.forContactNumber,
    this.forDateOfBirth,
    this.forNotes,
    this.status = BookingStatus.requested,
    this.otp,
    this.faceVerifiedAt,
    this.runningLateEta,
    this.serviceStartedAt,
    this.serviceEndedAt,
    this.totalHours,
    this.amountDue = 0,
    this.amountReceived = 0,
    this.paymentStatus = PaymentStatus.unpaid,
    this.paymentReminderSentAt,
    this.runningLateSent = false,
    this.customerRatingByProvider,
    this.customerCommentByProvider,
  });
}
