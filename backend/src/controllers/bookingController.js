import { query, withTransaction } from '../db/pool.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { Errors } from '../utils/apiError.js';
import { findMatchingProviders } from '../services/providerMatching.js';
import { bookingDisplayId } from '../utils/ids.js';
import { getConfigNumber } from '../services/appConfig.js';
import { createOrder, verifyPayment } from '../integrations/payment.js';
import { computeCancellation, hoursUntilStart } from '../services/cancellationPolicy.js';
import { getDirections } from '../integrations/maps.js';
import { localToday } from '../utils/dates.js';
import { assertOnBooking, listMessages, postMessage, markRead, unreadCounts } from '../services/messageService.js';

const custId = (req) => req.user.id;

async function loadBookingOwned(bookingId, customerId) {
  // The family row is joined rather than fetched separately: every caller of
  // this needs to know who the visit is for, and a second round trip per
  // booking read is a cost with no reason.
  const [booking] = await query(
    `SELECT b.*,
          f.name           AS for_name,
          f.relationship   AS for_relationship,
          f.contact_number AS for_contact_number,
          f.date_of_birth  AS for_date_of_birth,
          f.notes          AS for_notes
       FROM bookings b
       LEFT JOIN customer_family_members f ON f.id = b.for_family_member_id
      WHERE b.booking_id = ? AND b.customer_id = ?`,
    [bookingId, customerId]
  );
  if (!booking) throw Errors.notFound('Booking not found');
  return booking;
}

// ---------------------------------------------------------------------
// CREATE BOOKING + FAN OUT REQUESTS
// ---------------------------------------------------------------------

export const createBooking = asyncHandler(async (req, res) => {
  const b = req.body;
  const required = ['serviceType', 'startDate', 'endDate', 'timeFrom', 'timeTo'];
  for (const f of required) if (!b[f]) throw Errors.badRequest('VALIDATION', `${f} is required`);

  let address = null;
  if (b.addressId) {
    [address] = await query('SELECT * FROM customer_addresses WHERE id = ? AND customer_id = ?', [b.addressId, custId(req)]);
    if (!address) throw Errors.badRequest('VALIDATION', 'addressId does not belong to this customer');
  } else {
    // Every booking happens somewhere, and a booking with no address on it is
    // a provider who does not know where to go and a report that files the
    // revenue under "unknown". Clients that send only coordinates -- which is
    // what the customer app does, from this very address -- get the primary
    // one filled in rather than nothing.
    [address] = await query(
      "SELECT * FROM customer_addresses WHERE customer_id = ? ORDER BY address_type = 'primary' DESC, id ASC LIMIT 1",
      [custId(req)]
    );
  }
  // An explicitly supplied coordinate still wins: it is the more specific
  // statement of where the service is wanted.
  const lat = b.latitude ?? (address ? address.latitude : null);
  const lng = b.longitude ?? (address ? address.longitude : null);

  // Who the visit is for. NULL means the account holder, which is the common
  // case and the one every existing booking is. Checked against this customer's
  // own family rows: without that, an id from somewhere else would attach a
  // stranger's name and number to a booking.
  let forMember = null;
  if (b.forFamilyMemberId) {
    [forMember] = await query(
      'SELECT * FROM customer_family_members WHERE id = ? AND customer_id = ?',
      [b.forFamilyMemberId, custId(req)]
    );
    if (!forMember) {
      throw Errors.badRequest('VALIDATION', 'forFamilyMemberId is not one of your family members');
    }
  }

  const matched = await findMatchingProviders({
    serviceType: b.serviceType,
    dateFrom: b.startDate,
    dateTo: b.endDate,
    timeFrom: b.timeFrom,
    timeTo: b.timeTo,
    lat,
    lng,
    radiusKm: b.radiusKm,
    gender: b.genderPreference && b.genderPreference !== 'any' ? b.genderPreference : undefined,
    language: b.languagePreference,
  });

  // Who actually gets asked.
  //
  // Without `providerIds` the request goes to everyone who matches, which is
  // what this endpoint has always done. That was never quite honest: the app
  // showed one carer's profile and said "requesting Lakshmi Iyer" while the
  // server quietly asked twenty-seven people.
  //
  // With it, the customer picks the shortlist and only those are asked. They
  // are still intersected with the matched set rather than trusted outright —
  // a chosen carer who is off duty, out of range, or already booked for that
  // window must not receive a request they cannot accept, and a provider id
  // from somewhere else must not become a request at all.
  let candidates = matched;
  let unavailable = [];
  if (Array.isArray(b.providerIds) && b.providerIds.length > 0) {
    const wanted = new Set(b.providerIds.map(Number).filter(Number.isFinite));
    if (wanted.size === 0) {
      throw Errors.badRequest('VALIDATION', 'providerIds must be a list of provider ids');
    }
    candidates = matched.filter((p) => wanted.has(Number(p.provider_id)));
    const got = new Set(candidates.map((p) => Number(p.provider_id)));
    unavailable = [...wanted].filter((id) => !got.has(id));

    if (candidates.length === 0) {
      throw Errors.unprocessable(
        'NONE_AVAILABLE',
        'None of the carers you chose are free for that time. Pick somebody else, or change the day.'
      );
    }
  }

  // A reference code that has stopped being valid must not stop a booking.
  //
  // This used to reject the whole request. The code is applied weeks earlier,
  // on the profile screen, and the customer has no idea a partner has since
  // been blocked -- so the person trying to book care was shown "Invalid
  // referral code" for something entirely outside their control, on the one
  // screen where being blocked matters most. Drop the code instead: the
  // booking goes through, and the partner simply earns nothing on it.
  let referralCode = b.referralCode || null;
  if (referralCode) {
    const [agent] = await query('SELECT business_partner_id FROM business_agents WHERE referral_code = ? AND status = "active"', [referralCode]);
    if (!agent) referralCode = null;
  }

  const bookingChargeAmount = await getConfigNumber('customer_booking_amount', 99);

  const booking = await withTransaction(async (conn) => {
    const [result] = await conn.query(
      `INSERT INTO bookings
        (display_id, customer_id, for_family_member_id, service_type, address_id, latitude, longitude, start_date, end_date, time_from, time_to,
         gender_preference, language_preference, referral_code, status, booking_charge_amount)
       VALUES ('PENDING', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'searching', ?)`,
      [
        custId(req), forMember ? forMember.id : null,
        b.serviceType, address ? address.id : null, lat || null, lng || null, b.startDate, b.endDate, b.timeFrom, b.timeTo,
        b.genderPreference || 'any', b.languagePreference || null, referralCode, bookingChargeAmount,
      ]
    );
    const bookingId = result.insertId;
    await conn.query('UPDATE bookings SET display_id = ? WHERE booking_id = ?', [bookingDisplayId(bookingId), bookingId]);

    for (const p of candidates) {
      await conn.query('INSERT INTO booking_requests (booking_id, provider_id) VALUES (?, ?)', [bookingId, p.provider_id]);
    }
    const [row] = await conn.query('SELECT * FROM bookings WHERE booking_id = ?', [bookingId]);
    return row[0];
  });

  await req.audit('CreateBooking', 'CREATE', {
    bookingId: booking.booking_id,
    providersNotified: candidates.length,
    // Worth recording separately: "asked three of the four they picked" is a
    // different event from "asked every carer in range", and only the audit
    // log can answer that afterwards.
    chosenByCustomer: Array.isArray(b.providerIds) ? b.providerIds.length : null,
    unavailableOfChosen: unavailable.length || null,
    forFamilyMemberId: forMember ? forMember.id : null,
  });

  res.status(201).json({
    bookingId: booking.booking_id,
    displayId: booking.display_id,
    status: booking.status,
    bookingChargeAmount: booking.booking_charge_amount,
    providersNotified: candidates.length,
    // True when the customer chose the shortlist. The app says "asked 3 carers"
    // rather than "asked everyone nearby", and the two are different promises.
    chosenByCustomer: Array.isArray(b.providerIds) && b.providerIds.length > 0,
    // Chosen but not asked, because they were not free for that window. Saying
    // nothing here would leave somebody wondering why their first choice never
    // answered.
    unavailableCount: unavailable.length,
    forFamilyMemberId: forMember ? forMember.id : null,
    forName: forMember ? forMember.name : null,
    providers: candidates.map((p) => ({ providerId: p.provider_id, name: p.name, distanceKm: p.distance_km })),
  });
});

// ---------------------------------------------------------------------
// GET / LIST
// ---------------------------------------------------------------------

export const getBooking = asyncHandler(async (req, res) => {
  const booking = await loadBookingOwned(req.params.id, custId(req));
  const unread = await unreadCounts([booking.booking_id], 'customer');
  res.json({
    ...serializeBooking(booking),
    unreadMessages: unread[booking.booking_id] ?? 0,
  });
});

export const listBookings = asyncHandler(async (req, res) => {
  const { scope } = req.query;
  let sql = `SELECT b.*,
          f.name           AS for_name,
          f.relationship   AS for_relationship,
          f.contact_number AS for_contact_number,
          f.date_of_birth  AS for_date_of_birth,
          f.notes          AS for_notes
               FROM bookings b
               LEFT JOIN customer_family_members f ON f.id = b.for_family_member_id
              WHERE b.customer_id = ?`;
  const params = [custId(req)];
  const today = localToday();
  // Columns qualified with the alias now there is a join. MySQL resolves them
  // either way today, because customer_family_members has no column of the
  // same name -- which is exactly the kind of thing that stops being true the
  // next time somebody adds one.
  if (scope === 'past') { sql += ' AND (b.end_date < ? OR b.status IN ("completed","cancelled","expired"))'; params.push(today); }
  else if (scope === 'current') { sql += ' AND b.status IN ("confirmed","in_progress") AND b.start_date <= ? AND b.end_date >= ?'; params.push(today, today); }
  else if (scope === 'future') { sql += ' AND b.start_date > ? AND b.status NOT IN ("cancelled","expired","completed")'; params.push(today); }
  sql += ' ORDER BY b.start_date DESC, b.booking_id DESC';
  const rows = await query(sql, params);

  // Badges in one grouped query rather than one per row: a customer with
  // twenty bookings should cost two round trips, not twenty-one.
  const unread = await unreadCounts(rows.map((r) => r.booking_id), 'customer');

  res.json({
    bookings: rows.map((r) => ({
      ...serializeBooking(r),
      unreadMessages: unread[r.booking_id] ?? 0,
    })),
  });
});

function serializeBooking(b) {
  return {
    bookingId: b.booking_id,
    displayId: b.display_id,
    serviceType: b.service_type,
    startDate: b.start_date,
    endDate: b.end_date,
    timeFrom: b.time_from,
    timeTo: b.time_to,
    status: b.status,
    confirmedProviderId: b.confirmed_provider_id,
    // Where the service happens. The customer's screen shows it back to them
    // and the provider's app navigates to it, so it belongs on the booking
    // rather than only in the row it was read from.
    // Who the visit is for. Null means the account holder. The carer's job
    // sheet reads this before they knock, which is the whole point of it.
    forFamilyMemberId: b.for_family_member_id ?? null,
    forName: b.for_name ?? null,
    forRelationship: b.for_relationship ?? null,
    forContactNumber: b.for_contact_number ?? null,
    forDateOfBirth: b.for_date_of_birth ?? null,
    forNotes: b.for_notes ?? null,
    addressId: b.address_id,
    latitude: b.latitude === null ? null : Number(b.latitude),
    longitude: b.longitude === null ? null : Number(b.longitude),
    bookingChargeAmount: b.booking_charge_amount,
    bookingChargePaid: !!b.booking_charge_paid,
    paymentDeadlineAt: b.payment_deadline_at,
    createdAt: b.created_at,
  };
}


// ---------------------------------------------------------------------
// MESSAGES
// ---------------------------------------------------------------------
//
// One pair of handlers serves both apps. Who is asking comes from the token,
// and messageService decides whether they are on the booking at all — so there
// is no route where the customer's rules and the provider's rules can drift
// apart, which is how one side ends up able to read a thread it should not.

/// The thread on a booking, and it marks the other side's messages read.
export const getBookingMessages = asyncHandler(async (req, res) => {
  const booking = await assertOnBooking(req.params.id, req.user);
  const messages = await listMessages(booking.booking_id);

  // Reading the thread is what marks it read. A separate "mark read" call is
  // one more thing to forget, and the badge then lies.
  await markRead(booking.booking_id, req.user.role);

  res.json({
    bookingId: booking.booking_id,
    // Who the other side is, so the app can put a name at the top without a
    // second request.
    withName: req.user.role === 'customer' ? booking.provider_name : booking.customer_name,
    messages,
  });
});

/// Say something.
export const postBookingMessage = asyncHandler(async (req, res) => {
  const booking = await assertOnBooking(req.params.id, req.user);
  const message = await postMessage(booking.booking_id, {
    senderType: req.user.role,
    senderId: req.user.id,
    body: req.body.body,
  });

  await req.audit('BookingMessage', 'CREATE', { bookingId: booking.booking_id });
  res.status(201).json(message);
});

// ---------------------------------------------------------------------
// PAY BOOKING CHARGE
// ---------------------------------------------------------------------

export const payBooking = asyncHandler(async (req, res) => {
  const booking = await loadBookingOwned(req.params.id, custId(req));
  if (booking.status !== 'pending_payment') {
    throw Errors.conflict('INVALID_STATE', `Cannot pay a booking in status ${booking.status}`);
  }
  if (new Date(booking.payment_deadline_at) < new Date()) {
    await query('UPDATE bookings SET status = "expired" WHERE booking_id = ?', [booking.booking_id]);
    throw Errors.conflict('BOOKING_EXPIRED', 'Payment window has lapsed, this slot was released');
  }

  const order = await createOrder({ amount: booking.booking_charge_amount, receipt: `booking_${booking.booking_id}` });
  const verification = await verifyPayment({ orderId: order.orderId, paymentRef: req.body.paymentRef });

  const txn = await query(
    `INSERT INTO transactions (transaction_type, reference_type, reference_id, amount, gateway, gateway_ref_id, status)
     VALUES ('booking_charge', 'booking', ?, ?, ?, ?, ?)`,
    [booking.booking_id, booking.booking_charge_amount, verification.gateway, verification.gatewayRefId, verification.status]
  );
  await query('UPDATE bookings SET booking_charge_paid = TRUE, booking_charge_txn_id = ?, status = "confirmed" WHERE booking_id = ?', [
    txn.insertId,
    booking.booking_id,
  ]);
  await req.audit('PayBooking', 'PAYMENT', { bookingId: booking.booking_id, amount: booking.booking_charge_amount });

  res.json({ paid: true, transactionId: txn.insertId, status: 'confirmed' });
});

// ---------------------------------------------------------------------
// CANCEL
// ---------------------------------------------------------------------

export const cancelBooking = asyncHandler(async (req, res) => {
  const booking = await loadBookingOwned(req.params.id, custId(req));
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
       VALUES (?, 'customer', ?, ?, ?, ?, ?)`,
      [booking.booking_id, custId(req), req.body.reason || null, Math.max(0, hrsBefore), feeAmount, refundAmount]
    );
    await conn.query('UPDATE bookings SET status = "cancelled" WHERE booking_id = ?', [booking.booking_id]);
    await conn.query('UPDATE booking_requests SET status = "invalidated" WHERE booking_id = ? AND status = "pending"', [booking.booking_id]);
    if (feeAmount > 0) {
      await conn.query(
        `INSERT INTO transactions (transaction_type, reference_type, reference_id, amount, status) VALUES ('cancellation_fee', 'booking', ?, ?, 'success')`,
        [booking.booking_id, feeAmount]
      );
    }
    if (refundAmount > 0 && booking.booking_charge_txn_id) {
      await conn.query('UPDATE transactions SET status = "refunded" WHERE transaction_id = ?', [booking.booking_charge_txn_id]);
    }
  });

  await req.audit('CancelBooking', 'CANCEL', { bookingId: booking.booking_id, tier, feeAmount, refundAmount });

  res.json({ cancelled: true, tier, hoursBeforeStart: round1(hrsBefore), cancellationFeeAmount: feeAmount, refundAmount });
});

function round1(n) { return Math.round(n * 10) / 10; }

// ---------------------------------------------------------------------
// TRACK
// ---------------------------------------------------------------------

export const trackBooking = asyncHandler(async (req, res) => {
  const booking = await loadBookingOwned(req.params.id, custId(req));
  if (!booking.confirmed_provider_id) throw Errors.conflict('NO_PROVIDER', 'No provider confirmed for this booking yet');

  const [provider] = await query(
    'SELECT provider_id, name, current_latitude, current_longitude, current_location_at FROM service_providers WHERE provider_id = ?',
    [booking.confirmed_provider_id]
  );
  const directions = await getDirections({
    fromLat: provider.current_latitude,
    fromLng: provider.current_longitude,
    toLat: booking.latitude,
    toLng: booking.longitude,
  });

  res.json({
    provider: { providerId: provider.provider_id, name: provider.name },
    lastKnownLocation: { lat: provider.current_latitude, lng: provider.current_longitude, at: provider.current_location_at },
    etaMinutes: directions.etaMinutes,
    distanceKm: directions.distanceKm,
  });
});

// ---------------------------------------------------------------------
// SESSION OTP (customer side view of the OTP generated on provider start)
// ---------------------------------------------------------------------

export const getStartOtp = asyncHandler(async (req, res) => {
  const booking = await loadBookingOwned(req.params.id, custId(req));
  const [session] = await query(
    `SELECT * FROM booking_service_sessions WHERE booking_id = ? AND facial_recognition_verified = TRUE AND otp_verified_at IS NULL
     ORDER BY id DESC LIMIT 1`,
    [booking.booking_id]
  );
  if (!session) throw Errors.conflict('NO_ACTIVE_OTP', 'No pending start-OTP for this booking. Provider must call the start endpoint first.');

  res.json({ otp: session.otp_code, sessionDate: session.session_date, message: 'Share this OTP verbally with your provider to begin the service.' });
});

// ---------------------------------------------------------------------
// RATING
// ---------------------------------------------------------------------

export const rateBooking = asyncHandler(async (req, res) => {
  const booking = await loadBookingOwned(req.params.id, custId(req));
  if (booking.status !== 'completed') throw Errors.conflict('INVALID_STATE', 'Can only rate a completed booking');
  const { rating, comments } = req.body;
  if (!rating || rating < 1 || rating > 5) throw Errors.badRequest('VALIDATION', 'rating must be 1-5');

  await withTransaction(async (conn) => {
    await conn.query(
      `INSERT INTO ratings (booking_id, customer_id, provider_id, rating, comments) VALUES (?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE rating = VALUES(rating), comments = VALUES(comments)`,
      [booking.booking_id, custId(req), booking.confirmed_provider_id, rating, comments || null]
    );
    const [[agg]] = await conn.query('SELECT AVG(rating) AS avgRating, COUNT(*) AS cnt FROM ratings WHERE provider_id = ?', [
      booking.confirmed_provider_id,
    ]);
    await conn.query('UPDATE service_providers SET rating_avg = ?, rating_count = ? WHERE provider_id = ?', [
      Math.round(agg.avgRating * 100) / 100,
      agg.cnt,
      booking.confirmed_provider_id,
    ]);
  });

  await req.audit('RateBooking', 'CREATE', { bookingId: booking.booking_id, rating });
  res.status(201).json({ rated: true });
});
