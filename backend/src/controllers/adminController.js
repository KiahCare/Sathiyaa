import bcrypt from 'bcryptjs';
import { query } from '../db/pool.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { Errors } from '../utils/apiError.js';
import { displayId, randomReferralCode } from '../utils/ids.js';
import { getAllConfig, setConfig } from '../services/appConfig.js';
import { findMatchingProviders } from '../services/providerMatching.js';
import {
  parseTargeting, resolveRecipients, availableCities,
} from '../services/broadcastTargeting.js';
import { getServiceArea } from '../services/serviceArea.js';
import * as push from '../integrations/push.js';
import { localToday } from '../utils/dates.js';

const adminId = (req) => req.user.id;

// ---------------------------------------------------------------------
// EMERGENCY ALERTS
// ---------------------------------------------------------------------

/// Every SOS raised, newest first, open ones first when asked.
///
/// An alert nobody in the office can see is an alert nobody acts on, which
/// makes the button on the customer's screen a decoration.
export const listSosAlerts = asyncHandler(async (req, res) => {
  const { openOnly, limit } = req.query;
  const max = Math.min(parseInt(limit, 10) || 100, 300);

  const rows = await query(
    `SELECT s.id, s.customer_id AS customerId, c.name AS customerName,
            c.display_id AS customerDisplayId, c.mobile_number AS customerMobile,
            s.latitude, s.longitude, s.address_text AS addressText,
            s.booking_id AS bookingId, s.note, s.delivery,
            s.notified_count AS notifiedCount, s.recipients,
            s.acknowledged_at AS acknowledgedAt, s.acknowledged_by AS acknowledgedBy,
            s.resolution, s.created_at AS createdAt
       FROM sos_alerts s
       JOIN customers c ON c.customer_id = s.customer_id
      ${openOnly === 'true' ? 'WHERE s.acknowledged_at IS NULL' : ''}
      ORDER BY s.acknowledged_at IS NULL DESC, s.created_at DESC
      LIMIT ${max}`
  );

  const [[open]] = [await query('SELECT COUNT(*) AS n FROM sos_alerts WHERE acknowledged_at IS NULL')];
  res.json({ alerts: rows, openCount: open.n, count: rows.length });
});

/// Mark an alert as dealt with, with a note saying what happened.
export const acknowledgeSosAlert = asyncHandler(async (req, res) => {
  const { resolution } = req.body;
  if (!resolution || resolution.trim().length < 3) {
    // A blank resolution is how an alert gets quietly closed without anybody
    // having done anything about it.
    throw Errors.badRequest('VALIDATION', 'Say what was done about it — a few words is enough.');
  }

  const [alert] = await query('SELECT * FROM sos_alerts WHERE id = ?', [req.params.id]);
  if (!alert) throw Errors.notFound('Alert not found');
  if (alert.acknowledged_at) throw Errors.conflict('ALREADY_CLOSED', 'That alert has already been closed.');

  await query(
    'UPDATE sos_alerts SET acknowledged_at = NOW(), acknowledged_by = ?, resolution = ? WHERE id = ?',
    [adminId(req), resolution.trim(), req.params.id]
  );
  await req.audit('AdminSOS', 'UPDATE', { alertId: alert.id, resolution: resolution.trim() });

  res.json({ acknowledged: true, alertId: alert.id });
});

// ---------------------------------------------------------------------
// DEVICE REGISTRY
// ---------------------------------------------------------------------

const DEVICE_SELECT = `
  SELECT d.id,
         d.user_type      AS userType,
         d.user_id        AS userId,
         d.device_id      AS deviceId,
         d.platform,
         d.manufacturer,
         d.model,
         d.os_version     AS osVersion,
         d.app_version    AS appVersion,
         d.is_physical    AS isPhysical,
         d.first_seen_at  AS firstSeenAt,
         d.last_seen_at   AS lastSeenAt,
         d.last_ip        AS lastIp,
         d.last_user_agent AS lastUserAgent,
         d.is_current     AS isCurrent,
         COALESCE(p.name, c.name, b.partner_name, a.name)             AS ownerName,
         COALESCE(p.display_id, c.display_id, b.display_id)           AS ownerDisplayId,
         COALESCE(p.mobile_number, c.mobile_number, b.contact_number_1) AS ownerMobile
    FROM user_devices d
    LEFT JOIN service_providers p ON d.user_type = 'provider'       AND p.provider_id = d.user_id
    LEFT JOIN customers c         ON d.user_type = 'customer'       AND c.customer_id = d.user_id
    LEFT JOIN business_agents b   ON d.user_type = 'business_agent' AND b.business_partner_id = d.user_id
    LEFT JOIN admin_users a       ON d.user_type = 'admin'          AND a.admin_id = d.user_id
`;

/// Every device that has signed in, newest first.
///
/// This is the screen somebody opens after a complaint: which handset was that
/// account on, when, and from what address. Filterable by role, by a search
/// across owner and model, and by "only the device the account is bound to
/// now".
export const listDevices = asyncHandler(async (req, res) => {
  const { userType, search, currentOnly, limit } = req.query;

  const where = [];
  const params = [];

  if (userType && userType !== 'all') {
    where.push('d.user_type = ?');
    params.push(userType);
  }
  if (currentOnly === 'true') {
    where.push('d.is_current = TRUE');
  }
  if (search) {
    const like = `%${search}%`;
    where.push(`(
      d.device_id LIKE ? OR d.model LIKE ? OR d.manufacturer LIKE ? OR d.last_ip LIKE ?
      OR p.name LIKE ? OR c.name LIKE ? OR b.partner_name LIKE ? OR a.name LIKE ?
      OR p.display_id LIKE ? OR c.display_id LIKE ?
    )`);
    params.push(like, like, like, like, like, like, like, like, like, like);
  }

  // Capped, and the cap is applied after the filters so a search still reaches
  // old rows. 500 is enough for any console table and stops a stray request
  // pulling the whole registry into memory.
  const max = Math.min(parseInt(limit, 10) || 200, 500);

  const rows = await query(
    `${DEVICE_SELECT}
     ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
     ORDER BY d.last_seen_at DESC
     LIMIT ${max}`,
    params
  );

  res.json({ devices: rows, count: rows.length, limit: max });
});

/// Every device one account has ever signed in from.
export const listDevicesForUser = asyncHandler(async (req, res) => {
  const { userType, userId } = req.params;
  if (!['customer', 'provider', 'business_agent', 'admin'].includes(userType)) {
    throw Errors.badRequest('VALIDATION', 'userType must be customer, provider, business_agent or admin');
  }

  const rows = await query(
    `${DEVICE_SELECT} WHERE d.user_type = ? AND d.user_id = ? ORDER BY d.last_seen_at DESC`,
    [userType, userId]
  );

  res.json({ devices: rows, count: rows.length });
});

/// Other accounts that have used the same handset.
///
/// One device under several provider accounts is the pattern worth catching:
/// a verified carer passing their phone around, which is exactly what binding
/// an account to a device is meant to prevent.
export const listAccountsOnDevice = asyncHandler(async (req, res) => {
  const rows = await query(
    `${DEVICE_SELECT} WHERE d.device_id = ? ORDER BY d.last_seen_at DESC`,
    [req.params.deviceId]
  );

  res.json({
    deviceId: req.params.deviceId,
    accounts: rows,
    count: rows.length,
    shared: rows.length > 1,
  });
});

// ---------------------------------------------------------------------
// THIS ADMIN'S OWN ACCOUNT
// ---------------------------------------------------------------------

/// Change your own password.
///
/// There was no way to do this at all: the super-admin password is baked into
/// the seed and written down in the repository, and nothing in the API could
/// change it afterwards. On a server strangers can reach, an account whose
/// password is public is not an account.
///
/// Requires the current password, so a token lifted from a laptop somebody
/// left open cannot be used to lock the real owner out.
export const changeOwnPassword = asyncHandler(async (req, res) => {
  const { currentPassword, newPassword } = req.body;
  if (!currentPassword || !newPassword) {
    throw Errors.badRequest('VALIDATION', 'currentPassword and newPassword are required');
  }
  if (newPassword.length < 12) {
    throw Errors.unprocessable(
      'PASSWORD_TOO_SHORT',
      'Use at least 12 characters. A short phrase of a few unrelated words is stronger than a clever short one, and easier to type.'
    );
  }
  if (newPassword === currentPassword) {
    throw Errors.unprocessable('PASSWORD_UNCHANGED', 'That is the password you already have.');
  }

  const [admin] = await query('SELECT * FROM admin_users WHERE admin_id = ?', [adminId(req)]);
  if (!admin) throw Errors.notFound('Admin account not found');

  const ok = await bcrypt.compare(currentPassword, admin.password_hash);
  if (!ok) throw Errors.unprocessable('PASSWORD_INVALID', 'That is not your current password.');

  const hash = await bcrypt.hash(newPassword, 12);
  await query('UPDATE admin_users SET password_hash = ? WHERE admin_id = ?', [hash, admin.admin_id]);
  // The old password is not recorded, only that it changed and by whom.
  await req.audit('AdminUser', 'PASSWORD_CHANGE', { adminId: admin.admin_id });

  res.json({
    message:
      'Password changed. Anyone already signed in stays signed in until their token expires — ' +
      'change JWT_SECRET and restart the API if you need to cut that short.',
  });
});

// ---------------------------------------------------------------------
// PROVIDER APPROVAL
// ---------------------------------------------------------------------

/**
 * Columns the admin console may see. Explicit rather than `SELECT *`, because
 * `SELECT *` on this table was returning `pin_hash` to the browser — a
 * provider's login credential, sent to every admin page load. Listing the
 * columns means a future migration cannot quietly re-introduce that.
 */
const PROVIDER_COLUMNS = [
  'provider_id', 'display_id', 'provider_kind', 'organization_id', 'name', 'photo_url',
  'gender', 'dob', 'mobile_number', 'email', 'hourly_rate', 'no_fees',
  'aadhar_doc_url', 'police_verification_url', 'police_verification_valid_from',
  'police_verification_valid_to', 'medical_certificate_url', 'medical_certificate_valid_from',
  'medical_certificate_valid_to', 'work_certificate_url', 'allocate_via_org',
  // Organisations only, and null for a freelancer. Without these the console
  // cannot show an agency's registration certificate, so approving one means
  // approving a document nobody in the console has seen.
  'org_registration_url', 'gst_number', 'contact_person',
  'approval_status', 'approval_notes', 'approved_by', 'approved_at', 'status',
  'registration_fee_paid', 'device_id', 'location_on', 'current_latitude',
  'current_longitude', 'current_location_at', 'distance_from_home_pref_km',
  'distance_from_office_pref_km', 'languages', 'rating_avg', 'rating_count', 'created_at',
].map((c) => `p.${c}`).join(', ');

/**
 * Attaches each provider's expertise, addresses and work hours.
 *
 * The console's list and detail views both read these, and without them every
 * row rendered blank. Fetched as three grouped queries rather than one joined
 * query per provider, so the cost stays flat as the directory grows.
 */
async function attachProviderDetail(rows) {
  if (rows.length === 0) return rows;
  const ids = rows.map((r) => r.provider_id);
  const placeholders = ids.map(() => '?').join(',');

  const [expertise, addresses, workHours] = await Promise.all([
    query(`SELECT provider_id, service_type, years_experience, notes FROM service_provider_expertise WHERE provider_id IN (${placeholders})`, ids),
    query(`SELECT id, provider_id, address_type, line1, line2, city, state, pincode, latitude, longitude FROM service_provider_addresses WHERE provider_id IN (${placeholders})`, ids),
    query(`SELECT id, provider_id, day_of_week, start_time, end_time FROM service_provider_work_hours WHERE provider_id IN (${placeholders})`, ids),
  ]);

  const group = (list) => list.reduce((acc, row) => {
    (acc[row.provider_id] ||= []).push(row);
    return acc;
  }, {});
  const byExpertise = group(expertise);
  const byAddress = group(addresses);
  const byHours = group(workHours);

  return rows.map((r) => ({
    ...r,
    expertise: byExpertise[r.provider_id] || [],
    addresses: byAddress[r.provider_id] || [],
    work_hours: byHours[r.provider_id] || [],
  }));
}

export const listProviders = asyncHandler(async (req, res) => {
  const { status } = req.query;
  // The organisation's name, for a carer who belongs to one.
  //
  // Org employees are in this list and are approved from it -- an admin
  // checking an agency's carer had no way to see which agency, so "Priya
  // Shah, pending" arrived with no context at all and the approve button
  // meant approving a stranger.
  let sql = `SELECT ${PROVIDER_COLUMNS}, org.name AS organization_name
               FROM service_providers p
               LEFT JOIN service_providers org ON org.provider_id = p.organization_id`;
  const params = [];
  // The console sends `all` for its "All" tab; treat that as no filter rather
  // than matching an approval_status literally named "all", which matched
  // nothing and made the tab look empty.
  if (status && status !== 'all') { sql += ' WHERE p.approval_status = ?'; params.push(status); }
  sql += ' ORDER BY p.created_at DESC';
  const rows = await query(sql, params);
  res.json({ providers: await attachProviderDetail(rows) });
});

/**
 * Clears the device an account is bound to.
 *
 * A provider account is tied to one phone by design, so a lost, replaced or
 * wiped handset locks the provider out permanently with no way back. This is
 * the way back, and it is an admin action on purpose — self-service would
 * defeat the point of binding in the first place.
 */
export const resetProviderDevice = asyncHandler(async (req, res) => {
  const [provider] = await query('SELECT provider_id, name, device_id FROM service_providers WHERE provider_id = ?', [req.params.id]);
  if (!provider) throw Errors.notFound('Provider not found');

  await query('UPDATE service_providers SET device_id = NULL WHERE provider_id = ?', [req.params.id]);
  // The binding goes; the record of which handset it was stays. That history
  // is the reason the registry exists — clearing it on release would throw
  // away exactly the row somebody would come looking for afterwards.
  await query(
    "UPDATE user_devices SET is_current = FALSE WHERE user_type = 'provider' AND user_id = ?",
    [req.params.id]
  );
  await req.audit('AdminProviderDeviceReset', 'UPDATE', {
    providerId: provider.provider_id,
    previousDeviceId: provider.device_id,
  });

  res.json({
    reset: true,
    providerId: provider.provider_id,
    message: `${provider.name} can now sign in from a new device. The next device to log in becomes the bound one.`,
  });
});

async function setProviderApproval(req, res, approvalStatus, notes) {
  const { id } = req.params;
  const result = await query('UPDATE service_providers SET approval_status = ?, approval_notes = ?, approved_by = ?, approved_at = NOW() WHERE provider_id = ?', [
    approvalStatus, notes || null, adminId(req), id,
  ]);
  if (result.affectedRows === 0) throw Errors.notFound('Provider not found');
  await req.audit(`AdminProvider${approvalStatus[0].toUpperCase()}${approvalStatus.slice(1)}`, 'UPDATE', { providerId: id });
  res.json({ providerId: Number(id), approvalStatus });
}

export const approveProvider = asyncHandler((req, res) => setProviderApproval(req, res, 'approved', req.body.notes));
export const holdProvider = asyncHandler((req, res) => setProviderApproval(req, res, 'hold', req.body.notes));
export const rejectProvider = asyncHandler((req, res) => setProviderApproval(req, res, 'rejected', req.body.notes));

export const blockProvider = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const result = await query('UPDATE service_providers SET status = "blocked" WHERE provider_id = ?', [id]);
  if (result.affectedRows === 0) throw Errors.notFound('Provider not found');
  await req.audit('AdminProviderBlock', 'UPDATE', { providerId: id });
  res.json({ providerId: Number(id), status: 'blocked' });
});

export const unblockProvider = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const result = await query('UPDATE service_providers SET status = "active" WHERE provider_id = ?', [id]);
  if (result.affectedRows === 0) throw Errors.notFound('Provider not found');
  await req.audit('AdminProviderUnblock', 'UPDATE', { providerId: id });
  res.json({ providerId: Number(id), status: 'active' });
});

export const listCustomers = asyncHandler(async (req, res) => {
  const { status } = req.query;
  // The console shows a city per customer, taken from the primary address.
  let sql = `SELECT c.customer_id, c.display_id, c.name, c.photo_url, c.dob, c.gender,
                    c.blood_group, c.email, c.mobile_number, c.registration_fee_paid,
                    c.referred_by_code, c.status, c.created_at,
                    a.city
               FROM customers c
               LEFT JOIN customer_addresses a
                 ON a.customer_id = c.customer_id AND a.address_type = 'primary'`;
  const params = [];
  if (status && status !== 'all') { sql += ' WHERE c.status = ?'; params.push(status); }
  sql += ' ORDER BY c.created_at DESC';
  const rows = await query(sql, params);
  res.json({ customers: rows });
});

/**
 * Removes a registration outright.
 *
 * Blocking is the right answer for a real account that misbehaves -- the
 * history stays, and the audit trail still makes sense. This is for the other
 * case: a junk registration that should never have been a row. Automated test
 * runs create these by the dozen, and they crowd out the real directory.
 *
 * Refused once there is any history to lose. A provider who has ever been on a
 * booking gets blocked, not deleted.
 */
export const deleteProvider = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const [provider] = await query('SELECT provider_id, display_id, name FROM service_providers WHERE provider_id = ?', [id]);
  if (!provider) throw Errors.notFound('Provider not found');

  const [{ n: bookings }] = await query(
    'SELECT COUNT(*) AS n FROM bookings WHERE confirmed_provider_id = ?', [id]
  );
  const [{ n: sessions }] = await query(
    'SELECT COUNT(*) AS n FROM booking_service_sessions WHERE provider_id = ?', [id]
  );
  // Having ACCEPTED a request is history. Having been asked is not.
  //
  // Every provider in range is asked about every booking, so within a week of
  // going live that would be all of them -- and booking_requests holds a
  // foreign key with no ON DELETE, so the delete failed on the constraint and
  // came back as a 500 reading "Something went wrong".
  const [{ n: accepted }] = await query(
    "SELECT COUNT(*) AS n FROM booking_requests WHERE provider_id = ? AND status = 'accepted'", [id]
  );
  if (bookings > 0 || sessions > 0 || accepted > 0) {
    throw Errors.conflict(
      'HAS_HISTORY',
      `${provider.name} has worked on ${bookings + accepted} booking(s). Block the account instead of deleting it, so the history stays intact.`
    );
  }

  // The requests they were offered and never took. Cleared with them, because
  // a row saying "we asked somebody who no longer exists" is not a record
  // anybody reads.
  await query("DELETE FROM booking_requests WHERE provider_id = ? AND status <> 'accepted'", [id]);
  await query('DELETE FROM service_providers WHERE provider_id = ?', [id]);
  await req.audit('AdminProviderDeleted', 'DELETE', { providerId: Number(id), displayId: provider.display_id, name: provider.name });
  res.json({ deleted: true, providerId: Number(id), displayId: provider.display_id });
});

/** The same, for a customer with no bookings. */
export const deleteCustomer = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const [customer] = await query('SELECT customer_id, display_id, name FROM customers WHERE customer_id = ?', [id]);
  if (!customer) throw Errors.notFound('Customer not found');

  const [{ n: bookings }] = await query('SELECT COUNT(*) AS n FROM bookings WHERE customer_id = ?', [id]);
  if (bookings > 0) {
    throw Errors.conflict(
      'HAS_HISTORY',
      `${customer.name} has ${bookings} booking(s). Block the account instead of deleting it, so the history stays intact.`
    );
  }

  await query('DELETE FROM customers WHERE customer_id = ?', [id]);
  await req.audit('AdminCustomerDeleted', 'DELETE', { customerId: Number(id), displayId: customer.display_id, name: customer.name });
  res.json({ deleted: true, customerId: Number(id), displayId: customer.display_id });
});

export const blockCustomer = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const result = await query('UPDATE customers SET status = "blocked" WHERE customer_id = ?', [id]);
  if (result.affectedRows === 0) throw Errors.notFound('Customer not found');
  await req.audit('AdminCustomerBlock', 'UPDATE', { customerId: id });
  res.json({ customerId: Number(id), status: 'blocked' });
});

export const unblockCustomer = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const result = await query('UPDATE customers SET status = "active" WHERE customer_id = ?', [id]);
  if (result.affectedRows === 0) throw Errors.notFound('Customer not found');
  await req.audit('AdminCustomerUnblock', 'UPDATE', { customerId: id });
  res.json({ customerId: Number(id), status: 'active' });
});

// ---------------------------------------------------------------------
// BUSINESS AGENTS
// ---------------------------------------------------------------------

export const listBusinessAgents = asyncHandler(async (req, res) => {
  // The console shows a second contact, the address and the registration date;
  // omitting created_at was rendering the column as "Invalid Date".
  // password_hash and otp_hash are deliberately not selected.
  const rows = await query(
    `SELECT business_partner_id, display_id, entity_name, partner_name,
            contact_number_1, contact_number_2, email, address,
            referral_code, status, created_at
       FROM business_agents
      ORDER BY created_at DESC`
  );
  res.json({ businessAgents: rows });
});

export const createBusinessAgent = asyncHandler(async (req, res) => {
  const b = req.body;
  if (!b.entityName || !b.partnerName || !b.contactNumber1) {
    throw Errors.badRequest('VALIDATION', 'entityName, partnerName and contactNumber1 are required');
  }
  const referralCode = randomReferralCode(b.entityName);
  const passwordHash = b.password ? await bcrypt.hash(b.password, 10) : null;

  const result = await query(
    `INSERT INTO business_agents (display_id, entity_name, partner_name, contact_number_1, contact_number_2, email, address, password_hash, referral_code)
     VALUES ('PENDING', ?, ?, ?, ?, ?, ?, ?, ?)`,
    [b.entityName, b.partnerName, b.contactNumber1, b.contactNumber2 || null, b.email || null, b.address || null, passwordHash, referralCode]
  );
  const id = result.insertId;
  await query('UPDATE business_agents SET display_id = ? WHERE business_partner_id = ?', [displayId('BP', id), id]);
  await req.audit('AdminCreateBusinessAgent', 'CREATE', { businessPartnerId: id });

  res.status(201).json({ businessPartnerId: id, displayId: displayId('BP', id), referralCode });
});

// Admin block/unblock — Business Partner. Blocked partners are rejected at
// businessAgentLogin (authController.js checks status === 'blocked') the
// same way a blocked Customer or Service Provider is; a blocked partner's
// portal login also fails so they can't submit new referrals.
export const updateBusinessAgent = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { status } = req.body;
  if (status !== 'active' && status !== 'blocked') {
    throw Errors.badRequest('VALIDATION', "status must be 'active' or 'blocked'");
  }
  const result = await query('UPDATE business_agents SET status = ? WHERE business_partner_id = ?', [status, id]);
  if (result.affectedRows === 0) throw Errors.notFound('Business partner not found');
  await req.audit(status === 'blocked' ? 'AdminBusinessAgentBlock' : 'AdminBusinessAgentUnblock', 'UPDATE', { businessPartnerId: id });
  const [agent] = await query(
    'SELECT business_partner_id, display_id, entity_name, partner_name, contact_number_1, email, referral_code, status FROM business_agents WHERE business_partner_id = ?',
    [id]
  );
  res.json(agent);
});

// ---------------------------------------------------------------------
// CONFIGURATION
// ---------------------------------------------------------------------

export const getConfigAll = asyncHandler(async (req, res) => {
  const rows = await getAllConfig();
  res.json({ config: rows });
});

export const putConfig = asyncHandler(async (req, res) => {
  const updates = req.body.config || req.body; // accept { config: {...} } or flat object
  if (!updates || typeof updates !== 'object') throw Errors.badRequest('VALIDATION', 'config object is required');

  // Validate before writing any of it, so a bad third value does not leave the
  // first two applied.
  //
  // There was no validation here at all: whatever arrived was String()'d
  // straight into the table. Every key in this table is a money amount or a
  // count, so `-50` was accepted and would have become a negative booking fee,
  // and a non-numeric value became NaN the next time anything read it. Neither
  // showed up in the console, which happily displayed what it had just saved.
  // Not every setting is an amount of money any more. The service area is a
  // city name, a switch and a pair of coordinates, and forcing those through
  // Number() turned "Ahmedabad" into NaN and rejected the save -- so the
  // keys that are not numbers are named, and each gets the check that
  // actually applies to it.
  const TEXT_KEYS = new Set(['service_area_city', 'service_area_state']);
  const BOOLEAN_KEYS = new Set(['service_area_enabled']);
  const RANGES = {
    service_area_lat: [-90, 90],
    service_area_lng: [-180, 180],
    service_area_radius_km: [1, 2000],
  };

  const cleaned = {};
  for (const [key, raw] of Object.entries(updates)) {
    if (TEXT_KEYS.has(key)) {
      const text = String(raw ?? '').trim();
      if (text.length < 2) {
        throw Errors.badRequest('VALIDATION', `${key} needs a place name — got ${JSON.stringify(raw)}`);
      }
      cleaned[key] = text.slice(0, 100);
      continue;
    }
    if (BOOLEAN_KEYS.has(key)) {
      const text = String(raw ?? '').trim().toLowerCase();
      if (text !== 'true' && text !== 'false') {
        throw Errors.badRequest('VALIDATION', `${key} must be true or false — got ${JSON.stringify(raw)}`);
      }
      cleaned[key] = text;
      continue;
    }

    const n = Number(raw);
    if (raw === null || raw === '' || !Number.isFinite(n)) {
      throw Errors.badRequest('VALIDATION', `${key} must be a number — got ${JSON.stringify(raw)}`);
    }
    const range = RANGES[key];
    if (range) {
      // Latitude is allowed to be negative; a booking fee is not. The old
      // blanket "cannot be negative" would have made half the planet
      // unreachable the moment this table held a coordinate.
      if (n < range[0] || n > range[1]) {
        throw Errors.badRequest('VALIDATION', `${key} must be between ${range[0]} and ${range[1]} — got ${n}`);
      }
    } else if (n < 0) {
      throw Errors.badRequest('VALIDATION', `${key} cannot be negative — got ${n}`);
    }
    cleaned[key] = n;
  }

  for (const [key, value] of Object.entries(cleaned)) {
    await setConfig(key, value, adminId(req));
  }
  await req.audit('AdminUpdateConfig', 'UPDATE', { keys: Object.keys(updates) });
  const rows = await getAllConfig();
  res.json({ config: rows });
});

// ---------------------------------------------------------------------
// REVENUE SHARING
// ---------------------------------------------------------------------

export const getRevenueSharing = asyncHandler(async (req, res) => {
  const rows = await query(
    `SELECT rsc.* FROM revenue_sharing_config rsc
     INNER JOIN (SELECT service_type, MAX(effective_from) AS maxDate FROM revenue_sharing_config GROUP BY service_type) latest
       ON latest.service_type = rsc.service_type AND latest.maxDate = rsc.effective_from
     ORDER BY rsc.service_type`
  );
  res.json({ revenueSharing: rows });
});

async function upsertRevenueSharingRow(row) {
  // Accepts either camelCase (single-item legacy shape) or snake_case
  // (admin-portal's batch { items: [...] } shape, matching RevenueSharingConfig).
  const serviceType = row.serviceType ?? row.service_type;
  const customerRatePerHour = row.customerRatePerHour ?? row.customer_rate_per_hour;
  const providerRatePerHour = row.providerRatePerHour ?? row.provider_rate_per_hour;
  const businessPartnerFlatPerHour = row.businessPartnerFlatPerHour ?? row.business_partner_flat_per_hour;
  const effectiveFrom = row.effectiveFrom ?? row.effective_from;
  if (!serviceType || customerRatePerHour === undefined || providerRatePerHour === undefined) {
    throw Errors.badRequest('VALIDATION', 'serviceType, customerRatePerHour and providerRatePerHour are required');
  }
  const effDate = effectiveFrom || localToday();

  // An omitted partner rate carries forward; it does not become zero.
  //
  // `businessPartnerFlatPerHour || 0` meant any caller updating only the
  // customer and provider rates silently wiped what business partners earn on
  // that service -- their revenue page then showed hours worked and nothing
  // earned, with nothing to say why. Zero is only used when there is no
  // previous rate to keep.
  let partnerFlat = businessPartnerFlatPerHour;
  if (partnerFlat === undefined || partnerFlat === null) {
    const [previous] = await query(
      `SELECT business_partner_flat_per_hour AS rate
       FROM revenue_sharing_config
       WHERE service_type = ?
       ORDER BY effective_from DESC
       LIMIT 1`,
      [serviceType]
    );
    partnerFlat = previous ? Number(previous.rate) : 0;
  }

  await query(
    `INSERT INTO revenue_sharing_config (service_type, customer_rate_per_hour, provider_rate_per_hour, business_partner_flat_per_hour, effective_from)
     VALUES (?, ?, ?, ?, ?)
     ON DUPLICATE KEY UPDATE customer_rate_per_hour = VALUES(customer_rate_per_hour),
       provider_rate_per_hour = VALUES(provider_rate_per_hour), business_partner_flat_per_hour = VALUES(business_partner_flat_per_hour)`,
    [serviceType, customerRatePerHour, providerRatePerHour, partnerFlat, effDate]
  );
  return { serviceType, effectiveFrom: effDate };
}

export const putRevenueSharing = asyncHandler(async (req, res) => {
  // admin-portal saves the whole editable table at once as { items: [...] };
  // still accept a single flat object for API callers that only update one row.
  const items = Array.isArray(req.body.items) ? req.body.items : [req.body];
  const results = [];
  for (const item of items) {
    results.push(await upsertRevenueSharingRow(item));
  }
  await req.audit('AdminUpdateRevenueSharing', 'UPDATE', { serviceTypes: results.map((r) => r.serviceType) });
  const rows = await query(
    `SELECT rsc.* FROM revenue_sharing_config rsc
     INNER JOIN (SELECT service_type, MAX(effective_from) AS maxDate FROM revenue_sharing_config GROUP BY service_type) latest
       ON latest.service_type = rsc.service_type AND latest.maxDate = rsc.effective_from
     ORDER BY rsc.service_type`
  );
  res.json({ revenueSharing: rows });
});

// ---------------------------------------------------------------------
// TIME BANK CONFIG — points-per-hour, per service, per application year
// ("Configuration: Time Bank — Provision for define points per hour for
// each service with application year", e.g. Companion 250 pts/hr, 2026)
// ---------------------------------------------------------------------

export const getTimeBankConfig = asyncHandler(async (req, res) => {
  const rows = await query('SELECT * FROM time_bank_config ORDER BY application_year DESC, service_type ASC');
  res.json({ timeBankConfig: rows });
});

async function upsertTimeBankRow(row, adminId) {
  const serviceType = row.serviceType ?? row.service_type;
  const pointsPerHour = row.pointsPerHour ?? row.points_per_hour;
  const applicationYear = row.applicationYear ?? row.application_year;
  if (!serviceType || pointsPerHour === undefined || !applicationYear) {
    throw Errors.badRequest('VALIDATION', 'serviceType, pointsPerHour and applicationYear are required');
  }
  await query(
    `INSERT INTO time_bank_config (service_type, points_per_hour, application_year, updated_by)
     VALUES (?, ?, ?, ?)
     ON DUPLICATE KEY UPDATE points_per_hour = VALUES(points_per_hour), updated_by = VALUES(updated_by)`,
    [serviceType, pointsPerHour, applicationYear, adminId]
  );
  return { serviceType, applicationYear };
}

export const putTimeBankConfig = asyncHandler(async (req, res) => {
  // Same batch-save UX as revenue sharing: admin-portal sends the whole
  // editable table at once as { items: [...] }.
  const items = Array.isArray(req.body.items) ? req.body.items : [req.body];
  const results = [];
  for (const item of items) {
    results.push(await upsertTimeBankRow(item, adminId(req)));
  }
  await req.audit('AdminUpdateTimeBankConfig', 'UPDATE', { rows: results });
  const rows = await query('SELECT * FROM time_bank_config ORDER BY application_year DESC, service_type ASC');
  res.json({ timeBankConfig: rows });
});

// ---------------------------------------------------------------------
// BROADCAST
// ---------------------------------------------------------------------

/**
 * Who would this reach? Asked while the form is being filled in.
 *
 * Exists so nobody finds out that "Pune" means two people by sending to them.
 * It resolves exactly what createBroadcast would and writes nothing.
 */
export const previewBroadcast = asyncHandler(async (req, res) => {
  const targeting = parseTargeting(req.body);
  const recipients = await resolveRecipients(targeting);

  res.json({
    total: recipients.length,
    customers: recipients.filter((r) => r.userType === 'customer').length,
    providers: recipients.filter((r) => r.userType === 'provider').length,
    // Enough to recognise who this is, not the whole list: a preview of
    // fourteen thousand names helps nobody and is slow to send.
    sample: recipients.slice(0, 12).map((r) => ({ userType: r.userType, name: r.name })),
  });
});

/** Cities that actually have somebody in them, for the console's picker. */
export const broadcastCities = asyncHandler(async (req, res) => {
  res.json({ cities: await availableCities() });
});

export const createBroadcast = asyncHandler(async (req, res) => {
  const { title, message, imageUrl } = req.body;
  if (!title || !message) throw Errors.badRequest('VALIDATION', 'title and message are required');

  const targeting = parseTargeting(req.body);
  const recipients = await resolveRecipients(targeting);

  // Refuse rather than record a broadcast that reaches nobody. It is almost
  // always a filter that matched nothing -- a city with no active accounts, or
  // a hand-picked list of people who have since been blocked -- and a silent
  // "sent!" for zero people is worse than an error.
  if (recipients.length === 0) {
    throw Errors.unprocessable(
      'NO_RECIPIENTS',
      'Nobody matches that. Check the city or the people you picked — blocked accounts are never included.'
    );
  }

  const result = await query(
    `INSERT INTO broadcast_messages
       (title, message_text, image_url, target_audience, target_cities, target_pincodes,
        target_explicit, sent_by)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      title,
      message,
      imageUrl || null,
      targeting.audience,
      targeting.cities.length ? JSON.stringify(targeting.cities) : null,
      targeting.pincodes.length ? JSON.stringify(targeting.pincodes) : null,
      targeting.explicit ? 1 : 0,
      adminId(req),
    ]
  );
  const broadcastId = result.insertId;

  // The delivery that actually happens. One row per person, which their app
  // reads back — this is what makes a broadcast arrive without FCM, an SMS
  // bill or any account anywhere.
  //
  // One statement rather than a loop: sixty recipients was sixty round trips
  // to a database in another availability zone.
  await query(
    `INSERT INTO broadcast_recipients (broadcast_id, user_type, user_id) VALUES
     ${recipients.map(() => '(?, ?, ?)').join(', ')}`,
    recipients.flatMap((r) => [broadcastId, r.userType, r.userId])
  );

  // Push is the *second* channel, and still a stub until PUSH_PROVIDER=fcm.
  // Its failure no longer means the broadcast reached nobody.
  const fanout = await push.notifyMany(recipients, {
    title,
    body: message,
    data: { type: 'broadcast', broadcastId, imageUrl: imageUrl || '' },
  });

  await query('UPDATE broadcast_messages SET recipient_count = ?, delivered_count = ? WHERE id = ?', [
    recipients.length, recipients.length, broadcastId,
  ]);

  await req.audit('AdminBroadcast', 'CREATE', {
    broadcastId,
    audience: targeting.audience,
    cities: targeting.cities,
    pincodes: targeting.pincodes,
    explicit: targeting.explicit,
    recipients: recipients.length,
    pushed: fanout.sent,
  });

  res.status(201).json({
    broadcastId,
    recipients: recipients.length,
    // Everyone has it in their app. `pushed` is the separate question of
    // whether a phone also buzzed, which needs FCM configured.
    delivered: recipients.length,
    pushed: fanout.sent,
    channel: fanout.provider,
    message: `Sent to ${recipients.length} ${recipients.length === 1 ? 'person' : 'people'}.`,
  });
});

export const listBroadcasts = asyncHandler(async (req, res) => {
  // The admin's name is joined rather than left as a bare id: the history list
  // says "Sent by ...", and an id there tells nobody anything.
  const rows = await query(
    `SELECT b.*, a.name AS sent_by_name
     FROM broadcast_messages b
     LEFT JOIN admin_users a ON a.admin_id = b.sent_by
     ORDER BY b.sent_at DESC
     LIMIT 100`
  );
  res.json({
    broadcasts: rows.map((r) => ({
      ...r,
      sent_by_name: r.sent_by_name || 'Admin',
      recipient_count: Number(r.recipient_count ?? 0),
      delivered_count: Number(r.delivered_count ?? 0),
    })),
  });
});

// ---------------------------------------------------------------------
// LIVE TRACKING
// ---------------------------------------------------------------------

export const trackAllProviders = asyncHandler(async (req, res) => {
  // status and approval_status travel with the position because the console
  // shows them beside each pin; on_active_booking decides whether a pin is
  // blue (out on a job) or green (free). None of the three was being sent, so
  // every provider looked available and the "On active booking" figure was
  // permanently zero.
  const rows = await query(
    `SELECT sp.provider_id, sp.display_id, sp.name, sp.provider_kind,
            sp.current_latitude, sp.current_longitude, sp.current_location_at,
            sp.location_on, sp.status, sp.approval_status,
            EXISTS (
              SELECT 1 FROM bookings b
              WHERE (b.confirmed_provider_id = sp.provider_id OR b.assigned_employee_id = sp.provider_id)
                AND b.status = 'in_progress'
            ) AS on_active_booking
     FROM service_providers sp
     WHERE sp.current_latitude IS NOT NULL
     ORDER BY sp.current_location_at DESC`
  );
  // MySQL returns EXISTS as 1/0; the console wants a boolean.
  for (const r of rows) r.on_active_booking = !!r.on_active_booking;

  // The live map labels each pin with what that provider does, so the
  // expertise has to travel with the position — without it the console
  // crashed on an undefined list rather than simply showing less.
  if (rows.length > 0) {
    const ids = rows.map((r) => r.provider_id);
    const expertise = await query(
      `SELECT provider_id, service_type FROM service_provider_expertise WHERE provider_id IN (${ids.map(() => '?').join(',')})`,
      ids
    );
    const byProvider = expertise.reduce((acc, e) => {
      (acc[e.provider_id] ||= []).push(e.service_type);
      return acc;
    }, {});
    for (const r of rows) r.service_types = byProvider[r.provider_id] || [];
  }

  res.json({ providers: rows });
});

// ---------------------------------------------------------------------
// REPORTS
// ---------------------------------------------------------------------

export const reportsDashboard = asyncHandler(async (req, res) => {
  const byCity = await query(
    // A booking can legitimately have no address row -- someone who books
    // before filling in their profile still has coordinates, just no city --
    // so the bucket is named for what it is rather than dumped in as the
    // literal string "unknown".
    `SELECT COALESCE(ca.city, 'Not recorded') AS city, COALESCE(SUM(s.amount), 0) AS revenue, COUNT(DISTINCT s.booking_id) AS bookings
     FROM booking_service_sessions s
     JOIN bookings b ON b.booking_id = s.booking_id
     LEFT JOIN customer_addresses ca ON ca.id = b.address_id
     WHERE s.end_time_actual IS NOT NULL
     GROUP BY city ORDER BY revenue DESC`
  );
  const byServiceType = await query(
    `SELECT b.service_type, COALESCE(SUM(s.amount), 0) AS revenue, COUNT(DISTINCT s.booking_id) AS bookings
     FROM booking_service_sessions s JOIN bookings b ON b.booking_id = s.booking_id
     WHERE s.end_time_actual IS NOT NULL GROUP BY b.service_type ORDER BY revenue DESC`
  );
  const byProvider = await query(
    `SELECT sp.provider_id, sp.display_id, sp.name, COALESCE(SUM(s.amount), 0) AS revenue, COUNT(DISTINCT s.booking_id) AS bookings
     FROM booking_service_sessions s JOIN service_providers sp ON sp.provider_id = s.provider_id
     WHERE s.end_time_actual IS NOT NULL GROUP BY sp.provider_id ORDER BY revenue DESC LIMIT 50`
  );
  res.json({ byCity, byServiceType, byProvider });
});

const GROWTH_PERIOD_SQL = {
  day: "DATE_FORMAT(created_at, '%Y-%m-%d')",
  week: "CONCAT(YEAR(created_at), '-W', LPAD(WEEK(created_at, 3), 2, '0'))",
  month: "DATE_FORMAT(created_at, '%Y-%m')",
  quarter: "CONCAT(YEAR(created_at), '-Q', QUARTER(created_at))",
  year: "YEAR(created_at)",
};

export const reportsGrowth = asyncHandler(async (req, res) => {
  const period = GROWTH_PERIOD_SQL[req.query.period] ? req.query.period : 'month';
  const bucket = GROWTH_PERIOD_SQL[period];

  const customers = await query(`SELECT ${bucket} AS bucket, COUNT(*) AS count FROM customers GROUP BY bucket ORDER BY bucket DESC LIMIT 24`);
  const providers = await query(`SELECT ${bucket} AS bucket, COUNT(*) AS count FROM service_providers GROUP BY bucket ORDER BY bucket DESC LIMIT 24`);

  res.json({ period, customers, providers });
});

// ---------------------------------------------------------------------
// AUDIT LOG
// ---------------------------------------------------------------------

export const listAuditLog = asyncHandler(async (req, res) => {
  const { userType, userId, formName, from, to, limit } = req.query;
  let sql = 'SELECT * FROM audit_log WHERE 1=1';
  const params = [];
  if (userType) { sql += ' AND user_type = ?'; params.push(userType); }
  if (userId) { sql += ' AND user_id = ?'; params.push(userId); }
  if (formName) { sql += ' AND form_name = ?'; params.push(formName); }
  if (from) { sql += ' AND transaction_date >= ?'; params.push(from); }
  if (to) { sql += ' AND transaction_date <= ?'; params.push(to); }
  sql += ' ORDER BY transaction_date DESC LIMIT ?';
  params.push(Math.min(parseInt(limit, 10) || 100, 1000));
  const rows = await query(sql, params);
  res.json({ auditLog: rows });
});

// ---------------------------------------------------------------------
// ALLOCATE PROVIDER TO A BUSINESS-PARTNER REFERRAL (additive; from the
// MVP requirements doc: "allocate provider to Business-Partner-referred
// customer based on calendar availability")
// ---------------------------------------------------------------------

export const allocateReferral = asyncHandler(async (req, res) => {
  const { id } = req.params; // business_agent_referrals.id
  const [referral] = await query('SELECT * FROM business_agent_referrals WHERE id = ?', [id]);
  if (!referral) throw Errors.notFound('Referral not found');

  const candidates = await findMatchingProviders({
    serviceType: referral.service_type,
    dateFrom: referral.duration_start,
    dateTo: referral.duration_end,
    timeFrom: referral.time_from,
    timeTo: referral.time_to,
    gender: referral.gender || undefined,
  });
  if (candidates.length === 0) throw Errors.conflict('NO_PROVIDER_AVAILABLE', 'No approved, available provider matches this referral');

  const chosen = candidates[0];
  await query('UPDATE business_agent_referrals SET status = "booked" WHERE id = ?', [id]);
  await req.audit('AdminAllocateReferral', 'UPDATE', { referralId: id, providerId: chosen.provider_id });

  res.json({ referralId: Number(id), allocatedProviderId: chosen.provider_id, providerName: chosen.name });
});

// ---------------------------------------------------------------------
// WHERE PEOPLE ARE SIGNING UP FROM
// ---------------------------------------------------------------------

/**
 * Demand by place, for a business launching one city at a time.
 *
 * Sathiyaa serves Ahmedabad. Everyone else who registers is turned away at
 * the door -- and until now that was the end of it: no record that they came,
 * no idea which city to open next. The apps now report where the phone was at
 * sign-up, and this is the read side.
 *
 * Counted separately for customers and providers, because they mean different
 * things. Forty families asking in Surat is a market. Forty carers asking in
 * Surat is a workforce. You need both before opening anywhere.
 */
export const signupPlaces = asyncHandler(async (req, res) => {
  const sql = (table, idCol) => `
    SELECT COALESCE(NULLIF(TRIM(signup_city), ''), '(not given)') AS city,
           COALESCE(NULLIF(TRIM(signup_state), ''), '') AS state,
           COUNT(*) AS total,
           SUM(CASE WHEN signup_in_service_area = 1 THEN 1 ELSE 0 END) AS inside,
           MAX(signup_place_at) AS latest
      FROM ${table}
     WHERE signup_place_at IS NOT NULL
     GROUP BY city, state`;

  const [customerRows, providerRows] = await Promise.all([
    query(sql('customers', 'customer_id')),
    query(sql('service_providers', 'provider_id')),
  ]);

  // One row per place, with both counts on it -- a place that has customers
  // and no carers is the interesting case, and two separate lists hide it.
  const byPlace = new Map();
  const key = (r) => `${r.city}|${r.state}`;
  const slot = (r) => {
    const k = key(r);
    if (!byPlace.has(k)) {
      byPlace.set(k, {
        city: r.city, state: r.state,
        customers: 0, customersInside: 0,
        providers: 0, providersInside: 0,
        latest: null,
      });
    }
    return byPlace.get(k);
  };
  for (const r of customerRows) {
    const s = slot(r);
    s.customers = Number(r.total);
    s.customersInside = Number(r.inside);
    if (!s.latest || (r.latest && r.latest > s.latest)) s.latest = r.latest;
  }
  for (const r of providerRows) {
    const s = slot(r);
    s.providers = Number(r.total);
    s.providersInside = Number(r.inside);
    if (!s.latest || (r.latest && r.latest > s.latest)) s.latest = r.latest;
  }

  const places = [...byPlace.values()].sort(
    (a, b) => (b.customers + b.providers) - (a.customers + a.providers)
  );

  // How many never answered. A large number here means the location prompt is
  // being refused, which makes every figure above an undercount -- so it is
  // reported rather than quietly left out of the denominator.
  const [[cUnknown], [pUnknown]] = await Promise.all([
    query('SELECT COUNT(*) AS n FROM customers WHERE signup_place_at IS NULL'),
    query('SELECT COUNT(*) AS n FROM service_providers WHERE signup_place_at IS NULL AND provider_kind <> "org_employee"'),
  ]);

  const area = await getServiceArea();
  res.json({
    serviceArea: { city: area.city, state: area.state, radiusKm: area.radiusKm, enabled: area.enabled },
    places,
    notReported: { customers: Number(cUnknown.n), providers: Number(pUnknown.n) },
  });
});
