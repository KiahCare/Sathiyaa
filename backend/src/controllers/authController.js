import bcrypt from 'bcryptjs';
import { query, withTransaction } from '../db/pool.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { Errors } from '../utils/apiError.js';
import { signToken } from '../utils/jwt.js';
import { recordDevice } from '../middleware/deviceRegistry.js';
import { generateOtp, hashOtp, compareOtp, otpExpiryDate } from '../utils/otp.js';
import { displayId } from '../utils/ids.js';
import { sendOtp } from '../integrations/sms.js';
import { env } from '../config/env.js';
import { normaliseGender } from '../utils/enums.js';

const devOtpField = (otp) => (env.isProd ? {} : { devOtp: otp });

/**
 * A real bcrypt hash of a value nobody will ever type.
 *
 * The admin and partner sign-ins answer the same way whether the account does
 * not exist or the password is wrong. That is only true if it also *takes* the
 * same time: comparing against a hash costs about a tenth of a second, and
 * returning early when there is no account costs nothing, so the clock answers
 * the question the status code no longer does. Comparing against this instead
 * keeps the two paths the same length.
 */
const NO_SUCH_ACCOUNT_HASH = '$2a$10$eIrZ98eCh3PqPD7jucOQ/.lxnJ5RO8q9qddP7RHamaMtiMQLrpuVm';

// ---------------------------------------------------------------------
// CUSTOMER
// ---------------------------------------------------------------------

export const customerRegister = asyncHandler(async (req, res) => {
  const { name, mobile } = req.body;
  if (!name || !mobile) throw Errors.badRequest('VALIDATION', 'name and mobile are required');

  let [customer] = await query('SELECT * FROM customers WHERE mobile_number = ?', [mobile]);
  if (customer && customer.status === 'blocked') throw Errors.forbidden('This account is blocked');

  if (!customer) {
    const result = await query(
      // Registration collects a name and a mobile number. It used to fill the
      // other NOT NULL columns with '1970-01-01', 'other' and '' -- and those
      // are not placeholders once they are rows. The app read them back and
      // pre-filled every new customer's date of birth as 1 Jan 1970.
      // Migration 014 makes the three columns nullable so an unanswered
      // question can be stored as unanswered.
      `INSERT INTO customers (display_id, name, photo_url, dob, gender, mobile_number, status)
       VALUES ('PENDING', ?, NULL, NULL, NULL, ?, 'pending_payment')`,
      [name, mobile]
    );
    const newId = result.insertId;
    await query('UPDATE customers SET display_id = ? WHERE customer_id = ?', [displayId('CUST', newId), newId]);
    [customer] = await query('SELECT * FROM customers WHERE customer_id = ?', [newId]);
  }

  const otp = generateOtp();
  const otpHash = await hashOtp(otp);
  await query('UPDATE customers SET otp_hash = ?, otp_expires_at = ? WHERE customer_id = ?', [
    otpHash,
    otpExpiryDate(env.otpTtlMinutes),
    customer.customer_id,
  ]);
  await sendOtp({ mobileNumber: mobile, otp, purpose: 'register' });
  await req.audit('CustomerRegister', 'CREATE', { mobile }, { role: 'customer', id: customer.customer_id, name: customer.name });

  res.status(201).json({
    customerId: customer.customer_id,
    displayId: customer.display_id,
    message: 'OTP sent',
    ...devOtpField(otp),
  });
});

export const customerLogin = asyncHandler(async (req, res) => {
  const { mobile } = req.body;
  if (!mobile) throw Errors.badRequest('VALIDATION', 'mobile is required');

  const [customer] = await query('SELECT * FROM customers WHERE mobile_number = ?', [mobile]);
  if (!customer) throw Errors.notFound('No account found for this mobile number');
  if (customer.status === 'blocked') throw Errors.forbidden('This account is blocked');

  const otp = generateOtp();
  const otpHash = await hashOtp(otp);
  await query('UPDATE customers SET otp_hash = ?, otp_expires_at = ? WHERE customer_id = ?', [
    otpHash,
    otpExpiryDate(env.otpTtlMinutes),
    customer.customer_id,
  ]);
  await sendOtp({ mobileNumber: mobile, otp, purpose: 'login' });
  await req.audit('CustomerLogin', 'REQUEST_OTP', { mobile }, { role: 'customer', id: customer.customer_id, name: customer.name });

  res.json({ message: 'OTP sent', ...devOtpField(otp) });
});

export const customerResetOtp = customerLogin; // same behavior: re-send a fresh OTP

export const customerVerifyOtp = asyncHandler(async (req, res) => {
  const { mobile, otp } = req.body;
  if (!mobile || !otp) throw Errors.badRequest('VALIDATION', 'mobile and otp are required');

  const [customer] = await query('SELECT * FROM customers WHERE mobile_number = ?', [mobile]);
  if (!customer) throw Errors.notFound('No account found for this mobile number');
  if (customer.status === 'blocked') throw Errors.forbidden('This account is blocked');
  if (!customer.otp_expires_at || new Date(customer.otp_expires_at) < new Date()) {
    throw Errors.unprocessable('OTP_EXPIRED', 'OTP has expired, request a new one');
  }
  const ok = await compareOtp(otp, customer.otp_hash);
  if (!ok) throw Errors.unprocessable('OTP_INVALID', 'Incorrect OTP');

  await query('UPDATE customers SET otp_hash = NULL, otp_expires_at = NULL WHERE customer_id = ?', [customer.customer_id]);
  const token = signToken({ role: 'customer', id: customer.customer_id, name: customer.name });
  void recordDevice(req, { role: 'customer', id: customer.customer_id, name: customer.name });
  await req.audit('CustomerVerifyOtp', 'LOGIN', { mobile }, { role: 'customer', id: customer.customer_id, name: customer.name });

  res.json({
    token,
    customer: { customerId: customer.customer_id, displayId: customer.display_id, name: customer.name, status: customer.status },
  });
});

// ---------------------------------------------------------------------
// SERVICE PROVIDER
// ---------------------------------------------------------------------

export const providerRegister = asyncHandler(async (req, res) => {
  const b = req.body;
  if (!b.name || !b.mobile || !b.providerKind) {
    throw Errors.badRequest('VALIDATION', 'name, mobile and providerKind are required');
  }
  if (!['freelancer', 'organization', 'org_employee'].includes(b.providerKind)) {
    throw Errors.badRequest('VALIDATION', 'providerKind must be freelancer, organization or org_employee');
  }
  const [existing] = await query('SELECT provider_id FROM service_providers WHERE mobile_number = ?', [b.mobile]);
  if (existing) throw Errors.conflict('ALREADY_REGISTERED', 'A provider with this mobile number already exists');

  const pinHash = b.pin ? await bcrypt.hash(String(b.pin), 10) : null;

  const provider = await withTransaction(async (conn) => {
    const [result] = await conn.query(
      `INSERT INTO service_providers
        (display_id, provider_kind, organization_id, name, photo_url, gender, dob, mobile_number, email,
         pin_hash, hourly_rate, aadhar_doc_url, police_verification_url, work_certificate_url,
         org_registration_url, gst_number, contact_person,
         distance_from_home_pref_km, distance_from_office_pref_km, languages, device_id)
       VALUES ('PENDING', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        b.providerKind,
        b.organizationId || null,
        b.name,
        b.photoUrl || null,
        normaliseGender(b.gender),
        b.dob || null,
        b.mobile,
        b.email || null,
        pinHash,
        b.hourlyRate || 0,
        b.aadharDocUrl || null,
        b.policeVerificationUrl || null,
        b.workCertificateUrl || null,
        // Organisations only. A freelancer sends none of these, and an
        // organisation sends no gender or date of birth -- which is why
        // normaliseGender has to tolerate an empty string rather than
        // defaulting a company to 'female'.
        b.orgRegistrationUrl || null,
        b.gstNumber || null,
        b.contactPerson || null,
        b.distanceFromHomePrefKm || null,
        b.distanceFromOfficePrefKm || null,
        b.languages ? JSON.stringify(b.languages) : null,
        // Bind the account to the handset it was created on. Without this the
        // account stayed unbound until its first PIN login, and any device
        // with the right PIN could claim it in the meantime.
        b.deviceId || null,
      ]
    );
    const providerId = result.insertId;
    await conn.query('UPDATE service_providers SET display_id = ? WHERE provider_id = ?', [displayId('SP', providerId), providerId]);

    if (Array.isArray(b.addresses)) {
      for (const a of b.addresses) {
        await conn.query(
          `INSERT INTO service_provider_addresses (provider_id, address_type, line1, line2, city, state, pincode, latitude, longitude)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [providerId, a.addressType || 'home', a.line1, a.line2 || null, a.city || null, a.state || null, a.pincode || null, a.latitude || null, a.longitude || null]
        );
      }
    }
    // An organisation that names no days still has to be findable.
    //
    // The matching query INNER JOINs service_provider_work_hours, so a
    // provider with no rows matches nothing, ever -- an agency that skipped
    // the (now optional) "days the organisation operates" question would
    // register successfully, appear in the console as approved, and never be
    // offered a single booking, with nothing on any screen to say why.
    //
    // An agency covers whatever hours the carer it sends covers, so the
    // honest default is all seven days. Each carer's own days are collected
    // when they are added, and those are what a family is really matched
    // against.
    const DAYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
    let workHours = Array.isArray(b.workHours) ? b.workHours : [];
    if (workHours.length === 0 && b.providerKind === 'organization') {
      workHours = DAYS.map((d) => ({ dayOfWeek: d, startTime: '00:00', endTime: '23:59' }));
    }
    for (const w of workHours) {
      await conn.query(
        `INSERT INTO service_provider_work_hours (provider_id, day_of_week, start_time, end_time) VALUES (?, ?, ?, ?)`,
        [providerId, w.dayOfWeek, w.startTime, w.endTime]
      );
    }
    if (Array.isArray(b.expertise)) {
      for (const e of b.expertise) {
        await conn.query(
          `INSERT INTO service_provider_expertise (provider_id, service_type, years_experience, notes) VALUES (?, ?, ?, ?)`,
          [providerId, e.serviceType, e.yearsExperience || null, e.notes || null]
        );
      }
    }
    const [row] = await conn.query('SELECT * FROM service_providers WHERE provider_id = ?', [providerId]);
    return row[0];
  });

  const token = signToken({ role: 'provider', id: provider.provider_id, name: provider.name });
  void recordDevice(req, { role: 'provider', id: provider.provider_id, name: provider.name });
  await req.audit('ProviderRegister', 'CREATE', { mobile: b.mobile, providerKind: b.providerKind }, { role: 'provider', id: provider.provider_id, name: provider.name });

  res.status(201).json({
    token,
    provider: {
      providerId: provider.provider_id,
      displayId: provider.display_id,
      approvalStatus: provider.approval_status,
      message: 'Registered. Pending admin approval. Pay registration fee via POST /providers/me/registration-payment.',
    },
  });
});

export const providerLogin = asyncHandler(async (req, res) => {
  const { mobile, pin, deviceId } = req.body;
  if (!mobile || !pin) throw Errors.badRequest('VALIDATION', 'mobile and pin are required');

  const [provider] = await query('SELECT * FROM service_providers WHERE mobile_number = ?', [mobile]);
  if (!provider) throw Errors.notFound('No provider account for this mobile number');
  if (provider.status === 'blocked') throw Errors.forbidden('This account is blocked');
  if (!provider.pin_hash) throw Errors.unprocessable('PIN_NOT_SET', 'PIN not set for this account, use reset-pin-otp');

  const ok = await bcrypt.compare(String(pin), provider.pin_hash);
  if (!ok) throw Errors.unprocessable('PIN_INVALID', 'Incorrect PIN');

  const effectiveDeviceId = deviceId || req.headers['x-device-id'] || null;
  if (provider.device_id && effectiveDeviceId && provider.device_id !== effectiveDeviceId) {
    throw Errors.forbidden('This account is already bound to a different device. Contact admin to reset.');
  }
  if (!provider.device_id && effectiveDeviceId) {
    await query('UPDATE service_providers SET device_id = ? WHERE provider_id = ?', [effectiveDeviceId, provider.provider_id]);
  }

  const token = signToken({ role: 'provider', id: provider.provider_id, name: provider.name });
  void recordDevice(req, { role: 'provider', id: provider.provider_id, name: provider.name });
  await req.audit('ProviderLogin', 'LOGIN', { mobile }, { role: 'provider', id: provider.provider_id, name: provider.name });

  res.json({
    token,
    provider: {
      providerId: provider.provider_id,
      displayId: provider.display_id,
      name: provider.name,
      providerKind: provider.provider_kind,
      approvalStatus: provider.approval_status,
      status: provider.status,
    },
  });
});

// Single endpoint, two phases: {mobile} -> sends OTP; {mobile, otp, newPin} -> verifies + sets new PIN.
export const providerResetPinOtp = asyncHandler(async (req, res) => {
  const { mobile, otp, newPin } = req.body;
  if (!mobile) throw Errors.badRequest('VALIDATION', 'mobile is required');

  const [provider] = await query('SELECT * FROM service_providers WHERE mobile_number = ?', [mobile]);
  if (!provider) throw Errors.notFound('No provider account for this mobile number');
  if (provider.status === 'blocked') throw Errors.forbidden('This account is blocked');

  if (otp && newPin) {
    const [otpRow] = await query(
      `SELECT * FROM otp_log WHERE user_type = 'provider' AND user_id = ? AND purpose = 'reset' AND verified_at IS NULL
       ORDER BY id DESC LIMIT 1`,
      [provider.provider_id]
    );
    if (!otpRow) throw Errors.unprocessable('OTP_NOT_FOUND', 'No pending reset OTP, request a new one');
    if (new Date(otpRow.expires_at) < new Date()) throw Errors.unprocessable('OTP_EXPIRED', 'OTP expired');
    const ok = await compareOtp(otp, otpRow.otp_hash);
    if (!ok) throw Errors.unprocessable('OTP_INVALID', 'Incorrect OTP');

    const newPinHash = await bcrypt.hash(String(newPin), 10);
    await query('UPDATE service_providers SET pin_hash = ? WHERE provider_id = ?', [newPinHash, provider.provider_id]);
    await query('UPDATE otp_log SET verified_at = NOW() WHERE id = ?', [otpRow.id]);
    await req.audit('ProviderResetPin', 'UPDATE', { mobile }, { role: 'provider', id: provider.provider_id, name: provider.name });
    return res.json({ message: 'PIN reset successfully' });
  }

  const otpCode = generateOtp();
  const otpHash = await hashOtp(otpCode);
  await query(
    `INSERT INTO otp_log (user_type, user_id, purpose, otp_hash, expires_at) VALUES ('provider', ?, 'reset', ?, ?)`,
    [provider.provider_id, otpHash, otpExpiryDate(env.otpTtlMinutes)]
  );
  await sendOtp({ mobileNumber: mobile, otp: otpCode, purpose: 'reset' });
  await req.audit('ProviderResetPinOtp', 'REQUEST_OTP', { mobile }, { role: 'provider', id: provider.provider_id, name: provider.name });

  res.json({ message: 'OTP sent. Call this endpoint again with {mobile, otp, newPin} to complete the reset.', ...devOtpField(otpCode) });
});

// ---------------------------------------------------------------------
// BUSINESS AGENT
// ---------------------------------------------------------------------

async function findBusinessAgent(identifier) {
  // Partners are given four things on sign-up -- a partner ID, a referral
  // code, their contact number and their email -- and they remember whichever
  // they remember. Email was missing here, so a partner typing the address we
  // hold for them was told no account exists.
  const [agent] = await query(
    `SELECT * FROM business_agents
      WHERE display_id = ? OR contact_number_1 = ? OR contact_number_2 = ?
         OR referral_code = ? OR email = ?`,
    [identifier, identifier, identifier, identifier, identifier]
  );
  return agent;
}

export const businessAgentLogin = asyncHandler(async (req, res) => {
  const { identifier, password, otp } = req.body;
  if (!identifier) throw Errors.badRequest('VALIDATION', 'identifier (userId or mobile) is required');

  const agent = await findBusinessAgent(identifier);

  // Same reasoning as the admin sign-in above. A partner account is created in
  // the office, never by the partner, so an unknown identifier and a wrong
  // password are one answer — and a partner can be found by partner ID,
  // referral code, mobile or email, which is four things to go fishing with
  // rather than one.
  if (password) {
    const ok = await bcrypt.compare(
      password, agent && agent.password_hash ? agent.password_hash : NO_SUCH_ACCOUNT_HASH
    );
    if (!agent || !agent.password_hash || !ok) throw Errors.invalidCredentials();
  } else if (otp) {
    const live = agent && agent.otp_expires_at && new Date(agent.otp_expires_at) >= new Date();
    const ok = live && (await compareOtp(otp, agent.otp_hash));
    if (!ok) throw Errors.invalidCredentials('That code is not right, or it has expired. Ask for a new one.');
    await query('UPDATE business_agents SET otp_hash = NULL, otp_expires_at = NULL WHERE business_partner_id = ?', [agent.business_partner_id]);
  } else {
    throw Errors.badRequest('VALIDATION', 'password or otp is required');
  }

  if (agent.status === 'blocked') throw Errors.forbidden('This account is blocked');

  const token = signToken({ role: 'business_agent', id: agent.business_partner_id, name: agent.partner_name });
  void recordDevice(req, { role: 'business_agent', id: agent.business_partner_id, name: agent.partner_name });
  await req.audit('BusinessAgentLogin', 'LOGIN', { identifier }, { role: 'business_agent', id: agent.business_partner_id, name: agent.partner_name });

  res.json({
    token,
    agent: { businessPartnerId: agent.business_partner_id, displayId: agent.display_id, entityName: agent.entity_name, partnerName: agent.partner_name },
  });
});

export const businessAgentResetOtp = asyncHandler(async (req, res) => {
  const { identifier } = req.body;
  if (!identifier) throw Errors.badRequest('VALIDATION', 'identifier is required');

  const agent = await findBusinessAgent(identifier);

  // Worth closing along with the sign-in above, or the same list could just be
  // gathered here instead. An identifier that is not one gets the same sentence
  // as one that is.
  //
  // While NODE_ENV is not "production" the code itself comes back in the body,
  // so the presence of `devOtp` still says whether the account exists. That is
  // the trade-off that was chosen deliberately while there is no SMS provider,
  // and it closes by itself the day one is configured — not something to paper
  // over here.
  const SENT = 'If that account exists, a code has been sent to the number on it.';
  if (!agent || agent.status === 'blocked') {
    return res.json({ message: SENT });
  }

  const otp = generateOtp();
  const otpHash = await hashOtp(otp);
  await query('UPDATE business_agents SET otp_hash = ?, otp_expires_at = ? WHERE business_partner_id = ?', [
    otpHash,
    otpExpiryDate(env.otpTtlMinutes),
    agent.business_partner_id,
  ]);
  await sendOtp({ mobileNumber: agent.contact_number_1, otp, purpose: 'reset' });
  await req.audit('BusinessAgentResetOtp', 'REQUEST_OTP', { identifier }, { role: 'business_agent', id: agent.business_partner_id, name: agent.partner_name });

  res.json({ message: SENT, ...devOtpField(otp) });
});

// ---------------------------------------------------------------------
// ADMIN
// ---------------------------------------------------------------------

export const adminLogin = asyncHandler(async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) throw Errors.badRequest('VALIDATION', 'email and password are required');

  const [admin] = await query('SELECT * FROM admin_users WHERE email = ?', [email]);

  // No account and a wrong password are the same answer, and the blocked check
  // comes after the password rather than before it. Nobody signs themselves up
  // as an administrator, so telling an anonymous caller that an address is one
  // — or that it is one that has been blocked — gives a legitimate user nothing
  // and gives everybody else a list.
  const ok = await bcrypt.compare(password, admin ? admin.password_hash : NO_SUCH_ACCOUNT_HASH);
  if (!admin || !ok) throw Errors.invalidCredentials();

  // Past this point the caller has proved the password, so they are entitled to
  // know why they are not getting in.
  if (admin.status === 'blocked') throw Errors.forbidden('This account is blocked');

  const token = signToken({ role: 'admin', id: admin.admin_id, name: admin.name });
  void recordDevice(req, { role: 'admin', id: admin.admin_id, name: admin.name });
  await req.audit('AdminLogin', 'LOGIN', { email }, { role: 'admin', id: admin.admin_id, name: admin.name });

  res.json({ token, admin: { adminId: admin.admin_id, name: admin.name, role: admin.role } });
});
