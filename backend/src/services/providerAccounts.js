/**
 * Creating a service-provider account.
 *
 * Three callers need to put a row in `service_providers`, with its addresses,
 * work hours and expertise written alongside it in the same transaction:
 *
 *   1. a provider registering on their own phone  - authController.providerRegister
 *   2. an organisation adding one of its carers   - providerSelfController.addEmployee
 *   3. the office creating an account for somebody - adminController.createProvider
 *
 * All three were written separately, and the differences between them were not
 * decisions, they were omissions. `providerRegister` never wrote the police
 * verification's validity dates although the app sends them, so the app has to
 * follow its own registration call with a PUT to /providers/me to put them
 * back; `addEmployee` did write them. Neither wrote `no_fees`. Whichever of the
 * three a new column was added to, the other two went on storing NULL.
 *
 * The expensive version of that bug is already in this project's history. An
 * organisation that named no working days got no `service_provider_work_hours`
 * rows; the matching query INNER JOINs that table; so the agency was invisible
 * to every search while the console showed it as approved, with nothing on any
 * screen to say why. One caller was fixed. The others would have had to be
 * found and fixed again.
 *
 * So the INSERT lives here, once, and takes the full column set.
 *
 * What is deliberately NOT here is how strictly a caller's input is checked.
 * That differs between the three for a real reason: a stranger's phone is not
 * an administrator, and an APK already installed on somebody's handset cannot
 * be made to send a field it was never built to send. The predicates each
 * caller may want are exported below so the rules are written once; which of
 * them to enforce is the caller's decision.
 */
import bcrypt from 'bcryptjs';

import { withTransaction } from '../db/pool.js';
import { Errors } from '../utils/apiError.js';
import { displayId } from '../utils/ids.js';
import { normaliseGender } from '../utils/enums.js';

// ---------------------------------------------------------------------
// The values the columns accept
// ---------------------------------------------------------------------

export const PROVIDER_KINDS = ['freelancer', 'organization', 'org_employee'];
export const SERVICE_TYPES = ['companion', 'medical_companion', 'nurse', 'physiotherapy'];
export const DAYS_OF_WEEK = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];

/**
 * The services a medical certificate is required for.
 *
 * A companion sits with somebody; a nurse puts a needle in them. The
 * registration form has always drawn that line, and anything creating an
 * account has to draw it in the same place or the console becomes the way
 * round it.
 */
export const CLINICAL_SERVICES = ['nurse', 'physiotherapy'];

// ---------------------------------------------------------------------
// Predicates - the same rules the registration form applies on the phone
// ---------------------------------------------------------------------

/** Indian mobile numbers are ten digits and start 6-9. */
export const MOBILE_RE = /^[6-9]\d{9}$/;

/**
 * Deliberately loose. The job here is to catch a typo, not to decide which
 * addresses exist - every stricter pattern anybody writes rejects somebody's
 * real address, and this field is optional anyway.
 */
export const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

/** 15 characters: 2 state digits, 10-character PAN, entity digit, Z, checksum. */
export const GST_RE = /^\d{2}[A-Z]{5}\d{4}[A-Z]\d[Z][A-Z\d]$/;

/** What the rate field will accept, in rupees per hour. */
export const HOURLY_RATE_MIN = 50;
export const HOURLY_RATE_MAX = 5000;

/** Nobody outside this age range may be registered as a carer. */
export const MIN_CARER_AGE_YEARS = 18;
export const MAX_CARER_AGE_YEARS = 80;

/**
 * Why a PIN is refused, or null when it is acceptable.
 *
 * Returns the sentence rather than throwing, because one caller wants it as a
 * field error next to the input and another wants it as a 422. The three rules
 * are the ones the provider app's own PIN step applies, and they are here so
 * the console cannot quietly be the softer door: an account created in the
 * office with the PIN 111111 is as easy to walk into as one created on a phone
 * with it.
 */
export function pinRefusal(pin) {
  const value = String(pin ?? '').trim();
  if (!/^\d{6}$/.test(value)) return 'The PIN must be exactly 6 digits.';
  if (/^(\d)\1{5}$/.test(value)) return 'Choose a PIN that is not the same digit six times.';
  if (value === '123456' || value === '654321') return 'That PIN is too easy to guess.';
  return null;
}

/** bcrypt cost 10, matching every other password and PIN in this codebase. */
export async function hashPin(pin) {
  return bcrypt.hash(String(pin), 10);
}

/**
 * Age in years at today's date, or null when no date of birth was given.
 *
 * Date of birth is optional - it was made optional because requiring it cost
 * registrations - so "no date" and "an impossible date" are different answers
 * and only the second one is a problem.
 */
export function ageInYears(dob) {
  if (!dob) return null;
  const born = new Date(dob);
  if (Number.isNaN(born.getTime())) return null;
  return (Date.now() - born.getTime()) / (365.25 * 24 * 60 * 60 * 1000);
}

/** True when `to` is strictly later than `from`, both "HH:mm" or "HH:mm:ss". */
export function isAfterTime(to, from) {
  const minutes = (hhmm) => {
    const [h, m] = String(hhmm).split(':');
    return Number(h) * 60 + Number(m);
  };
  return minutes(to) > minutes(from);
}

// ---------------------------------------------------------------------
// Normalising the child rows
// ---------------------------------------------------------------------

/**
 * Work hours, with the all-week default an organisation needs.
 *
 * An organisation that names no days still has to be findable. The matching
 * query INNER JOINs `service_provider_work_hours`, so a provider with no rows
 * matches nothing, ever - an agency that skipped the (optional) "days the
 * organisation operates" question would register successfully, appear in the
 * console as approved, and never be offered a single booking.
 *
 * An agency covers whatever hours the carer it sends covers, so the honest
 * default is all seven days. Each carer's own days are collected when that
 * carer is added, and those are what a family is really matched against.
 *
 * A freelancer gets no such default: their hours are a real constraint that
 * somebody has to have stated, and inventing 00:00-23:59 for a person would
 * offer them 3 a.m. bookings they never agreed to.
 */
export function normaliseWorkHours(workHours, { providerKind }) {
  const given = Array.isArray(workHours) ? workHours : [];
  const rows = given
    .map((w) => ({
      dayOfWeek: String(w.dayOfWeek ?? '').toLowerCase(),
      startTime: w.startTime ?? '09:00',
      endTime: w.endTime ?? '18:00',
    }))
    .filter((w) => DAYS_OF_WEEK.includes(w.dayOfWeek));

  if (rows.length === 0 && providerKind === 'organization') {
    return DAYS_OF_WEEK.map((dayOfWeek) => ({ dayOfWeek, startTime: '00:00', endTime: '23:59' }));
  }

  // One row per day: the table has a UNIQUE KEY on (provider_id, day_of_week),
  // so a payload naming Monday twice would abort the whole transaction on the
  // second INSERT and lose the account rather than the duplicate.
  const seen = new Set();
  return rows.filter((w) => (seen.has(w.dayOfWeek) ? false : seen.add(w.dayOfWeek)));
}

/**
 * Expertise rows, accepting either `['nurse']` or `[{serviceType:'nurse'}]`.
 *
 * Both shapes are already in use by existing callers; rejecting one of them now
 * would break a client that works today.
 */
export function normaliseExpertise(expertise) {
  const given = Array.isArray(expertise) ? expertise : [];
  const rows = given
    .map((e) => (typeof e === 'string'
      ? { serviceType: e, yearsExperience: null, notes: null }
      : {
        serviceType: String(e.serviceType ?? ''),
        yearsExperience: e.yearsExperience ?? null,
        notes: e.notes ?? null,
      }))
    .filter((e) => SERVICE_TYPES.includes(e.serviceType));

  // UNIQUE KEY (provider_id, service_type), same reasoning as the days above.
  const seen = new Set();
  return rows.filter((e) => (seen.has(e.serviceType) ? false : seen.add(e.serviceType)));
}

/**
 * Addresses, accepting a bare string as well as the object the apps send.
 *
 * A string is the obvious thing for anything else to send, and taking only the
 * object meant a string passed the truthiness check, `line1` came out
 * undefined, and the INSERT died on a NOT NULL column - a 500 where a sentence
 * belongs.
 */
export function normaliseAddresses(addresses) {
  const given = Array.isArray(addresses) ? addresses : addresses ? [addresses] : [];
  return given
    .map((a) => (typeof a === 'string' ? { line1: a.trim() } : a))
    .filter((a) => a && typeof a === 'object' && String(a.line1 ?? '').trim())
    .map((a) => ({
      addressType: a.addressType === 'office' ? 'office' : 'home',
      line1: String(a.line1).trim(),
      line2: a.line2 || null,
      city: a.city || null,
      state: a.state || null,
      pincode: a.pincode || null,
      latitude: a.latitude ?? null,
      longitude: a.longitude ?? null,
    }));
}

// ---------------------------------------------------------------------
// The write
// ---------------------------------------------------------------------

/**
 * Insert one provider and its child rows on an existing connection.
 *
 * Every column the three callers between them need is a named parameter with a
 * null default, so adding a column means touching this function and nothing
 * else. The caller is responsible for having validated its own input; this
 * function's job is that whatever was decided actually reaches the database.
 *
 * `display_id` is written in a second statement because it is derived from the
 * auto-increment id, which does not exist until the INSERT has run. Both
 * statements are inside the caller's transaction, so no row with the literal
 * 'PENDING' is ever visible to anybody.
 */
export async function insertProviderAccount(conn, spec) {
  const {
    providerKind,
    organizationId = null,
    name,
    photoUrl = null,
    gender = null,
    dob = null,
    mobile,
    email = null,
    pinHash = null,
    hourlyRate = 0,
    noFees = false,
    aadharDocUrl = null,
    policeVerificationUrl = null,
    policeVerificationValidFrom = null,
    policeVerificationValidTo = null,
    medicalCertificateUrl = null,
    medicalCertificateValidFrom = null,
    medicalCertificateValidTo = null,
    workCertificateUrl = null,
    orgRegistrationUrl = null,
    gstNumber = null,
    contactPerson = null,
    allocateViaOrg = false,
    distanceFromHomePrefKm = null,
    distanceFromOfficePrefKm = null,
    languages = null,
    deviceId = null,
    approvalStatus = 'pending',
    approvalNotes = null,
    approvedBy = null,
    registrationFeePaid = false,
    addresses = [],
    workHours = [],
    expertise = [],
  } = spec;

  if (!PROVIDER_KINDS.includes(providerKind)) {
    throw Errors.badRequest('VALIDATION', `providerKind must be one of: ${PROVIDER_KINDS.join(', ')}`);
  }

  // `approved_at` is a timestamp, not a value a caller supplies: it answers
  // "when did somebody at Sathiyaa decide this", so it is set here if and only
  // if an administrator is named as having decided it.
  const approvedAtSql = approvedBy === null ? 'NULL' : 'NOW()';

  const [result] = await conn.query(
    `INSERT INTO service_providers
      (display_id, provider_kind, organization_id, name, photo_url, gender, dob,
       mobile_number, email, pin_hash, hourly_rate, no_fees,
       aadhar_doc_url, police_verification_url, police_verification_valid_from,
       police_verification_valid_to, medical_certificate_url,
       medical_certificate_valid_from, medical_certificate_valid_to,
       work_certificate_url, org_registration_url, gst_number, contact_person,
       allocate_via_org, distance_from_home_pref_km, distance_from_office_pref_km,
       languages, device_id, approval_status, approval_notes, approved_by,
       approved_at, registration_fee_paid)
     VALUES ('PENDING', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
             ?, ?, ?, ?, ?, ?, ?, ?, ${approvedAtSql}, ?)`,
    [
      providerKind,
      organizationId,
      name,
      photoUrl,
      // An organisation has no gender. normaliseGender tolerates an empty
      // string for exactly this reason rather than defaulting a company to
      // 'female', which an earlier version of the registration path did.
      normaliseGender(gender),
      dob || null,
      mobile,
      email,
      pinHash,
      noFees ? 0 : hourlyRate || 0,
      noFees ? 1 : 0,
      aadharDocUrl,
      policeVerificationUrl,
      policeVerificationValidFrom || null,
      policeVerificationValidTo || null,
      medicalCertificateUrl,
      medicalCertificateValidFrom || null,
      medicalCertificateValidTo || null,
      workCertificateUrl,
      orgRegistrationUrl,
      gstNumber,
      contactPerson,
      allocateViaOrg ? 1 : 0,
      distanceFromHomePrefKm,
      distanceFromOfficePrefKm,
      // JSON_CONTAINS against NULL matches nothing, which makes a carer
      // invisible to every language search rather than only the wrong ones. A
      // caller that knows no languages should still send one.
      Array.isArray(languages) && languages.length ? JSON.stringify(languages) : null,
      // Binds the account to the handset it was created on, when there is one.
      // Null leaves it unbound and the first PIN login claims it - which is
      // what an account created in the office needs, or it would be bound to a
      // device the provider does not own.
      deviceId,
      approvalStatus,
      approvalNotes,
      approvedBy,
      registrationFeePaid ? 1 : 0,
    ]
  );

  const providerId = result.insertId;
  await conn.query('UPDATE service_providers SET display_id = ? WHERE provider_id = ?', [
    displayId('SP', providerId), providerId,
  ]);

  for (const a of addresses) {
    await conn.query(
      `INSERT INTO service_provider_addresses
         (provider_id, address_type, line1, line2, city, state, pincode, latitude, longitude)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [providerId, a.addressType, a.line1, a.line2, a.city, a.state, a.pincode, a.latitude, a.longitude]
    );
  }

  for (const w of workHours) {
    await conn.query(
      'INSERT INTO service_provider_work_hours (provider_id, day_of_week, start_time, end_time) VALUES (?, ?, ?, ?)',
      [providerId, w.dayOfWeek, w.startTime, w.endTime]
    );
  }

  for (const e of expertise) {
    await conn.query(
      'INSERT INTO service_provider_expertise (provider_id, service_type, years_experience, notes) VALUES (?, ?, ?, ?)',
      [providerId, e.serviceType, e.yearsExperience, e.notes]
    );
  }

  const [rows] = await conn.query('SELECT * FROM service_providers WHERE provider_id = ?', [providerId]);
  return rows[0];
}

/**
 * The same thing, in a transaction of its own.
 *
 * Use this unless the caller already has one open. Half a provider is worse
 * than none: a row with no expertise and no work hours is an account that can
 * sign in, looks complete in the console, and can never be offered a booking.
 */
export async function createProviderAccount(spec) {
  return withTransaction((conn) => insertProviderAccount(conn, spec));
}
