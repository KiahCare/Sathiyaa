import { query } from '../db/pool.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { Errors } from '../utils/apiError.js';
import { createOrder, verifyPayment } from '../integrations/payment.js';
import { normaliseGender, normaliseContactModes } from '../utils/enums.js';
import { raiseSosAlert } from '../services/sosService.js';
import { recordSignupPlace } from '../services/serviceArea.js';
import { registrationStanding, transactionTypeFor } from '../services/registrationFee.js';

const customerId = (req) => req.user.id;

// "Data limit of 5 records for all Vitals, Medication, Surgery, and Allergy"
// (requirements doc). Vitals is capped at 5 total across all vital types
// combined (BP/SpO2/Pulse/Glucose share one pool), same as Family's existing
// 5-contact cap — not 5 per type, which would defeat the point of a hard
// limit. All four counts only the customer's live (non-deleted) rows.
const PROFILE_SECTION_RECORD_LIMIT = 5;

async function assertUnderRecordLimit(table, custId, label) {
  const [{ c }] = await query(`SELECT COUNT(*) AS c FROM ${table} WHERE customer_id = ? AND deleted_at IS NULL`, [custId]);
  if (c >= PROFILE_SECTION_RECORD_LIMIT) {
    throw Errors.unprocessable('DATA_LIMIT', `You've reached the maximum of ${PROFILE_SECTION_RECORD_LIMIT} ${label} records. Delete one before adding another.`);
  }
}

// "Provision to link customer with Service Provider (provision to link up
// to 10 service providers)" — a customer's favorites/regulars list.
const LINKED_PROVIDER_LIMIT = 10;

// ---------------------------------------------------------------------
// PROFILE
// ---------------------------------------------------------------------

export const getMe = asyncHandler(async (req, res) => {
  const [customer] = await query('SELECT * FROM customers WHERE customer_id = ?', [customerId(req)]);
  if (!customer) throw Errors.notFound('Customer not found');
  const addresses = await query('SELECT * FROM customer_addresses WHERE customer_id = ?', [customerId(req)]);
  // What the fee actually is right now, not what the app was built with.
  //
  // The amount lives in app_configuration and an admin can change it; without
  // this the card offered "Pay 499" and the server then charged whatever the
  // console said, which is the one place a mismatch is unforgivable. Zero is
  // a valid answer and means the card is not shown at all.
  //
  // For somebody who has already paid, the amount reported is the RENEWAL
  // rate -- what they would pay next -- rather than the joining rate they
  // will never pay again.
  const standing = await registrationStanding({
    kind: 'customer',
    referenceId: customer.customer_id,
    alreadyPaid: !!customer.registration_fee_paid,
  });
  res.json({
    ...serializeCustomer(customer),
    registrationFeeAmount: standing.amount,
    registrationIsRenewal: standing.isRenewal,
    registrationRenewalDue: standing.canPay && standing.isRenewal,
    registrationPaidAt: standing.paidAt,
    registrationRenewsAt: standing.renewsAt,
    addresses,
  });
});

export const updateMe = asyncHandler(async (req, res) => {
  const b = req.body;
  const fields = [];
  const values = [];
  const map = {
    name: 'name', photoUrl: 'photo_url', dob: 'dob', gender: 'gender', bloodGroup: 'blood_group',
    email: 'email', heightCm: 'height_cm', weightKg: 'weight_kg',
    preferredCommMode: 'preferred_comm_mode', preferredCommTimeframe: 'preferred_comm_timeframe',
  };
  // Checked here rather than left to the columns: an unrecognised ENUM or SET
  // member makes MySQL reject the whole UPDATE, which surfaces in the app as
  // an unhelpful "something went wrong" with no clue which field was at fault.
  const normalisedModes = normaliseContactModes(b.preferredCommMode);
  if (normalisedModes !== undefined) b.preferredCommMode = normalisedModes;
  if (b.gender !== undefined) b.gender = normaliseGender(b.gender);

  for (const [k, col] of Object.entries(map)) {
    if (b[k] !== undefined) { fields.push(`${col} = ?`); values.push(b[k]); }
  }
  if (b.preferredLanguages !== undefined) { fields.push('preferred_languages = ?'); values.push(JSON.stringify(b.preferredLanguages)); }
  if (fields.length === 0) throw Errors.badRequest('VALIDATION', 'No updatable fields provided');

  values.push(customerId(req));
  await query(`UPDATE customers SET ${fields.join(', ')} WHERE customer_id = ?`, values);
  await req.audit('CustomerUpdateProfile', 'UPDATE');

  const [customer] = await query('SELECT * FROM customers WHERE customer_id = ?', [customerId(req)]);
  res.json(serializeCustomer(customer));
});

function serializeCustomer(c) {
  return {
    customerId: c.customer_id,
    displayId: c.display_id,
    name: c.name,
    photoUrl: c.photo_url,
    dob: c.dob,
    gender: c.gender,
    bloodGroup: c.blood_group,
    email: c.email,
    mobileNumber: c.mobile_number,
    preferredLanguages: c.preferred_languages,
    heightCm: c.height_cm,
    weightKg: c.weight_kg,
    bmi: c.bmi,
    preferredCommMode: c.preferred_comm_mode,
    preferredCommTimeframe: c.preferred_comm_timeframe,
    registrationFeePaid: !!c.registration_fee_paid,
    // The code the customer typed in, and where they registered from. Both
    // used to live only in the app's memory, which meant a referral was lost
    // the moment the app was closed and the service-area gate had to re-ask
    // for a location fix on every launch.
    referralCode: c.referred_by_code,
    signupCity: c.signup_city,
    signupState: c.signup_state,
    signupInServiceArea:
      c.signup_in_service_area === null || c.signup_in_service_area === undefined
        ? null
        : !!c.signup_in_service_area,
    status: c.status,
    termsPrivacyAcceptedAt: c.terms_privacy_accepted_at,
    ratingAvg: c.rating_avg === null || c.rating_avg === undefined ? 0 : Number(c.rating_avg),
    ratingCount: c.rating_count ?? 0,
    createdAt: c.created_at,
  };
}

// ---------------------------------------------------------------------
// TERMS & PRIVACY POLICY ACCEPTANCE
// ---------------------------------------------------------------------
// Gates the "Continue" button at the end of registration (and can be
// re-called if terms are ever re-issued). Recorded once as a timestamp
// rather than a boolean so support/audit can see exactly when a customer
// agreed to the current Terms & Conditions / Privacy Policy.

export const acceptTerms = asyncHandler(async (req, res) => {
  if (req.body.accepted !== true) {
    throw Errors.badRequest('VALIDATION', 'accepted must be true to record agreement');
  }
  await query('UPDATE customers SET terms_privacy_accepted_at = NOW() WHERE customer_id = ?', [customerId(req)]);
  await req.audit('CustomerAcceptTerms', 'UPDATE');
  const [customer] = await query('SELECT terms_privacy_accepted_at FROM customers WHERE customer_id = ?', [customerId(req)]);
  res.json({ accepted: true, termsPrivacyAcceptedAt: customer.terms_privacy_accepted_at });
});

// ---------------------------------------------------------------------
// LINKED (FAVORITE) SERVICE PROVIDERS — capped at 10
// ---------------------------------------------------------------------

function serializeLinkedProvider(row) {
  return {
    linkId: row.id,
    providerId: row.provider_id,
    name: row.name,
    photoUrl: row.photo_url,
    providerKind: row.provider_kind,
    hourlyRate: row.hourly_rate === null ? null : Number(row.hourly_rate),
    noFees: !!row.no_fees,
    status: row.status,
    approvalStatus: row.approval_status,
    linkedAt: row.created_at,
  };
}

export const listLinkedProviders = asyncHandler(async (req, res) => {
  const rows = await query(
    `SELECT l.id, l.created_at, p.provider_id, p.name, p.photo_url, p.provider_kind, p.hourly_rate, p.no_fees, p.status, p.approval_status
     FROM customer_provider_links l
     JOIN service_providers p ON p.provider_id = l.provider_id
     WHERE l.customer_id = ?
     ORDER BY l.created_at DESC`,
    [customerId(req)]
  );
  res.json({ linkedProviders: rows.map(serializeLinkedProvider) });
});

export const addLinkedProvider = asyncHandler(async (req, res) => {
  const { providerId } = req.body;
  if (!providerId) throw Errors.badRequest('VALIDATION', 'providerId is required');

  const [provider] = await query('SELECT provider_id FROM service_providers WHERE provider_id = ?', [providerId]);
  if (!provider) throw Errors.notFound('Service provider not found');

  const [{ c }] = await query('SELECT COUNT(*) AS c FROM customer_provider_links WHERE customer_id = ?', [customerId(req)]);
  if (c >= LINKED_PROVIDER_LIMIT) {
    throw Errors.unprocessable('DATA_LIMIT', `You can link up to ${LINKED_PROVIDER_LIMIT} service providers. Remove one before adding another.`);
  }

  try {
    const result = await query('INSERT INTO customer_provider_links (customer_id, provider_id) VALUES (?, ?)', [customerId(req), providerId]);
    await req.audit('CustomerLinkedProviders', 'CREATE', { providerId });
    res.status(201).json({ id: result.insertId });
  } catch (err) {
    if (err && err.code === 'ER_DUP_ENTRY') throw Errors.conflict('ALREADY_LINKED', 'This service provider is already linked');
    throw err;
  }
});

export const deleteLinkedProvider = asyncHandler(async (req, res) => {
  const { providerId } = req.params;
  const result = await query('DELETE FROM customer_provider_links WHERE customer_id = ? AND provider_id = ?', [customerId(req), providerId]);
  if (result.affectedRows === 0) throw Errors.notFound('Linked provider not found');
  await req.audit('CustomerLinkedProviders', 'DELETE', { providerId });
  res.json({ deleted: true });
});

// ---------------------------------------------------------------------
// ADDRESSES
// ---------------------------------------------------------------------

export const putAddresses = asyncHandler(async (req, res) => {
  const { primary, secondary } = req.body;
  if (!primary && !secondary) throw Errors.badRequest('VALIDATION', 'At least the primary address is required');

  for (const [type, addr] of [['primary', primary], ['secondary', secondary]]) {
    if (!addr) continue;
    await query(
      `INSERT INTO customer_addresses (customer_id, address_type, line1, line2, city, state, pincode, latitude, longitude)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE line1 = VALUES(line1), line2 = VALUES(line2), city = VALUES(city),
         state = VALUES(state), pincode = VALUES(pincode), latitude = VALUES(latitude), longitude = VALUES(longitude)`,
      [customerId(req), type, addr.line1, addr.line2 || null, addr.city || null, addr.state || null, addr.pincode || null, addr.latitude || null, addr.longitude || null]
    );
  }
  await req.audit('CustomerAddresses', 'UPDATE');
  const addresses = await query('SELECT * FROM customer_addresses WHERE customer_id = ?', [customerId(req)]);
  res.json({ addresses });
});

// ---------------------------------------------------------------------
// VITALS
// ---------------------------------------------------------------------

export const listVitals = asyncHandler(async (req, res) => {
  const { type, from, to } = req.query;
  let sql = 'SELECT * FROM customer_vitals WHERE customer_id = ? AND deleted_at IS NULL';
  const params = [customerId(req)];
  if (type) { sql += ' AND vital_type = ?'; params.push(type); }
  if (from) { sql += ' AND recorded_at >= ?'; params.push(from); }
  if (to) { sql += ' AND recorded_at <= ?'; params.push(to); }
  sql += ' ORDER BY recorded_at ASC';
  const rows = await query(sql, params);
  res.json({ vitals: rows });
});

export const addVital = asyncHandler(async (req, res) => {
  const { vitalType, valuePrimary, valueSecondary, recordedAt } = req.body;
  if (!vitalType || valuePrimary === undefined || !recordedAt) {
    throw Errors.badRequest('VALIDATION', 'vitalType, valuePrimary and recordedAt are required');
  }
  await assertUnderRecordLimit('customer_vitals', customerId(req), 'vitals');
  const result = await query(
    'INSERT INTO customer_vitals (customer_id, vital_type, value_primary, value_secondary, recorded_at) VALUES (?, ?, ?, ?, ?)',
    [customerId(req), vitalType, valuePrimary, valueSecondary || null, recordedAt]
  );
  await req.audit('CustomerVitals', 'CREATE', { vitalType });
  res.status(201).json({ id: result.insertId });
});

export const updateVital = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { vitalType, valuePrimary, valueSecondary, recordedAt } = req.body;
  const fields = [];
  const values = [];
  if (vitalType !== undefined) { fields.push('vital_type = ?'); values.push(vitalType); }
  if (valuePrimary !== undefined) { fields.push('value_primary = ?'); values.push(valuePrimary); }
  if (valueSecondary !== undefined) { fields.push('value_secondary = ?'); values.push(valueSecondary); }
  if (recordedAt !== undefined) { fields.push('recorded_at = ?'); values.push(recordedAt); }
  if (fields.length === 0) throw Errors.badRequest('VALIDATION', 'No updatable fields provided');
  values.push(id, customerId(req));
  const result = await query(
    `UPDATE customer_vitals SET ${fields.join(', ')} WHERE id = ? AND customer_id = ? AND deleted_at IS NULL`,
    values
  );
  if (result.affectedRows === 0) throw Errors.notFound('Vital reading not found');
  await req.audit('CustomerVitals', 'UPDATE', { id });
  res.json({ updated: true });
});

export const deleteVital = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const result = await query(
    'UPDATE customer_vitals SET deleted_at = NOW() WHERE id = ? AND customer_id = ? AND deleted_at IS NULL',
    [id, customerId(req)]
  );
  if (result.affectedRows === 0) throw Errors.notFound('Vital reading not found');
  await req.audit('CustomerVitals', 'DELETE', { id });
  res.json({ deleted: true });
});

// ---------------------------------------------------------------------
// MEDICATIONS
// ---------------------------------------------------------------------

export const listMedications = asyncHandler(async (req, res) => {
  const rows = await query(
    'SELECT * FROM customer_medications WHERE customer_id = ? AND deleted_at IS NULL ORDER BY created_at DESC',
    [customerId(req)]
  );
  res.json({ medications: rows });
});

export const addMedication = asyncHandler(async (req, res) => {
  const { medicineName, frequency, prescriptionUrl } = req.body;
  if (!medicineName || !frequency) throw Errors.badRequest('VALIDATION', 'medicineName and frequency are required');
  await assertUnderRecordLimit('customer_medications', customerId(req), 'medication');
  const result = await query(
    'INSERT INTO customer_medications (customer_id, medicine_name, frequency, prescription_url) VALUES (?, ?, ?, ?)',
    [customerId(req), medicineName, frequency, prescriptionUrl || null]
  );
  await req.audit('CustomerMedications', 'CREATE', { medicineName });
  res.status(201).json({ id: result.insertId });
});

export const updateMedication = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { medicineName, frequency, prescriptionUrl, active } = req.body;
  const fields = [];
  const values = [];
  if (medicineName !== undefined) { fields.push('medicine_name = ?'); values.push(medicineName); }
  if (frequency !== undefined) { fields.push('frequency = ?'); values.push(frequency); }
  if (prescriptionUrl !== undefined) { fields.push('prescription_url = ?'); values.push(prescriptionUrl); }
  if (active !== undefined) { fields.push('active = ?'); values.push(active); }
  if (fields.length === 0) throw Errors.badRequest('VALIDATION', 'No updatable fields provided');
  values.push(id, customerId(req));
  const result = await query(
    `UPDATE customer_medications SET ${fields.join(', ')} WHERE id = ? AND customer_id = ? AND deleted_at IS NULL`,
    values
  );
  if (result.affectedRows === 0) throw Errors.notFound('Medication not found');
  await req.audit('CustomerMedications', 'UPDATE', { id });
  res.json({ updated: true });
});

export const deleteMedication = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const result = await query(
    'UPDATE customer_medications SET deleted_at = NOW() WHERE id = ? AND customer_id = ? AND deleted_at IS NULL',
    [id, customerId(req)]
  );
  if (result.affectedRows === 0) throw Errors.notFound('Medication not found');
  await req.audit('CustomerMedications', 'DELETE', { id });
  res.json({ deleted: true });
});

// ---------------------------------------------------------------------
// SURGERIES
// ---------------------------------------------------------------------

export const listSurgeries = asyncHandler(async (req, res) => {
  const rows = await query(
    'SELECT * FROM customer_surgeries WHERE customer_id = ? AND deleted_at IS NULL ORDER BY surgery_date DESC',
    [customerId(req)]
  );
  res.json({ surgeries: rows });
});

export const addSurgery = asyncHandler(async (req, res) => {
  const { surgeryName, surgeryDate } = req.body;
  if (!surgeryName || !surgeryDate) throw Errors.badRequest('VALIDATION', 'surgeryName and surgeryDate are required');
  await assertUnderRecordLimit('customer_surgeries', customerId(req), 'surgery');
  const result = await query('INSERT INTO customer_surgeries (customer_id, surgery_name, surgery_date) VALUES (?, ?, ?)', [
    customerId(req), surgeryName, surgeryDate,
  ]);
  await req.audit('CustomerSurgeries', 'CREATE', { surgeryName });
  res.status(201).json({ id: result.insertId });
});

export const updateSurgery = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { surgeryName, surgeryDate } = req.body;
  const fields = [];
  const values = [];
  if (surgeryName !== undefined) { fields.push('surgery_name = ?'); values.push(surgeryName); }
  if (surgeryDate !== undefined) { fields.push('surgery_date = ?'); values.push(surgeryDate); }
  if (fields.length === 0) throw Errors.badRequest('VALIDATION', 'No updatable fields provided');
  values.push(id, customerId(req));
  const result = await query(
    `UPDATE customer_surgeries SET ${fields.join(', ')} WHERE id = ? AND customer_id = ? AND deleted_at IS NULL`,
    values
  );
  if (result.affectedRows === 0) throw Errors.notFound('Surgery not found');
  await req.audit('CustomerSurgeries', 'UPDATE', { id });
  res.json({ updated: true });
});

export const deleteSurgery = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const result = await query(
    'UPDATE customer_surgeries SET deleted_at = NOW() WHERE id = ? AND customer_id = ? AND deleted_at IS NULL',
    [id, customerId(req)]
  );
  if (result.affectedRows === 0) throw Errors.notFound('Surgery not found');
  await req.audit('CustomerSurgeries', 'DELETE', { id });
  res.json({ deleted: true });
});

// ---------------------------------------------------------------------
// ALLERGIES
// ---------------------------------------------------------------------

export const listAllergies = asyncHandler(async (req, res) => {
  const rows = await query(
    'SELECT * FROM customer_allergies WHERE customer_id = ? AND deleted_at IS NULL ORDER BY created_at DESC',
    [customerId(req)]
  );
  res.json({ allergies: rows });
});

export const addAllergy = asyncHandler(async (req, res) => {
  const { allergyName, onsetDate, status } = req.body;
  if (!allergyName) throw Errors.badRequest('VALIDATION', 'allergyName is required');
  await assertUnderRecordLimit('customer_allergies', customerId(req), 'allergy');
  const result = await query('INSERT INTO customer_allergies (customer_id, allergy_name, onset_date, status) VALUES (?, ?, ?, ?)', [
    customerId(req), allergyName, onsetDate || null, status || 'active',
  ]);
  await req.audit('CustomerAllergies', 'CREATE', { allergyName });
  res.status(201).json({ id: result.insertId });
});

export const updateAllergy = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { allergyName, onsetDate, status } = req.body;
  const fields = [];
  const values = [];
  if (allergyName !== undefined) { fields.push('allergy_name = ?'); values.push(allergyName); }
  if (onsetDate !== undefined) { fields.push('onset_date = ?'); values.push(onsetDate); }
  if (status !== undefined) { fields.push('status = ?'); values.push(status); }
  if (fields.length === 0) throw Errors.badRequest('VALIDATION', 'No updatable fields provided');
  values.push(id, customerId(req));
  const result = await query(
    `UPDATE customer_allergies SET ${fields.join(', ')} WHERE id = ? AND customer_id = ? AND deleted_at IS NULL`,
    values
  );
  if (result.affectedRows === 0) throw Errors.notFound('Allergy not found');
  await req.audit('CustomerAllergies', 'UPDATE', { id });
  res.json({ updated: true });
});

export const deleteAllergy = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const result = await query(
    'UPDATE customer_allergies SET deleted_at = NOW() WHERE id = ? AND customer_id = ? AND deleted_at IS NULL',
    [id, customerId(req)]
  );
  if (result.affectedRows === 0) throw Errors.notFound('Allergy not found');
  await req.audit('CustomerAllergies', 'DELETE', { id });
  res.json({ deleted: true });
});

// ---------------------------------------------------------------------
// INSURANCE
// ---------------------------------------------------------------------

export const listInsurance = asyncHandler(async (req, res) => {
  const rows = await query('SELECT * FROM customer_insurance WHERE customer_id = ? ORDER BY created_at DESC', [customerId(req)]);
  res.json({ insurance: rows });
});

export const addInsurance = asyncHandler(async (req, res) => {
  const { insuredWith, policyNumber, startDate, endDate } = req.body;
  if (!insuredWith || !policyNumber || !startDate || !endDate) {
    throw Errors.badRequest('VALIDATION', 'insuredWith, policyNumber, startDate and endDate are required');
  }
  const result = await query(
    'INSERT INTO customer_insurance (customer_id, insured_with, policy_number, start_date, end_date) VALUES (?, ?, ?, ?, ?)',
    [customerId(req), insuredWith, policyNumber, startDate, endDate]
  );
  await req.audit('CustomerInsurance', 'CREATE', { insuredWith });
  res.status(201).json({ id: result.insertId });
});

// ---------------------------------------------------------------------
// FAMILY MEMBERS
// ---------------------------------------------------------------------


// ---------------------------------------------------------------------
// EMERGENCY
// ---------------------------------------------------------------------

/// Raise an emergency alert.
///
/// Deliberately tolerant about its input: an emergency is the worst possible
/// moment to reject a request for a missing field. Location, note and booking
/// are all optional, and an alert with none of them still gets raised and
/// still reaches the family on the account.
export const raiseSos = asyncHandler(async (req, res) => {
  const [customer] = await query('SELECT * FROM customers WHERE customer_id = ?', [customerId(req)]);
  if (!customer) throw Errors.notFound('Customer not found');

  const result = await raiseSosAlert({
    customer,
    latitude: req.body.latitude ?? null,
    longitude: req.body.longitude ?? null,
    addressText: req.body.addressText ?? null,
    note: req.body.note ?? null,
    bookingId: req.body.bookingId ?? null,
  });

  await req.audit('CustomerSOS', 'CREATE', {
    alertId: result.alertId,
    delivery: result.delivery,
    notified: result.notifiedCount,
  });

  // 201 rather than 200: something was created, and the id is what lets the
  // app show the alert afterwards.
  res.status(201).json(result);
});

/// This customer's own alerts, newest first.
export const listMySos = asyncHandler(async (req, res) => {
  const rows = await query(
    `SELECT id, latitude, longitude, address_text AS addressText, booking_id AS bookingId,
            note, delivery, notified_count AS notifiedCount, recipients,
            acknowledged_at AS acknowledgedAt, resolution, created_at AS createdAt
       FROM sos_alerts
      WHERE customer_id = ?
      ORDER BY created_at DESC
      LIMIT 50`,
    [customerId(req)]
  );
  res.json({ alerts: rows });
});

export const listFamily = asyncHandler(async (req, res) => {
  const rows = await query(
    'SELECT * FROM customer_family_members WHERE customer_id = ? AND deleted_at IS NULL ORDER BY created_at ASC',
    [customerId(req)]
  );
  res.json({ family: rows });
});

export const addFamily = asyncHandler(async (req, res) => {
  // dateOfBirth and notes are optional and only matter when a visit is booked
  // for this person rather than for the account holder: the carer needs to know
  // how old they are and anything worth knowing before they knock.
  const { name, relationship, contactNumber, dateOfBirth, notes } = req.body;
  if (!name || !relationship || !contactNumber) {
    throw Errors.badRequest('VALIDATION', 'name, relationship and contactNumber are required');
  }
  await assertUnderRecordLimit('customer_family_members', customerId(req), 'family contact');
  const result = await query(
    `INSERT INTO customer_family_members (customer_id, name, relationship, contact_number, date_of_birth, notes)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [customerId(req), name, relationship, contactNumber, dateOfBirth || null, notes || null]
  );
  await req.audit('CustomerFamily', 'CREATE', { name });
  res.status(201).json({ id: result.insertId });
});

export const updateFamily = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { name, relationship, contactNumber, dateOfBirth, notes } = req.body;
  const fields = [];
  const values = [];
  if (name !== undefined) { fields.push('name = ?'); values.push(name); }
  if (relationship !== undefined) { fields.push('relationship = ?'); values.push(relationship); }
  if (dateOfBirth !== undefined) { fields.push('date_of_birth = ?'); values.push(dateOfBirth || null); }
  if (notes !== undefined) { fields.push('notes = ?'); values.push(notes || null); }
  if (contactNumber !== undefined) { fields.push('contact_number = ?'); values.push(contactNumber); }
  if (fields.length === 0) throw Errors.badRequest('VALIDATION', 'No updatable fields provided');
  values.push(id, customerId(req));
  const result = await query(
    `UPDATE customer_family_members SET ${fields.join(', ')} WHERE id = ? AND customer_id = ? AND deleted_at IS NULL`,
    values
  );
  if (result.affectedRows === 0) throw Errors.notFound('Family member not found');
  await req.audit('CustomerFamily', 'UPDATE', { id });
  res.json({ updated: true });
});

// Soft delete: the row is kept (deleted_at set) so its audit trail is never
// lost, but it's excluded from listFamily and from the min-1-member count.
export const deleteFamily = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const count = await query(
    'SELECT COUNT(*) AS c FROM customer_family_members WHERE customer_id = ? AND deleted_at IS NULL',
    [customerId(req)]
  );
  if (count[0].c <= 1) throw Errors.unprocessable('MIN_FAMILY_MEMBER', 'At least 1 family member is required');
  const result = await query(
    'UPDATE customer_family_members SET deleted_at = NOW() WHERE id = ? AND customer_id = ? AND deleted_at IS NULL',
    [id, customerId(req)]
  );
  if (result.affectedRows === 0) throw Errors.notFound('Family member not found');
  await req.audit('CustomerFamily', 'DELETE', { id });
  res.json({ deleted: true });
});

// ---------------------------------------------------------------------
// REGISTRATION PAYMENT
// ---------------------------------------------------------------------

export const registrationPayment = asyncHandler(async (req, res) => {
  const [customer] = await query('SELECT * FROM customers WHERE customer_id = ?', [customerId(req)]);
  if (!customer) throw Errors.notFound('Customer not found');
  const standing = await registrationStanding({
    kind: 'customer',
    referenceId: customer.customer_id,
    alreadyPaid: !!customer.registration_fee_paid,
  });
  if (!standing.canPay) {
    // Nothing lapses. Being inside the paid year is not an error -- it is the
    // normal state of a paying customer -- so the refusal says when the next
    // one is due rather than only that this one was refused.
    throw Errors.conflict(
      'ALREADY_PAID',
      standing.renewsAt
        ? `Already paid. The next renewal is due on ${standing.renewsAt.toISOString().slice(0, 10)}.`
        : 'Registration fee already paid.'
    );
  }

  const { amount, isRenewal } = standing;
  const txnType = transactionTypeFor('customer', isRenewal);

  // A fee of zero is a decision, not a payment.
  //
  // Setting the annual fee to 0 in the console used to send a zero-rupee order
  // to the gateway, which refuses it -- Razorpay's minimum is one rupee -- so
  // "free" was the one price the product could not charge. Waive it here
  // instead: the account activates, a transaction row is still written so the
  // ledger has no gap, and the app is told not to show a payment screen at
  // all.
  if (!(amount > 0)) {
    const waived = await query(
      `INSERT INTO transactions (transaction_type, reference_type, reference_id, amount, gateway, gateway_ref_id, status)
       VALUES (?, 'customer', ?, 0, 'waived', NULL, 'success')`,
      [txnType, customer.customer_id]
    );
    await query('UPDATE customers SET registration_fee_paid = TRUE, registration_txn_id = ?, status = ? WHERE customer_id = ?', [
      waived.insertId,
      customer.status === 'pending_payment' ? 'active' : customer.status,
      customer.customer_id,
    ]);
    await req.audit('CustomerRegistrationPayment', 'PAYMENT', { amount: 0, waived: true, isRenewal });
    return res.json({ paid: true, amount: 0, waived: true, isRenewal, transactionId: waived.insertId });
  }

  const order = await createOrder({ amount, receipt: `custreg_${customer.customer_id}` });
  const verification = await verifyPayment({ orderId: order.orderId, paymentRef: req.body.paymentRef });

  const txn = await query(
    `INSERT INTO transactions (transaction_type, reference_type, reference_id, amount, gateway, gateway_ref_id, status)
     VALUES (?, 'customer', ?, ?, ?, ?, ?)`,
    [txnType, customer.customer_id, amount, verification.gateway, verification.gatewayRefId, verification.status]
  );

  await query('UPDATE customers SET registration_fee_paid = TRUE, registration_txn_id = ?, status = ? WHERE customer_id = ?', [
    txn.insertId,
    customer.status === 'pending_payment' ? 'active' : customer.status,
    customer.customer_id,
  ]);
  await req.audit('CustomerRegistrationPayment', 'PAYMENT', { amount, isRenewal });

  res.json({ paid: true, amount, isRenewal, transactionId: txn.insertId, gatewayRefId: verification.gatewayRefId });
});

// ---------------------------------------------------------------------
// REFERENCE CODE
// ---------------------------------------------------------------------

/**
 * Applies a business partner's reference code to this customer.
 *
 * This is the half that was missing. The app checked that the code was at
 * least four characters long, showed a green tick with the word "verified",
 * and kept it in memory -- so a typo passed, the partner's name could not be
 * shown, and closing the app threw the code away. The customer then made a
 * booking weeks later with no code attached, and the partner who introduced
 * them earned nothing.
 *
 * Validating here means the tick means something, the partner's own name
 * comes back to prove it, and the code is on the customer's row rather than
 * in a variable that does not survive the app being closed.
 */
export const applyReferralCode = asyncHandler(async (req, res) => {
  const code = String(req.body.code || '').trim().toUpperCase();
  if (!code) throw Errors.badRequest('VALIDATION', 'Enter the code you were given.');

  const [agent] = await query(
    'SELECT business_partner_id, entity_name, partner_name, status FROM business_agents WHERE referral_code = ?',
    [code]
  );
  if (!agent) {
    throw Errors.badRequest('INVALID_REFERRAL_CODE', 'That code is not one of ours. Check it with whoever gave it to you.');
  }
  if (agent.status !== 'active') {
    throw Errors.badRequest('INVALID_REFERRAL_CODE', 'That code is no longer active.');
  }

  await query('UPDATE customers SET referred_by_code = ? WHERE customer_id = ?', [code, customerId(req)]);

  // Close the loop on the partner's side: a referral they submitted for this
  // mobile number has been waiting to be linked to a real account.
  const [me] = await query('SELECT mobile_number FROM customers WHERE customer_id = ?', [customerId(req)]);
  if (me) {
    await query(
      `UPDATE business_agent_referrals
          SET customer_id = ?
        WHERE business_partner_id = ? AND mobile_number = ? AND customer_id IS NULL`,
      [customerId(req), agent.business_partner_id, me.mobile_number]
    );
  }

  await req.audit('CustomerApplyReferralCode', 'UPDATE', { code });
  res.json({ code, partnerName: agent.entity_name, contactName: agent.partner_name });
});

export const clearReferralCode = asyncHandler(async (req, res) => {
  await query('UPDATE customers SET referred_by_code = NULL WHERE customer_id = ?', [customerId(req)]);
  await req.audit('CustomerClearReferralCode', 'UPDATE');
  res.json({ code: null });
});

// ---------------------------------------------------------------------
// WHERE THEY SIGNED UP FROM
// ---------------------------------------------------------------------

/**
 * Records the place this customer registered from, and says whether Sathiyaa
 * serves it.
 *
 * The verdict is reached on the server. An app that decides for itself can be
 * talked into saying yes, and -- far more to the point -- would need a new
 * release every time the business opens a city.
 */
export const putSignupPlace = asyncHandler(async (req, res) => {
  const verdict = await recordSignupPlace({
    table: 'customers',
    idColumn: 'customer_id',
    id: customerId(req),
    place: req.body || {},
  });
  await req.audit('CustomerSignupPlace', 'UPDATE', {
    city: req.body?.city || null,
    inside: verdict.inside,
    reason: verdict.reason,
  });
  res.json({
    inServiceArea: verdict.inside,
    serviceArea: { city: verdict.area.city, state: verdict.area.state, radiusKm: verdict.area.radiusKm },
  });
});
