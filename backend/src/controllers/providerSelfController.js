import bcrypt from 'bcryptjs';
import { query, withTransaction } from '../db/pool.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { Errors } from '../utils/apiError.js';
import { displayId } from '../utils/ids.js';
import { generateOtp } from '../utils/otp.js';
import { haversineKm } from '../utils/haversine.js';
import { verifyFace } from '../integrations/faceMatch.js';
import * as push from '../integrations/push.js';
import { getDirections } from '../integrations/maps.js';
import { createOrder, verifyPayment } from '../integrations/payment.js';
import { recordSignupPlace } from '../services/serviceArea.js';
import { registrationStanding, transactionTypeFor } from '../services/registrationFee.js';
import { computeRevenueSplit } from '../services/revenueSharing.js';
import { writeAuditLog } from '../middleware/audit.js';
import { env } from '../config/env.js';
import { creditTimeBank, computeOrgBilling, getTimeBankSummary } from '../services/pricing.js';
import { computeCancellation, hoursUntilStart } from '../services/cancellationPolicy.js';
import { normaliseGender } from '../utils/enums.js';
import { localToday } from '../utils/dates.js';
import { unreadCounts, systemNote } from '../services/messageService.js';

const provId = (req) => req.user.id;

async function loadOwnProvider(req) {
  const [provider] = await query('SELECT * FROM service_providers WHERE provider_id = ?', [provId(req)]);
  if (!provider) throw Errors.notFound('Provider not found');
  return provider;
}

// Matches on confirmed_provider_id (the freelancer, or the organization
// itself before it allocates the request) OR assigned_employee_id (the
// org_employee actually performing the service once the org has
// allocated it) — see requirement "Allocate Employee" routing.
async function loadBookingForProvider(bookingId, providerId) {
  const [booking] = await query(
    `SELECT b.*,
            f.name           AS for_name,
            f.relationship   AS for_relationship,
            f.contact_number AS for_contact_number,
            f.date_of_birth  AS for_date_of_birth,
            f.notes          AS for_notes
       FROM bookings b
       LEFT JOIN customer_family_members f ON f.id = b.for_family_member_id
      WHERE b.booking_id = ? AND (b.confirmed_provider_id = ? OR b.assigned_employee_id = ?)`,
    [bookingId, providerId, providerId]
  );
  if (!booking) throw Errors.notFound('Booking not found for this provider');
  return booking;
}

// ---------------------------------------------------------------------
// PROFILE
// ---------------------------------------------------------------------

export const getMe = asyncHandler(async (req, res) => {
  const provider = await loadOwnProvider(req);
  const addresses = await query('SELECT * FROM service_provider_addresses WHERE provider_id = ?', [provId(req)]);
  const workHours = await query('SELECT * FROM service_provider_work_hours WHERE provider_id = ?', [provId(req)]);
  const expertise = await query('SELECT * FROM service_provider_expertise WHERE provider_id = ?', [provId(req)]);
  res.json({ ...serializeProvider(provider), addresses, workHours, expertise });
});

function serializeProvider(p) {
  return {
    providerId: p.provider_id,
    displayId: p.display_id,
    providerKind: p.provider_kind,
    organizationId: p.organization_id,
    name: p.name,
    photoUrl: p.photo_url,
    gender: p.gender,
    dob: p.dob,
    mobileNumber: p.mobile_number,
    email: p.email,
    hourlyRate: p.hourly_rate,
    noFees: !!p.no_fees,
    aadharDocUrl: p.aadhar_doc_url,
    workCertificateUrl: p.work_certificate_url,
    policeVerificationUrl: p.police_verification_url,
    policeVerificationValidFrom: p.police_verification_valid_from,
    policeVerificationValidTo: p.police_verification_valid_to,
    medicalCertificateUrl: p.medical_certificate_url,
    medicalCertificateValidFrom: p.medical_certificate_valid_from,
    medicalCertificateValidTo: p.medical_certificate_valid_to,
    allocateViaOrg: !!p.allocate_via_org,
    // Organisations only; null for a freelancer.
    orgRegistrationUrl: p.org_registration_url,
    gstNumber: p.gst_number,
    contactPerson: p.contact_person,
    languages: p.languages,
    approvalStatus: p.approval_status,
    status: p.status,
    registrationFeePaid: !!p.registration_fee_paid,
    // Where they registered from, so the service-area gate does not have to
    // ask the phone again on every launch.
    signupCity: p.signup_city,
    signupState: p.signup_state,
    signupInServiceArea:
      p.signup_in_service_area === null || p.signup_in_service_area === undefined
        ? null
        : !!p.signup_in_service_area,
    // Whether they have answered the language question at all, so the profile
    // screen knows when to stop asking.
    languagesConfirmed: !!p.languages_confirmed_at,
    locationOn: !!p.location_on,
    currentLatitude: p.current_latitude,
    currentLongitude: p.current_longitude,
    distanceFromHomePrefKm: p.distance_from_home_pref_km,
    distanceFromOfficePrefKm: p.distance_from_office_pref_km,
    ratingAvg: p.rating_avg,
    ratingCount: p.rating_count,
  };
}

export const updateMe = asyncHandler(async (req, res) => {
  const b = req.body;
  const fields = [];
  const values = [];
  const map = {
    name: 'name', photoUrl: 'photo_url', gender: 'gender', dob: 'dob', email: 'email',
    hourlyRate: 'hourly_rate', distanceFromHomePrefKm: 'distance_from_home_pref_km',
    distanceFromOfficePrefKm: 'distance_from_office_pref_km', locationOn: 'location_on',
    noFees: 'no_fees',
    aadharDocUrl: 'aadhar_doc_url',
    workCertificateUrl: 'work_certificate_url',
    policeVerificationUrl: 'police_verification_url',
    policeVerificationValidFrom: 'police_verification_valid_from',
    policeVerificationValidTo: 'police_verification_valid_to',
    medicalCertificateUrl: 'medical_certificate_url',
    medicalCertificateValidFrom: 'medical_certificate_valid_from',
    medicalCertificateValidTo: 'medical_certificate_valid_to',
    allocateViaOrg: 'allocate_via_org',
    orgRegistrationUrl: 'org_registration_url',
    gstNumber: 'gst_number',
    contactPerson: 'contact_person',
  };
  // Checked before the UPDATE, or an unknown value makes MySQL reject the
  // whole statement and the app shows "Something went wrong".
  if (b.gender !== undefined) b.gender = normaliseGender(b.gender);

  for (const [k, col] of Object.entries(map)) {
    if (b[k] !== undefined) { fields.push(`${col} = ?`); values.push(b[k]); }
  }
  if (b.languages !== undefined) {
    fields.push('languages = ?');
    values.push(JSON.stringify(b.languages));
    // Saving them is the answer, whatever the answer is. Somebody who speaks
    // only English picks English and saves; without this the list is
    // identical to the untouched default and the profile screen would keep
    // asking them the same question.
    fields.push('languages_confirmed_at = NOW()');
  }
  if (fields.length === 0) throw Errors.badRequest('VALIDATION', 'No updatable fields provided');

  values.push(provId(req));
  await query(`UPDATE service_providers SET ${fields.join(', ')} WHERE provider_id = ?`, values);
  await req.audit('ProviderUpdateProfile', 'UPDATE');
  const provider = await loadOwnProvider(req);
  res.json(serializeProvider(provider));
});

export const registrationPayment = asyncHandler(async (req, res) => {
  const provider = await loadOwnProvider(req);
  const standing = await registrationStanding({
    kind: 'provider',
    referenceId: provider.provider_id,
    alreadyPaid: !!provider.registration_fee_paid,
  });
  if (!standing.canPay) {
    throw Errors.conflict(
      'ALREADY_PAID',
      standing.renewsAt
        ? `Already paid. The next renewal is due on ${standing.renewsAt.toISOString().slice(0, 10)}.`
        : 'Registration fee already paid.'
    );
  }

  const { amount, isRenewal } = standing;
  const txnType = transactionTypeFor('provider', isRenewal);

  // Zero is a price, and the gateway cannot charge it: Razorpay's minimum
  // order is one rupee, so setting the fee to 0 in the console used to make
  // registration fail rather than free. Waive it, write the ledger row so
  // there is no gap, and tell the app there is nothing to pay.
  if (!(amount > 0)) {
    const waived = await query(
      `INSERT INTO transactions (transaction_type, reference_type, reference_id, amount, gateway, gateway_ref_id, status)
       VALUES (?, 'provider', ?, 0, 'waived', NULL, 'success')`,
      [txnType, provider.provider_id]
    );
    await query('UPDATE service_providers SET registration_fee_paid = TRUE, registration_txn_id = ? WHERE provider_id = ?', [
      waived.insertId, provider.provider_id,
    ]);
    await req.audit('ProviderRegistrationPayment', 'PAYMENT', { amount: 0, waived: true });
    return res.json({
      paid: true, amount: 0, waived: true, transactionId: waived.insertId,
      message: 'No fee is being charged. Your account activates once an admin approves your profile.',
    });
  }

  const order = await createOrder({ amount, receipt: `provreg_${provider.provider_id}` });
  const verification = await verifyPayment({ orderId: order.orderId, paymentRef: req.body.paymentRef });

  const txn = await query(
    `INSERT INTO transactions (transaction_type, reference_type, reference_id, amount, gateway, gateway_ref_id, status)
     VALUES (?, 'provider', ?, ?, ?, ?, ?)`,
    [txnType, provider.provider_id, amount, verification.gateway, verification.gatewayRefId, verification.status]
  );
  await query('UPDATE service_providers SET registration_fee_paid = TRUE, registration_txn_id = ? WHERE provider_id = ?', [
    txn.insertId,
    provider.provider_id,
  ]);
  await req.audit('ProviderRegistrationPayment', 'PAYMENT', { amount });

  res.json({ paid: true, amount, transactionId: txn.insertId, message: 'Fee paid. Your account activates once an admin approves your profile.' });
});

// ---------------------------------------------------------------------
// WORK HOURS
// ---------------------------------------------------------------------

export const putWorkHours = asyncHandler(async (req, res) => {
  const { workHours } = req.body;
  if (!Array.isArray(workHours) || workHours.length === 0) throw Errors.badRequest('VALIDATION', 'workHours array is required');

  await withTransaction(async (conn) => {
    await conn.query('DELETE FROM service_provider_work_hours WHERE provider_id = ?', [provId(req)]);
    for (const w of workHours) {
      await conn.query('INSERT INTO service_provider_work_hours (provider_id, day_of_week, start_time, end_time) VALUES (?, ?, ?, ?)', [
        provId(req), w.dayOfWeek, w.startTime, w.endTime,
      ]);
    }
  });
  await req.audit('ProviderWorkHours', 'UPDATE');
  const rows = await query('SELECT * FROM service_provider_work_hours WHERE provider_id = ?', [provId(req)]);
  res.json({ workHours: rows });
});

// ---------------------------------------------------------------------
// CALENDAR BLOCKS
// ---------------------------------------------------------------------

export const listCalendarBlocks = asyncHandler(async (req, res) => {
  // Optional ?from=&to= so a calendar screen can ask for just the month it is
  // showing; with neither, everything from today onwards is returned.
  const { from, to } = req.query;
  const clauses = ['provider_id = ?'];
  const params = [provId(req)];
  if (from) {
    clauses.push('block_end >= ?');
    params.push(from);
  } else {
    clauses.push('block_end >= CURDATE()');
  }
  if (to) {
    clauses.push('block_start <= ?');
    params.push(to);
  }
  const rows = await query(
    `SELECT id, block_start, block_end, reason, created_at
       FROM service_provider_calendar_blocks
      WHERE ${clauses.join(' AND ')}
      ORDER BY block_start`,
    params
  );
  res.json({
    calendarBlocks: rows.map((r) => ({
      id: r.id,
      blockStart: r.block_start,
      blockEnd: r.block_end,
      reason: r.reason,
      createdAt: r.created_at,
    })),
  });
});

export const addCalendarBlock = asyncHandler(async (req, res) => {
  const { blockStart, blockEnd, reason } = req.body;
  if (!blockStart || !blockEnd) throw Errors.badRequest('VALIDATION', 'blockStart and blockEnd are required');
  const result = await query('INSERT INTO service_provider_calendar_blocks (provider_id, block_start, block_end, reason) VALUES (?, ?, ?, ?)', [
    provId(req), blockStart, blockEnd, reason || null,
  ]);
  await req.audit('ProviderCalendarBlock', 'CREATE', { blockStart, blockEnd });
  res.status(201).json({
    id: result.insertId,
    blockStart,
    blockEnd,
    reason: reason || null,
  });
});

export const deleteCalendarBlock = asyncHandler(async (req, res) => {
  const result = await query('DELETE FROM service_provider_calendar_blocks WHERE id = ? AND provider_id = ?', [req.params.id, provId(req)]);
  if (result.affectedRows === 0) throw Errors.notFound('Calendar block not found');
  await req.audit('ProviderCalendarBlock', 'DELETE', { id: req.params.id });
  res.json({ deleted: true });
});

// ---------------------------------------------------------------------
// LOCATION
// ---------------------------------------------------------------------

export const patchLocation = asyncHandler(async (req, res) => {
  const { lat, lng } = req.body;
  if (lat === undefined || lng === undefined) throw Errors.badRequest('VALIDATION', 'lat and lng are required');

  await withTransaction(async (conn) => {
    await conn.query('UPDATE service_providers SET current_latitude = ?, current_longitude = ?, current_location_at = NOW() WHERE provider_id = ?', [
      lat, lng, provId(req),
    ]);
    await conn.query('INSERT INTO provider_location_log (provider_id, latitude, longitude) VALUES (?, ?, ?)', [provId(req), lat, lng]);
  });
  // Not routed through req.audit's generic form so we can flag this as high-frequency/system-ish; still logged.
  await req.audit('ProviderLocationPing', 'UPDATE', { lat, lng });

  res.json({ updated: true });
});

// ---------------------------------------------------------------------
// BOOKING REQUESTS: list / accept / reject
// ---------------------------------------------------------------------

/**
 * Requests waiting for this provider to accept or decline.
 *
 * Carries the customer's first name and the area, and deliberately no more:
 * one request fans out to every matching provider, so the full address and
 * phone number would be handed to a dozen strangers for a job eleven of them
 * will not do. Those arrive with the appointment, once somebody has accepted.
 *
 * It used to carry no name at all -- a provider chose between jobs on a
 * service type and a pair of coordinates.
 */
export const listMyRequests = asyncHandler(async (req, res) => {
  const rows = await query(
    `SELECT br.*, b.display_id AS booking_display_id, b.service_type, b.start_date, b.end_date, b.time_from, b.time_to,
            b.latitude, b.longitude, b.status AS booking_status,
            c.name AS customer_name, c.gender AS customer_gender,
            ca.city AS customer_city, ca.pincode AS customer_pincode
     FROM booking_requests br
     JOIN bookings b ON b.booking_id = br.booking_id
     JOIN customers c ON c.customer_id = b.customer_id
     LEFT JOIN customer_addresses ca ON ca.id = b.address_id
     WHERE br.provider_id = ? AND br.status = 'pending'
     ORDER BY br.sent_at DESC`,
    [provId(req)]
  );
  res.json({
    requests: rows.map((r) => ({
      ...r,
      // First name only until this provider is the one doing the job.
      customer_name: String(r.customer_name || '').split(' ')[0] || 'Customer',
      customer_area: [r.customer_city, r.customer_pincode].filter(Boolean).join(' ') || null,
    })),
  });
});

export const acceptRequest = asyncHandler(async (req, res) => {
  const provider = await loadOwnProvider(req);
  if (!provider.location_on) throw Errors.conflict('LOCATION_OFF', 'Turn location on before accepting requests');

  const bookingId = req.params.bookingId;

  const result = await withTransaction(async (conn) => {
    const [[reqRow]] = await conn.query(
      'SELECT * FROM booking_requests WHERE booking_id = ? AND provider_id = ? FOR UPDATE',
      [bookingId, provId(req)]
    );
    if (!reqRow) throw Errors.notFound('Request not found');
    if (reqRow.status !== 'pending') throw Errors.conflict('REQUEST_NOT_PENDING', `Request already ${reqRow.status}`);

    const [[booking]] = await conn.query('SELECT * FROM bookings WHERE booking_id = ? FOR UPDATE', [bookingId]);
    if (!booking) throw Errors.notFound('Booking not found');
    if (booking.status !== 'searching') {
      throw Errors.conflict('BOOKING_ALREADY_TAKEN', 'This booking was already accepted by another provider');
    }

    const deadline = new Date(Date.now() + env.bookingPaymentWindowMinutes * 60 * 1000);
    await conn.query('UPDATE booking_requests SET status = "accepted", responded_at = NOW() WHERE id = ?', [reqRow.id]);
    await conn.query(
      'UPDATE booking_requests SET status = "invalidated", responded_at = NOW() WHERE booking_id = ? AND provider_id != ? AND status = "pending"',
      [bookingId, provId(req)]
    );
    await conn.query('UPDATE bookings SET confirmed_provider_id = ?, status = "pending_payment", payment_deadline_at = ? WHERE booking_id = ?', [
      provId(req), deadline, bookingId,
    ]);
    return { deadline };
  });

  await req.audit('ProviderAcceptRequest', 'UPDATE', { bookingId });
  res.json({ accepted: true, paymentDeadlineAt: result.deadline });
});

export const rejectRequest = asyncHandler(async (req, res) => {
  const bookingId = req.params.bookingId;
  const result = await query(
    'UPDATE booking_requests SET status = "rejected", responded_at = NOW() WHERE booking_id = ? AND provider_id = ? AND status = "pending"',
    [bookingId, provId(req)]
  );
  if (result.affectedRows === 0) throw Errors.conflict('REQUEST_NOT_PENDING', 'Request not found or already responded to');
  await req.audit('ProviderRejectRequest', 'UPDATE', { bookingId });
  res.json({ rejected: true });
});

// ---------------------------------------------------------------------
// TRANSFERS
// ---------------------------------------------------------------------

export const transferBooking = asyncHandler(async (req, res) => {
  const booking = await loadBookingForProvider(req.params.id, provId(req));
  const { toProviderId } = req.body;
  if (!toProviderId) throw Errors.badRequest('VALIDATION', 'toProviderId is required');
  if (Number(toProviderId) === provId(req)) throw Errors.badRequest('VALIDATION', 'Cannot transfer to yourself');
  if (!['confirmed', 'in_progress'].includes(booking.status)) {
    throw Errors.conflict('INVALID_STATE', `Cannot transfer a booking in status ${booking.status}`);
  }

  const [target] = await query('SELECT provider_id FROM service_providers WHERE provider_id = ? AND approval_status = "approved" AND status = "active"', [toProviderId]);
  if (!target) throw Errors.badRequest('VALIDATION', 'Target provider not found or not eligible');

  const result = await query('INSERT INTO booking_transfers (booking_id, from_provider_id, to_provider_id) VALUES (?, ?, ?)', [
    booking.booking_id, provId(req), toProviderId,
  ]);
  await req.audit('ProviderTransferBooking', 'CREATE', { bookingId: booking.booking_id, toProviderId });
  res.status(201).json({ transferId: result.insertId, status: 'pending' });
});

export const respondTransfer = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { action } = req.body; // 'accept' | 'reject'
  if (!['accept', 'reject'].includes(action)) throw Errors.badRequest('VALIDATION', 'action must be accept or reject');

  const result = await withTransaction(async (conn) => {
    const [[transfer]] = await conn.query('SELECT * FROM booking_transfers WHERE id = ? AND to_provider_id = ? FOR UPDATE', [id, provId(req)]);
    if (!transfer) throw Errors.notFound('Transfer not found');
    if (transfer.status !== 'pending') throw Errors.conflict('ALREADY_RESPONDED', `Transfer already ${transfer.status}`);

    const newStatus = action === 'accept' ? 'accepted' : 'rejected';
    await conn.query('UPDATE booking_transfers SET status = ?, responded_at = NOW() WHERE id = ?', [newStatus, id]);
    if (action === 'accept') {
      await conn.query('UPDATE bookings SET confirmed_provider_id = ? WHERE booking_id = ?', [provId(req), transfer.booking_id]);
    }
    return transfer;
  });

  await req.audit('ProviderRespondTransfer', 'UPDATE', { transferId: id, action });
  res.json({ status: action === 'accept' ? 'accepted' : 'rejected', bookingId: result.booking_id });
});

// ---------------------------------------------------------------------
// START / VERIFY OTP / END / RUNNING LATE / DIRECTIONS
// ---------------------------------------------------------------------

export const startService = asyncHandler(async (req, res) => {
  const provider = await loadOwnProvider(req);
  const booking = await loadBookingForProvider(req.params.id, provId(req));
  if (!['confirmed', 'in_progress'].includes(booking.status)) {
    throw Errors.conflict('INVALID_STATE', `Cannot start a booking in status ${booking.status}`);
  }

  const { selfieUrl } = req.body;
  const faceResult = await verifyFace(selfieUrl, provider.photo_url);
  if (!faceResult.match) throw Errors.unprocessable('FACE_MISMATCH', 'Facial recognition failed');

  const distance = haversineKm(provider.current_latitude, provider.current_longitude, booking.latitude, booking.longitude);
  if (distance === null || distance > env.startServiceGeofenceKm) {
    throw Errors.unprocessable('GEOFENCE_FAILED', `Provider is ${distance ?? 'an unknown distance'} km from the service address (must be within ${env.startServiceGeofenceKm} km)`);
  }

  const today = localToday();
  const sessionDate = today < booking.start_date ? booking.start_date : today > booking.end_date ? booking.end_date : today;

  const otp = generateOtp();
  await query(
    `INSERT INTO booking_service_sessions (booking_id, provider_id, session_date, otp_code, facial_recognition_verified)
     VALUES (?, ?, ?, ?, TRUE)
     ON DUPLICATE KEY UPDATE otp_code = VALUES(otp_code), facial_recognition_verified = TRUE, otp_verified_at = NULL, start_time_actual = NULL, end_time_actual = NULL`,
    [booking.booking_id, provId(req), sessionDate, otp]
  );

  await req.audit('ProviderStartService', 'UPDATE', { bookingId: booking.booking_id, sessionDate, faceMatchConfidence: faceResult.confidence, distanceKm: distance });
  res.json({ started: true, sessionDate, faceMatch: true, distanceKm: distance, message: 'OTP issued to customer. Ask them for it and submit via verify-start-otp.' });
});

export const verifyStartOtp = asyncHandler(async (req, res) => {
  const booking = await loadBookingForProvider(req.params.id, provId(req));
  const { otp } = req.body;
  if (!otp) throw Errors.badRequest('VALIDATION', 'otp is required');

  const [session] = await query(
    `SELECT * FROM booking_service_sessions WHERE booking_id = ? AND provider_id = ? AND facial_recognition_verified = TRUE AND otp_verified_at IS NULL
     ORDER BY id DESC LIMIT 1`,
    [booking.booking_id, provId(req)]
  );
  if (!session) throw Errors.conflict('NO_ACTIVE_SESSION', 'No pending session to verify. Call start first.');
  if (String(otp) !== String(session.otp_code)) throw Errors.unprocessable('OTP_INVALID', 'Incorrect OTP');

  await withTransaction(async (conn) => {
    await conn.query('UPDATE booking_service_sessions SET otp_verified_at = NOW(), start_time_actual = NOW() WHERE id = ?', [session.id]);
    await conn.query('UPDATE bookings SET status = "in_progress" WHERE booking_id = ? AND status = "confirmed"', [booking.booking_id]);
  });
  await req.audit('ProviderVerifyStartOtp', 'UPDATE', { bookingId: booking.booking_id, sessionDate: session.session_date });

  res.json({ verified: true, sessionDate: session.session_date, startTime: new Date().toISOString() });
});

export const endService = asyncHandler(async (req, res) => {
  const provider = await loadOwnProvider(req);
  const booking = await loadBookingForProvider(req.params.id, provId(req));
  const [session] = await query(
    `SELECT * FROM booking_service_sessions WHERE booking_id = ? AND provider_id = ? AND otp_verified_at IS NOT NULL AND end_time_actual IS NULL
     ORDER BY id DESC LIMIT 1`,
    [booking.booking_id, provId(req)]
  );
  if (!session) throw Errors.conflict('NO_OPEN_SESSION', 'No in-progress session to end for this booking');

  const startedAt = new Date(session.start_time_actual);
  const endedAt = new Date();
  const totalHours = Math.max(0.01, Math.round(((endedAt - startedAt) / 3600000) * 100) / 100);

  // Billing branches three ways:
  //  1. No Fees (donated) — nothing is billed; hours are credited to the
  //     provider's Time Bank as points instead.
  //  2. Organization employee — the org's own per-service fee (or the
  //     employee's hourly_rate if the org hasn't overridden it) plus
  //     Sathiyaa's additive revenue-share markup for the customer amount;
  //     the org/employee keeps the full fee (no deduction).
  //  3. Freelancer (default) — the existing deduction-based
  //     revenue_sharing_config split.
  let amount = 0;
  let customerAmount = 0;
  let revenueBreakdown = null;
  let timeBank = null;

  if (provider.no_fees) {
    timeBank = await creditTimeBank({ providerId: provider.provider_id, bookingId: booking.booking_id, serviceType: booking.service_type, hours: totalHours });
    revenueBreakdown = { noFees: true, pointsPerHour: timeBank.pointsPerHour, pointsEarned: timeBank.pointsEarned };
  } else if (provider.provider_kind === 'org_employee') {
    const org = await computeOrgBilling({
      organizationId: provider.organization_id, employeeHourlyRate: provider.hourly_rate,
      serviceType: booking.service_type, totalHours,
    });
    amount = org.providerEarning;
    customerAmount = org.customerAmount;
    revenueBreakdown = { feePerHour: org.feePerHour, markupPercent: org.markupPercent, providerEarning: org.providerEarning };
  } else {
    const split = await computeRevenueSplit({ serviceType: booking.service_type, totalHours, hasReferral: !!booking.referral_code });
    amount = split.providerEarning; // see README: single `amount` column = admin-configured provider payout
    customerAmount = split.customerAmount;
    revenueBreakdown = { customerRatePerHour: split.config?.customer_rate_per_hour ?? null, providerRatePerHour: split.config?.provider_rate_per_hour ?? null, businessPartnerFlatPerHour: split.config?.business_partner_flat_per_hour ?? null, businessPartnerEarning: split.businessPartnerEarning };
  }

  const isLastDay = session.session_date >= booking.end_date;

  // NOTE: computed in two steps rather than one combined UPDATE — MySQL/
  // MariaDB evaluate a multi-column SET clause left to right and a later
  // assignment sees the EARLIER assignment's new value, not the
  // pre-update one, which would silently double-count customerAmount if
  // amount_due and payment_status were derived in the same statement.
  await withTransaction(async (conn) => {
    await conn.query(
      'UPDATE booking_service_sessions SET end_time_actual = NOW(), total_hours = ?, amount = ?, customer_amount = ?, is_no_fees = ? WHERE id = ?',
      [totalHours, amount, customerAmount, !!provider.no_fees, session.id]
    );
    if (customerAmount > 0) {
      await conn.query('UPDATE bookings SET amount_due = COALESCE(amount_due, 0) + ? WHERE booking_id = ?', [customerAmount, booking.booking_id]);
      const [[row]] = await conn.query('SELECT amount_due, amount_received FROM bookings WHERE booking_id = ?', [booking.booking_id]);
      const newStatus = Number(row.amount_received) >= Number(row.amount_due) ? 'paid' : Number(row.amount_received) > 0 ? 'partial' : 'pending';
      await conn.query('UPDATE bookings SET payment_status = ? WHERE booking_id = ?', [newStatus, booking.booking_id]);
    }
    if (isLastDay) {
      await conn.query('UPDATE bookings SET status = "completed" WHERE booking_id = ?', [booking.booking_id]);
    }
  });
  await req.audit('ProviderEndService', 'UPDATE', { bookingId: booking.booking_id, totalHours, amount, customerAmount, noFees: !!provider.no_fees });

  const totalsRows = await query(
    'SELECT SUM(total_hours) AS totalHours, SUM(amount) AS totalAmount, SUM(customer_amount) AS totalCustomerAmount, COUNT(*) AS sessions FROM booking_service_sessions WHERE booking_id = ?',
    [booking.booking_id]
  );
  const [updatedBooking] = await query('SELECT amount_due, amount_received, payment_status FROM bookings WHERE booking_id = ?', [booking.booking_id]);

  res.json({
    ended: true,
    bookingCompleted: isLastDay,
    session: { sessionDate: session.session_date, totalHours, amount, customerAmount, noFees: !!provider.no_fees },
    revenueBreakdown,
    bookingTotals: { totalHours: totalsRows[0].totalHours, totalAmount: totalsRows[0].totalAmount, totalCustomerAmount: totalsRows[0].totalCustomerAmount, sessionsCompleted: totalsRows[0].sessions },
    payment: { amountDue: updatedBooking.amount_due, amountReceived: updatedBooking.amount_received, paymentStatus: updatedBooking.payment_status },
  });
});

export const runningLate = asyncHandler(async (req, res) => {
  const booking = await loadBookingForProvider(req.params.id, provId(req));
  const { minutes } = req.body;
  if (![10, 15, 30].includes(Number(minutes))) throw Errors.badRequest('VALIDATION', 'minutes must be 10, 15 or 30');

  const [provider] = await query('SELECT name FROM service_providers WHERE provider_id = ?', [provId(req)]);
  const delivery = await push.notify({
    userType: 'customer',
    userId: booking.customer_id,
    title: 'Your provider is running late',
    body: `${provider?.name || 'Your provider'} will reach you in about ${minutes} minutes.`,
    data: { type: 'running_late', bookingId: booking.booking_id, minutes },
  });

  await writeAuditLog({
    userType: 'provider', userId: provId(req), formName: 'ProviderRunningLate', action: 'NOTIFY',
    metadata: { bookingId: booking.booking_id, minutes, customerId: booking.customer_id, delivered: delivery.sent },
  });
  await req.audit('ProviderRunningLate', 'NOTIFY', { bookingId: booking.booking_id, minutes });

  res.json({
    notified: true,
    minutes,
    delivered: delivery.sent,
    channel: push.providerName,
    message: `Customer notified that you are running ${minutes} minutes late.`,
  });
});

export const getDirectionsToCustomer = asyncHandler(async (req, res) => {
  const provider = await loadOwnProvider(req);
  const booking = await loadBookingForProvider(req.params.id, provId(req));
  const directions = await getDirections({
    fromLat: provider.current_latitude, fromLng: provider.current_longitude,
    toLat: booking.latitude, toLng: booking.longitude,
  });
  res.json(directions);
});

// ---------------------------------------------------------------------
// APPOINTMENTS
// ---------------------------------------------------------------------

/**
 * The bookings this provider actually has.
 *
 * These rows used to come straight out of the bookings table, so they held a
 * customer id and nothing else -- no name, no address, no phone. A nurse on
 * her way to a house could not say whose house it was, and had no way to ring
 * ahead. The join is what makes the appointment usable.
 */
export const listAppointments = asyncHandler(async (req, res) => {
  const { scope } = req.query;
  let sql = `
    SELECT b.*,
           c.name AS customer_name, c.mobile_number AS customer_mobile,
           c.gender AS customer_gender, c.blood_group AS customer_blood_group,
           c.preferred_comm_mode AS customer_comm_mode,
           c.preferred_comm_timeframe AS customer_comm_timeframe,
           ca.line1 AS address_line1, ca.line2 AS address_line2, ca.city AS address_city,
           ca.state AS address_state, ca.pincode AS address_pincode,
           -- Who the carer is actually visiting. Usually the account holder,
           -- but the commonest case this app exists for is somebody arranging
           -- care for a parent in another city -- and a carer who knocks
           -- asking for the wrong name has already lost the family.
           f.name           AS for_name,
           f.relationship   AS for_relationship,
           f.contact_number AS for_contact_number,
           f.date_of_birth  AS for_date_of_birth,
           f.notes          AS for_notes
    FROM bookings b
    JOIN customers c ON c.customer_id = b.customer_id
    LEFT JOIN customer_addresses ca ON ca.id = b.address_id
    LEFT JOIN customer_family_members f ON f.id = b.for_family_member_id
    WHERE (b.confirmed_provider_id = ? OR b.assigned_employee_id = ?)`;
  const params = [provId(req), provId(req)];
  const today = localToday();
  if (scope === 'past') { sql += ' AND (b.end_date < ? OR b.status IN ("completed","cancelled","expired"))'; params.push(today); }
  else if (scope === 'future') { sql += ' AND b.start_date >= ? AND b.status NOT IN ("cancelled","expired","completed")'; params.push(today); }
  sql += ' ORDER BY b.start_date DESC';
  const rows = await query(sql, params);

  const unread = await unreadCounts(rows.map((r) => r.booking_id), 'provider');

  res.json({
    appointments: rows.map((r) => ({
      ...r,
      unread_messages: unread[r.booking_id] ?? 0,
      customer_address: [r.address_line1, r.address_line2, r.address_city, r.address_pincode]
        .filter(Boolean)
        .join(', ') || null,
    })),
  });
});

// ---------------------------------------------------------------------
// DASHBOARD
// ---------------------------------------------------------------------

const PERIOD_SQL = {
  today: 'DATE(s.created_at) = CURDATE()',
  week: 'YEARWEEK(s.created_at, 3) = YEARWEEK(CURDATE(), 3)',
  month: 'YEAR(s.created_at) = YEAR(CURDATE()) AND MONTH(s.created_at) = MONTH(CURDATE())',
  quarter: 'YEAR(s.created_at) = YEAR(CURDATE()) AND QUARTER(s.created_at) = QUARTER(CURDATE())',
  year: 'YEAR(s.created_at) = YEAR(CURDATE())',
};

async function periodAggregate(providerIds) {
  if (providerIds.length === 0) {
    return Object.fromEntries(Object.keys(PERIOD_SQL).map((k) => [k, { revenue: 0, appointments: 0, pendingAmount: 0 }]));
  }
  const placeholders = providerIds.map(() => '?').join(',');
  const out = {};
  for (const [period, cond] of Object.entries(PERIOD_SQL)) {
    const rows = await query(
      `SELECT COALESCE(SUM(s.amount), 0) AS revenue, COUNT(DISTINCT s.booking_id) AS appointments
       FROM booking_service_sessions s WHERE s.provider_id IN (${placeholders}) AND ${cond}`,
      providerIds
    );
    const pendingRows = await query(
      `SELECT COALESCE(SUM(s.amount), 0) AS pendingAmount FROM booking_service_sessions s
       JOIN bookings b ON b.booking_id = s.booking_id
       WHERE s.provider_id IN (${placeholders}) AND b.status NOT IN ('completed') AND ${cond}`,
      providerIds
    );
    out[period] = { revenue: rows[0].revenue, appointments: rows[0].appointments, pendingAmount: pendingRows[0].pendingAmount };
  }
  return out;
}

export const getDashboard = asyncHandler(async (req, res) => {
  const provider = await loadOwnProvider(req);
  const own = await periodAggregate([provider.provider_id]);

  if (provider.provider_kind === 'organization') {
    const employees = await query('SELECT provider_id, name, display_id FROM service_providers WHERE organization_id = ?', [provider.provider_id]);
    const byEmployee = [];
    for (const emp of employees) {
      byEmployee.push({ providerId: emp.provider_id, name: emp.name, displayId: emp.display_id, ...(await periodAggregate([emp.provider_id])) });
    }
    const orgTotals = await periodAggregate([provider.provider_id, ...employees.map((e) => e.provider_id)]);
    return res.json({ scope: 'organization', organizationTotals: orgTotals, own, byEmployee });
  }

  res.json({ scope: 'individual', own });
});

export const getScheduleOverview = asyncHandler(async (req, res) => {
  const provider = await loadOwnProvider(req);
  if (provider.provider_kind !== 'organization') throw Errors.forbidden('Only an organization head can view the schedule overview');

  const date = req.query.date || localToday();
  const employees = await query('SELECT provider_id, name, display_id FROM service_providers WHERE organization_id = ?', [provider.provider_id]);
  const providerIds = employees.map((e) => e.provider_id);
  if (providerIds.length === 0) return res.json({ date, employees: [] });

  const placeholders = providerIds.map(() => '?').join(',');
  const bookings = await query(
    `SELECT * FROM bookings WHERE confirmed_provider_id IN (${placeholders}) AND start_date <= ? AND end_date >= ? AND status IN ('confirmed','in_progress')`,
    [...providerIds, date, date]
  );

  const byProvider = employees.map((e) => ({
    providerId: e.provider_id,
    name: e.name,
    displayId: e.display_id,
    bookings: bookings.filter((b) => b.confirmed_provider_id === e.provider_id),
    availableForTransfer: !bookings.some((b) => b.confirmed_provider_id === e.provider_id),
  }));

  res.json({ date, employees: byProvider });
});

// ---------------------------------------------------------------------
// EMPLOYEES (org head adds employee)
// ---------------------------------------------------------------------

/**
 * Whether a carer's paperwork is complete enough to send them to a family.
 *
 * Aadhaar identifies them and the police verification is the check a family
 * is actually relying on, so both are required and the police check has to
 * still be in date -- an expired certificate is not a check, it is a record
 * of one that has run out.
 *
 * The medical certificate is deliberately NOT here: it is required only for
 * nursing and physiotherapy, which is a per-booking question rather than a
 * per-person one.
 */
/**
 * Whether an organisation has given us enough to review this carer at all.
 *
 * No longer decides approval -- an admin does that -- but a carer with no
 * police check cannot even be looked at, and the org's own screen says so.
 */
function documentsComplete(b) {
  // Takes either shape: the camelCase body an app sends, or a database row.
  // Both call sites are real and the alternative is two near-identical
  // functions that drift.
  const aadhar = b.aadharDocUrl ?? b.aadhar_doc_url;
  const police = b.policeVerificationUrl ?? b.police_verification_url;
  const validTo = b.policeVerificationValidTo ?? b.police_verification_valid_to;
  if (!aadhar || !police || !validTo) return false;
  return new Date(validTo) > new Date();
}

export const addEmployee = asyncHandler(async (req, res) => {
  const org = await loadOwnProvider(req);
  if (org.provider_kind !== 'organization') throw Errors.forbidden('Only an organization can add employees');

  const b = req.body;
  if (!b.name || !b.mobile) throw Errors.badRequest('VALIDATION', 'name and mobile are required');
  const [existing] = await query('SELECT provider_id FROM service_providers WHERE mobile_number = ?', [b.mobile]);
  if (existing) throw Errors.conflict('ALREADY_REGISTERED', 'A provider with this mobile number already exists');

  const pin = b.pin || b.mobile.slice(-6);
  const pinHash = await bcrypt.hash(String(pin), 10);

  // `address` arrives as an object from the app, but a bare string is the
  // obvious thing for anything else to send. Taking only the object meant a
  // string passed the truthiness check, line1 came out undefined, and the
  // INSERT died on a NOT NULL column -- a 500 where a sentence belongs.
  let addr = null;
  if (typeof b.address === 'string') {
    if (b.address.trim()) addr = { line1: b.address.trim() };
  } else if (b.address && typeof b.address === 'object') {
    if (!b.address.line1 || !String(b.address.line1).trim()) {
      throw Errors.badRequest('VALIDATION', 'address.line1 is required when an address is given');
    }
    addr = b.address;
  }

  const employee = await withTransaction(async (conn) => {
    const [result] = await conn.query(
      `INSERT INTO service_providers
        (display_id, provider_kind, organization_id, name, photo_url, gender, dob, mobile_number, pin_hash,
         aadhar_doc_url, police_verification_url, police_verification_valid_from,
         police_verification_valid_to, medical_certificate_url,
         medical_certificate_valid_from, medical_certificate_valid_to, languages,
         distance_from_home_pref_km, distance_from_office_pref_km, approval_status, status)
       VALUES ('PENDING', 'org_employee', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active')`,
      [
        org.provider_id, b.name, b.photoUrl || null, normaliseGender(b.gender), b.dob || null,
        b.mobile, pinHash,
        // The carer's OWN documents. An organisation being approved says
        // nothing about the person it is about to send into somebody's home,
        // and until now these columns were left null for every employee.
        b.aadharDocUrl || null,
        b.policeVerificationUrl || null,
        b.policeVerificationValidFrom || null,
        b.policeVerificationValidTo || null,
        b.medicalCertificateUrl || null,
        b.medicalCertificateValidFrom || null,
        b.medicalCertificateValidTo || null,
        // A family filters on this. Left null, JSON_CONTAINS matches nothing,
        // so an agency's Gujarati-speaking carer never appears in a search for
        // Gujarati -- which is how every org employee behaved until now.
        Array.isArray(b.languages) && b.languages.length ? JSON.stringify(b.languages) : null,
        b.distanceFromHomePrefKm || null, b.distanceFromOfficePrefKm || null,
        // Always pending.
        //
        // This used to approve a carer outright as soon as the organisation
        // was approved and the two document fields were non-empty -- which
        // means an agency could add somebody, attach any two photographs, and
        // have Sathiyaa tell families that person was verified. Nobody at
        // Sathiyaa had looked at them.
        //
        // Having the documents is the organisation's job. Deciding they are
        // genuine is ours, and it happens in the admin console like it does
        // for every carer who registers on their own.
        'pending',
      ]
    );
    const id = result.insertId;
    await conn.query('UPDATE service_providers SET display_id = ? WHERE provider_id = ?', [displayId('SP', id), id]);
    if (addr) {
      await conn.query(
        `INSERT INTO service_provider_addresses (provider_id, address_type, line1, line2, city, state, pincode, latitude, longitude)
         VALUES (?, 'home', ?, ?, ?, ?, ?, ?, ?)`,
        [id, addr.line1, addr.line2 || null, addr.city || null, addr.state || null, addr.pincode || null, addr.latitude || null, addr.longitude || null]
      );
    }
    if (Array.isArray(b.workHours)) {
      for (const w of b.workHours) {
        await conn.query('INSERT INTO service_provider_work_hours (provider_id, day_of_week, start_time, end_time) VALUES (?, ?, ?, ?)', [
          id, w.dayOfWeek, w.startTime, w.endTime,
        ]);
      }
    }
    // Without this an org's carer matched no service type, so the allocation
    // query never returned them and an agency's staff list looked correct
    // while being unbookable.
    if (Array.isArray(b.expertise)) {
      for (const e of b.expertise) {
        await conn.query('INSERT INTO service_provider_expertise (provider_id, service_type) VALUES (?, ?)', [
          id, typeof e === 'string' ? e : e.serviceType,
        ]);
      }
    }
    const [row] = await conn.query('SELECT * FROM service_providers WHERE provider_id = ?', [id]);
    return row[0];
  });

  await req.audit('ProviderAddEmployee', 'CREATE', { employeeId: employee.provider_id, mobile: b.mobile });
  res.status(201).json({ providerId: employee.provider_id, displayId: employee.display_id, approvalStatus: employee.approval_status, temporaryPin: b.pin ? undefined : pin });
});

// ---------------------------------------------------------------------
// TIME BANK — donated (No Fees) hours, credited as points
// ---------------------------------------------------------------------

export const getTimeBank = asyncHandler(async (req, res) => {
  const summary = await getTimeBankSummary(provId(req));
  res.json(summary);
});

// ---------------------------------------------------------------------
// MANUAL PAYMENT TRACKING (cash/UPI collected in person — separate from
// the payment-gateway `transactions` used for registration/booking fees)
// ---------------------------------------------------------------------

export const recordPayment = asyncHandler(async (req, res) => {
  const booking = await loadBookingForProvider(req.params.id, provId(req));
  const { amount, paymentType, note } = req.body;
  if (!amount || Number(amount) <= 0) throw Errors.badRequest('VALIDATION', 'amount must be a positive number');
  if (!['full', 'part'].includes(paymentType)) throw Errors.badRequest('VALIDATION', 'paymentType must be full or part');

  // Two steps, not one combined UPDATE — see the note in endService: a
  // later SET-clause assignment in the same statement would see the
  // just-updated amount_received rather than its pre-update value.
  const updated = await withTransaction(async (conn) => {
    await conn.query('INSERT INTO booking_payments (booking_id, amount, payment_type, recorded_by, note) VALUES (?, ?, ?, ?, ?)', [
      booking.booking_id, amount, paymentType, provId(req), note || null,
    ]);
    await conn.query('UPDATE bookings SET amount_received = amount_received + ? WHERE booking_id = ?', [amount, booking.booking_id]);
    const [[row]] = await conn.query('SELECT amount_due, amount_received FROM bookings WHERE booking_id = ?', [booking.booking_id]);
    const newStatus = Number(row.amount_due) > 0 && Number(row.amount_received) >= Number(row.amount_due) ? 'paid' : 'partial';
    await conn.query('UPDATE bookings SET payment_status = ? WHERE booking_id = ?', [newStatus, booking.booking_id]);
    return { ...row, payment_status: newStatus };
  });

  await req.audit('ProviderRecordPayment', 'PAYMENT', { bookingId: booking.booking_id, amount, paymentType });

  const remaining = updated.amount_due === null ? null : round2(Number(updated.amount_due) - Number(updated.amount_received));
  res.status(201).json({
    recorded: true,
    amountDue: updated.amount_due,
    amountReceived: updated.amount_received,
    remainingAmount: remaining,
    paymentStatus: updated.payment_status,
  });
});

function round2(n) {
  return Math.round(n * 100) / 100;
}

export const sendPaymentReminder = asyncHandler(async (req, res) => {
  const booking = await loadBookingForProvider(req.params.id, provId(req));
  if (booking.payment_status === 'paid') throw Errors.conflict('ALREADY_PAID', 'This booking is already fully paid');

  await query('UPDATE bookings SET last_payment_reminder_at = NOW() WHERE booking_id = ?', [booking.booking_id]);

  const remaining = booking.amount_due === null ? null : round2(Number(booking.amount_due) - Number(booking.amount_received));
  const delivery = await push.notify({
    userType: 'customer',
    userId: booking.customer_id,
    title: 'Payment pending',
    body: remaining === null
      ? 'You have a pending balance for a recent Sathiyaa booking.'
      : `INR ${remaining.toFixed(0)} is still due for your recent Sathiyaa booking.`,
    data: { type: 'payment_reminder', bookingId: booking.booking_id, remaining },
  });

  await writeAuditLog({
    userType: 'provider', userId: provId(req), formName: 'ProviderPaymentReminder', action: 'NOTIFY',
    metadata: { bookingId: booking.booking_id, customerId: booking.customer_id, remaining, delivered: delivery.sent },
  });
  await req.audit('ProviderPaymentReminder', 'NOTIFY', { bookingId: booking.booking_id });

  res.json({
    notified: true,
    remainingAmount: remaining,
    delivered: delivery.sent,
    channel: push.providerName,
    message: 'Customer notified of the pending balance.',
  });
});

// ---------------------------------------------------------------------
// FEEDBACK ON CUSTOMER
// ---------------------------------------------------------------------

export const rateCustomer = asyncHandler(async (req, res) => {
  const booking = await loadBookingForProvider(req.params.id, provId(req));
  const { rating, comments } = req.body;
  if (!rating || rating < 1 || rating > 5) throw Errors.badRequest('VALIDATION', 'rating must be between 1 and 5');
  if (!['completed', 'in_progress'].includes(booking.status)) {
    throw Errors.conflict('INVALID_STATE', 'Feedback can only be given once the service has started');
  }

  try {
    await withTransaction(async (conn) => {
      await conn.query('INSERT INTO customer_ratings (booking_id, provider_id, customer_id, rating, comments) VALUES (?, ?, ?, ?, ?)', [
        booking.booking_id, provId(req), booking.customer_id, rating, comments || null,
      ]);
      const [[agg]] = await conn.query('SELECT AVG(rating) AS avgRating, COUNT(*) AS cnt FROM customer_ratings WHERE customer_id = ?', [booking.customer_id]);
      await conn.query('UPDATE customers SET rating_avg = ?, rating_count = ? WHERE customer_id = ?', [
        Math.round(agg.avgRating * 100) / 100, agg.cnt, booking.customer_id,
      ]);
    });
  } catch (err) {
    if (err && err.code === 'ER_DUP_ENTRY') throw Errors.conflict('ALREADY_RATED', 'You already gave feedback for this booking');
    throw err;
  }

  await req.audit('ProviderRateCustomer', 'CREATE', { bookingId: booking.booking_id, customerId: booking.customer_id, rating });
  res.status(201).json({ rated: true });
});

// ---------------------------------------------------------------------
// ORGANIZATION: EMPLOYEE MANAGEMENT (list / active-block)
// ---------------------------------------------------------------------

async function requireOrgHead(req) {
  const org = await loadOwnProvider(req);
  if (org.provider_kind !== 'organization') throw Errors.forbidden('Only an organization head can perform this action');
  return org;
}

function serializeEmployee(e) {
  return {
    providerId: e.provider_id,
    displayId: e.display_id,
    name: e.name,
    photoUrl: e.photo_url,
    gender: e.gender,
    mobileNumber: e.mobile_number,
    dob: e.dob,
    languages: e.languages,
    distanceFromHomePrefKm: e.distance_from_home_pref_km,
    distanceFromOfficePrefKm: e.distance_from_office_pref_km,
    // The org's staff screen needs these to say who can actually be sent to
    // a family. Without them the app had no way to tell a verified carer
    // from one who had only been typed in.
    aadharDocUrl: e.aadhar_doc_url,
    policeVerificationUrl: e.police_verification_url,
    policeVerificationValidFrom: e.police_verification_valid_from,
    policeVerificationValidTo: e.police_verification_valid_to,
    medicalCertificateUrl: e.medical_certificate_url,
    medicalCertificateValidFrom: e.medical_certificate_valid_from,
    medicalCertificateValidTo: e.medical_certificate_valid_to,
    approvalStatus: e.approval_status,
    // Whether the organisation has given Sathiyaa enough to review. The two
    // waits look identical on the staff screen otherwise: "we have not sent
    // the police check" and "Sathiyaa has not looked yet" both read as
    // Pending, and only one of them is the organisation's to fix.
    documentsComplete: documentsComplete(e),
    status: e.status,
    ratingAvg: e.rating_avg,
    ratingCount: e.rating_count,
  };
}

export const listEmployees = asyncHandler(async (req, res) => {
  const org = await requireOrgHead(req);
  const employees = await query('SELECT * FROM service_providers WHERE organization_id = ? ORDER BY name ASC', [org.provider_id]);
  const addresses = await query(
    `SELECT provider_id, line1, line2, city, state, pincode, latitude, longitude FROM service_provider_addresses
     WHERE provider_id IN (${employees.map(() => '?').join(',') || 'NULL'}) AND address_type = 'home'`,
    employees.map((e) => e.provider_id)
  );
  const addrByProvider = Object.fromEntries(addresses.map((a) => [a.provider_id, a]));

  // The days and hours each carer works.
  //
  // The app has always SENT these when adding somebody and never got them
  // back, so reopening a carer to edit them showed an empty week and saving
  // wrote that empty week over what was there. They travel with the list now.
  const hours = await query(
    `SELECT provider_id, day_of_week, start_time, end_time FROM service_provider_work_hours
      WHERE provider_id IN (${employees.map(() => '?').join(',') || 'NULL'})`,
    employees.map((e) => e.provider_id)
  );
  const hoursByProvider = hours.reduce((acc, h) => {
    (acc[h.provider_id] ||= []).push({
      dayOfWeek: h.day_of_week,
      startTime: String(h.start_time).slice(0, 5),
      endTime: String(h.end_time).slice(0, 5),
    });
    return acc;
  }, {});

  res.json({
    employees: employees.map((e) => ({
      ...serializeEmployee(e),
      address: addrByProvider[e.provider_id] || null,
      workHours: hoursByProvider[e.provider_id] || [],
    })),
  });
});

// "Mark Active or Block" — org-scoped equivalent of the platform admin's
// block/unblock, restricted to the calling org's own employees.
export const setEmployeeStatus = asyncHandler(async (req, res) => {
  const org = await requireOrgHead(req);
  const { status } = req.body;
  if (!['active', 'blocked'].includes(status)) throw Errors.badRequest('VALIDATION', 'status must be active or blocked');

  const result = await query('UPDATE service_providers SET status = ? WHERE provider_id = ? AND organization_id = ?', [
    status, req.params.id, org.provider_id,
  ]);
  if (result.affectedRows === 0) throw Errors.notFound('Employee not found in your organization');
  await req.audit('ProviderSetEmployeeStatus', 'UPDATE', { employeeId: req.params.id, status });
  res.json({ updated: true, status });
});

export const updateEmployee = asyncHandler(async (req, res) => {
  const org = await requireOrgHead(req);
  const [employee] = await query('SELECT provider_id FROM service_providers WHERE provider_id = ? AND organization_id = ?', [req.params.id, org.provider_id]);
  if (!employee) throw Errors.notFound('Employee not found in your organization');

  const b = req.body;
  const fields = [];
  const values = [];
  const map = {
    name: 'name', photoUrl: 'photo_url', gender: 'gender', dob: 'dob',
    mobileNumber: 'mobile_number',
    aadharDocUrl: 'aadhar_doc_url',
    policeVerificationUrl: 'police_verification_url',
    policeVerificationValidFrom: 'police_verification_valid_from',
    policeVerificationValidTo: 'police_verification_valid_to',
    medicalCertificateUrl: 'medical_certificate_url',
    medicalCertificateValidFrom: 'medical_certificate_valid_from',
    medicalCertificateValidTo: 'medical_certificate_valid_to',
    distanceFromHomePrefKm: 'distance_from_home_pref_km', distanceFromOfficePrefKm: 'distance_from_office_pref_km',
  };
  if (b.gender !== undefined) b.gender = normaliseGender(b.gender);
  // A JSON column, so it is stored as a string and kept out of the plain
  // field map above, which assigns values verbatim. Without this an
  // organisation could edit a carer's languages, get a 200 back, and find
  // nothing had changed.
  if (Array.isArray(b.languages)) {
    fields.push('languages = ?');
    values.push(JSON.stringify(b.languages));
  }
  for (const [k, col] of Object.entries(map)) {
    if (b[k] !== undefined) { fields.push(`${col} = ?`); values.push(b[k]); }
  }
  if (fields.length > 0) {
    values.push(req.params.id);
    await query(`UPDATE service_providers SET ${fields.join(', ')} WHERE provider_id = ?`, values);
  }

  // No auto-approval here either.
  //
  // Uploading the missing documents used to flip a carer from pending to
  // approved on the spot, so an organisation could attach any two photographs
  // and Sathiyaa would immediately tell families that person was verified.
  // Nobody had looked at them. Having the documents is the organisation's
  // job; deciding they are genuine is ours, and it happens in the admin
  // console -- the same review every carer who registers on their own goes
  // through.
  if (b.address) {
    await query(
      `INSERT INTO service_provider_addresses (provider_id, address_type, line1, line2, city, state, pincode, latitude, longitude)
       VALUES (?, 'home', ?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE line1 = VALUES(line1), line2 = VALUES(line2), city = VALUES(city),
         state = VALUES(state), pincode = VALUES(pincode), latitude = VALUES(latitude), longitude = VALUES(longitude)`,
      [req.params.id, b.address.line1, b.address.line2 || null, b.address.city || null, b.address.state || null, b.address.pincode || null, b.address.latitude || null, b.address.longitude || null]
    );
  }
  if (Array.isArray(b.workHours)) {
    await withTransaction(async (conn) => {
      await conn.query('DELETE FROM service_provider_work_hours WHERE provider_id = ?', [req.params.id]);
      for (const w of b.workHours) {
        await conn.query('INSERT INTO service_provider_work_hours (provider_id, day_of_week, start_time, end_time) VALUES (?, ?, ?, ?)', [
          req.params.id, w.dayOfWeek, w.startTime, w.endTime,
        ]);
      }
    });
  }
  await req.audit('ProviderUpdateEmployee', 'UPDATE', { employeeId: req.params.id });
  const [updated] = await query('SELECT * FROM service_providers WHERE provider_id = ?', [req.params.id]);
  res.json(serializeEmployee(updated));
});

// ---------------------------------------------------------------------
// ORGANIZATION: REQUEST ALLOCATION / RE-ALLOCATION / CANCEL
// ---------------------------------------------------------------------

async function loadOrgBooking(bookingId, org) {
  const [booking] = await query('SELECT * FROM bookings WHERE booking_id = ? AND confirmed_provider_id = ?', [bookingId, org.provider_id]);
  if (!booking) throw Errors.notFound('Booking not found for your organization');
  return booking;
}

// "Provision for Org. Admin to allocate request to its employees for
// hours, multiple days, multiple date with specific hours." MVP
// simplification (documented in the coverage matrix): one employee is
// assigned to the whole booking rather than split per day/date — the
// admin's intended day/hours breakdown can be recorded in `notes` for now.
export const allocateEmployee = asyncHandler(async (req, res) => {
  const org = await requireOrgHead(req);
  const booking = await loadOrgBooking(req.params.id, org);
  const { employeeId, notes } = req.body;
  if (!employeeId) throw Errors.badRequest('VALIDATION', 'employeeId is required');

  const [employee] = await query(
    'SELECT provider_id FROM service_providers WHERE provider_id = ? AND organization_id = ? AND approval_status = "approved" AND status = "active"',
    [employeeId, org.provider_id]
  );
  if (!employee) throw Errors.badRequest('VALIDATION', 'Employee not found, not approved, or blocked');

  await query('UPDATE bookings SET assigned_employee_id = ? WHERE booking_id = ?', [employeeId, booking.booking_id]);
  await req.audit('ProviderAllocateEmployee', 'UPDATE', { bookingId: booking.booking_id, employeeId, notes: notes || null });
  res.json({ allocated: true, employeeId: Number(employeeId) });
});

// "Provision for Org. Admin to transfer request from one Employee to
// another" — distinct from transferBooking, which hands a booking to a
// different provider entirely (freelancer-to-freelancer, or org-to-org)
// and requires the receiving side to accept; a same-org reallocation is
// entirely within the admin's own authority, so it applies immediately.
export const reallocateEmployee = asyncHandler(async (req, res) => {
  const org = await requireOrgHead(req);
  const booking = await loadOrgBooking(req.params.id, org);
  const { employeeId } = req.body;
  if (!employeeId) throw Errors.badRequest('VALIDATION', 'employeeId is required');
  if (!['confirmed', 'in_progress'].includes(booking.status)) {
    throw Errors.conflict('INVALID_STATE', `Cannot reallocate a booking in status ${booking.status}`);
  }

  const [employee] = await query(
    'SELECT provider_id FROM service_providers WHERE provider_id = ? AND organization_id = ? AND approval_status = "approved" AND status = "active"',
    [employeeId, org.provider_id]
  );
  if (!employee) throw Errors.badRequest('VALIDATION', 'Employee not found, not approved, or blocked');

  await query('UPDATE bookings SET assigned_employee_id = ? WHERE booking_id = ?', [employeeId, booking.booking_id]);
  await req.audit('ProviderReallocateEmployee', 'UPDATE', { bookingId: booking.booking_id, fromEmployeeId: booking.assigned_employee_id, toEmployeeId: employeeId });
  res.json({ reallocated: true, employeeId: Number(employeeId) });
});

export const orgCancelBooking = asyncHandler(async (req, res) => {
  const org = await requireOrgHead(req);
  const booking = await loadOrgBooking(req.params.id, org);
  if (['completed', 'cancelled', 'expired'].includes(booking.status)) {
    throw Errors.conflict('INVALID_STATE', `Cannot cancel a booking in status ${booking.status}`);
  }

  const hrsBefore = hoursUntilStart(booking.start_date, booking.time_from);
  const { tier, feeAmount, refundAmount } = computeCancellation({
    hoursBeforeStart: hrsBefore,
    baseAmount: booking.booking_charge_paid ? booking.booking_charge_amount : 0,
  });

  await withTransaction(async (conn) => {
    await conn.query(
      `INSERT INTO booking_cancellations (booking_id, cancelled_by_type, cancelled_by_id, reason, hours_before_start, cancellation_fee_amount, refund_amount)
       VALUES (?, 'provider', ?, ?, ?, ?, ?)`,
      [booking.booking_id, org.provider_id, req.body.reason || null, Math.max(0, hrsBefore), feeAmount, refundAmount]
    );
    await conn.query('UPDATE bookings SET status = "cancelled" WHERE booking_id = ?', [booking.booking_id]);
    await conn.query('UPDATE booking_requests SET status = "invalidated" WHERE booking_id = ? AND status = "pending"', [booking.booking_id]);
    if (refundAmount > 0 && booking.booking_charge_txn_id) {
      await conn.query('UPDATE transactions SET status = "refunded" WHERE transaction_id = ?', [booking.booking_charge_txn_id]);
    }
  });

  await req.audit('ProviderOrgCancelBooking', 'CANCEL', { bookingId: booking.booking_id, tier, feeAmount, refundAmount });
  res.json({ cancelled: true, tier, hoursBeforeStart: Math.round(hrsBefore * 10) / 10, cancellationFeeAmount: feeAmount, refundAmount });
});

// ---------------------------------------------------------------------
// ORGANIZATION: UTILIZATION
// ---------------------------------------------------------------------
// "Provision for an Organization to check the utilization of their
// employee, business done, customer rating per employee, pending payment
// from Customer per employee."

export const getUtilization = asyncHandler(async (req, res) => {
  const org = await requireOrgHead(req);
  const employees = await query('SELECT provider_id, name, display_id, status FROM service_providers WHERE organization_id = ?', [org.provider_id]);

  const out = [];
  for (const emp of employees) {
    const [business] = await query(
      `SELECT COALESCE(SUM(amount), 0) AS totalEarning, COALESCE(SUM(customer_amount), 0) AS totalBilled, COUNT(DISTINCT booking_id) AS appointments
       FROM booking_service_sessions WHERE provider_id = ?`,
      [emp.provider_id]
    );
    const [rating] = await query('SELECT AVG(rating) AS avgRating, COUNT(*) AS ratingCount FROM ratings WHERE provider_id = ?', [emp.provider_id]);
    const [pending] = await query(
      `SELECT COALESCE(SUM(GREATEST(COALESCE(amount_due, 0) - amount_received, 0)), 0) AS pendingAmount
       FROM bookings WHERE assigned_employee_id = ? AND status != 'cancelled'`,
      [emp.provider_id]
    );
    out.push({
      providerId: emp.provider_id,
      name: emp.name,
      displayId: emp.display_id,
      status: emp.status,
      appointments: business.appointments,
      businessDone: Number(business.totalBilled),
      employeeEarning: Number(business.totalEarning),
      ratingAvg: rating.avgRating ? Math.round(rating.avgRating * 100) / 100 : 0,
      ratingCount: rating.ratingCount,
      pendingPayment: Number(pending.pendingAmount),
    });
  }

  res.json({ employees: out });
});

// ---------------------------------------------------------------------
// WHERE THEY SIGNED UP FROM
// ---------------------------------------------------------------------

export const putSignupPlace = asyncHandler(async (req, res) => {
  const verdict = await recordSignupPlace({
    table: 'service_providers',
    idColumn: 'provider_id',
    id: provId(req),
    place: req.body || {},
  });
  await req.audit('ProviderSignupPlace', 'UPDATE', {
    city: req.body?.city || null,
    inside: verdict.inside,
    reason: verdict.reason,
  });
  res.json({
    inServiceArea: verdict.inside,
    serviceArea: { city: verdict.area.city, state: verdict.area.state, radiusKm: verdict.area.radiusKm },
  });
});
