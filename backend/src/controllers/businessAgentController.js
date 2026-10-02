import { query } from '../db/pool.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { Errors } from '../utils/apiError.js';

const agentId = (req) => req.user.id;

export const getMe = asyncHandler(async (req, res) => {
  const [agent] = await query('SELECT * FROM business_agents WHERE business_partner_id = ?', [agentId(req)]);
  if (!agent) throw Errors.notFound('Business agent not found');
  res.json(serialize(agent));
});

function serialize(a) {
  return {
    businessPartnerId: a.business_partner_id,
    displayId: a.display_id,
    entityName: a.entity_name,
    partnerName: a.partner_name,
    contactNumber1: a.contact_number_1,
    contactNumber2: a.contact_number_2,
    email: a.email,
    address: a.address,
    referralCode: a.referral_code,
    status: a.status,
  };
}

export const updateMe = asyncHandler(async (req, res) => {
  const b = req.body;
  const fields = [];
  const values = [];
  const map = { entityName: 'entity_name', partnerName: 'partner_name', contactNumber1: 'contact_number_1', contactNumber2: 'contact_number_2', email: 'email', address: 'address' };
  for (const [k, col] of Object.entries(map)) {
    if (b[k] !== undefined) { fields.push(`${col} = ?`); values.push(b[k]); }
  }
  if (fields.length === 0) throw Errors.badRequest('VALIDATION', 'No updatable fields provided');
  values.push(agentId(req));
  await query(`UPDATE business_agents SET ${fields.join(', ')} WHERE business_partner_id = ?`, values);
  await req.audit('BusinessAgentUpdateProfile', 'UPDATE');
  const [agent] = await query('SELECT * FROM business_agents WHERE business_partner_id = ?', [agentId(req)]);
  res.json(serialize(agent));
});

export const createReferral = asyncHandler(async (req, res) => {
  const b = req.body;
  const required = ['customerName', 'serviceType', 'durationStart', 'durationEnd', 'timeFrom', 'timeTo', 'mobileNumber'];
  for (const f of required) if (!b[f]) throw Errors.badRequest('VALIDATION', `${f} is required`);

  const [agent] = await query('SELECT referral_code FROM business_agents WHERE business_partner_id = ?', [agentId(req)]);

  const result = await query(
    `INSERT INTO business_agent_referrals
      (business_partner_id, customer_name, gender, service_type, duration_start, duration_end, time_from, time_to, mobile_number, address)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [agentId(req), b.customerName, b.gender || null, b.serviceType, b.durationStart, b.durationEnd, b.timeFrom, b.timeTo, b.mobileNumber, b.address || null]
  );
  await req.audit('BusinessAgentCreateReferral', 'CREATE', { referralId: result.insertId });

  res.status(201).json({ referralId: result.insertId, referralCode: agent.referral_code });
});

/**
 * The referral list for one partner, by id.
 *
 * Split out from the request handler because the admin console needs exactly
 * this, for a partner other than the caller. It used to call the partner's own
 * `/business-agents/me/referrals` with a `business_partner_id` query parameter,
 * which could never have worked: that route is behind requireAuth in the
 * business_agent role, so an admin token got 403, and the handler scopes by the
 * id in the *token* regardless, so the parameter was never read.
 */
export async function referralsForAgent(partnerId) {
  // The allocated carer is joined in by name. The console showed a referral as
  // 'booked' with nothing saying who was sent, because the id was the only
  // thing stored and nothing resolved it -- and a partner ringing up to ask
  // which carer their client is getting is the most ordinary question there is.
  const rows = await query(
    `SELECT r.*, a.referral_code,
            p.name AS allocated_provider_name,
            p.display_id AS allocated_provider_display_id,
            p.mobile_number AS allocated_provider_mobile
     FROM business_agent_referrals r
     JOIN business_agents a ON a.business_partner_id = r.business_partner_id
     LEFT JOIN service_providers p ON p.provider_id = r.allocated_provider_id
     WHERE r.business_partner_id = ?
     ORDER BY r.created_at DESC`,
    [partnerId]
  );
  // hours_used comes from the sessions actually worked on bookings that
  // carried this partner's code -- the referral row does not hold it.
  const [{ code } = {}] = await query(
    'SELECT referral_code AS code FROM business_agents WHERE business_partner_id = ?',
    [partnerId]
  );
  const hours = code
    ? await query(
        `SELECT b.customer_id, COALESCE(SUM(s.total_hours), 0) AS hours
         FROM bookings b
         LEFT JOIN booking_service_sessions s ON s.booking_id = b.booking_id AND s.end_time_actual IS NOT NULL
         WHERE b.referral_code = ?
         GROUP BY b.customer_id`,
        [code]
      )
    : [];
  const byCustomer = Object.fromEntries(hours.map((h) => [h.customer_id, Number(h.hours) || 0]));

  return {
    referrals: rows.map((r) => ({
      ...r,
      // The list shows a referral code column; without this it was blank.
      referral_code: r.referral_code,
      hours_used: r.customer_id ? byCustomer[r.customer_id] ?? 0 : 0,
    })),
  };
}

export const listReferrals = asyncHandler(async (req, res) => {
  res.json(await referralsForAgent(agentId(req)));
});

// Σ (hours used × flat rate/hr for that service type) per referral, using
// bookings that carried this agent's referral_code and their completed
// service sessions.
export async function revenueForAgent(partnerId) {
  const [agent] = await query('SELECT referral_code FROM business_agents WHERE business_partner_id = ?', [partnerId]);
  if (!agent) throw Errors.notFound('Business agent not found');

  const rows = await query(
    `SELECT b.booking_id, b.display_id, b.service_type, b.customer_id, c.name AS customer_name,
            COALESCE(SUM(s.total_hours), 0) AS totalHours,
            rsc.business_partner_flat_per_hour AS flatRatePerHour,
            COALESCE(SUM(s.total_hours), 0) * COALESCE(rsc.business_partner_flat_per_hour, 0) AS revenue
     FROM bookings b
     JOIN customers c ON c.customer_id = b.customer_id
     LEFT JOIN booking_service_sessions s ON s.booking_id = b.booking_id AND s.end_time_actual IS NOT NULL
     LEFT JOIN revenue_sharing_config rsc ON rsc.service_type = b.service_type
       AND rsc.effective_from = (SELECT MAX(effective_from) FROM revenue_sharing_config WHERE service_type = b.service_type AND effective_from <= CURDATE())
     WHERE b.referral_code = ?
     GROUP BY b.booking_id, rsc.business_partner_flat_per_hour
     ORDER BY b.created_at DESC`,
    [agent.referral_code]
  );

  const totalRevenue = rows.reduce((sum, r) => sum + Number(r.revenue), 0);
  return { referralCode: agent.referral_code, totalRevenue: Math.round(totalRevenue * 100) / 100, bookings: rows };
}

export const getRevenue = asyncHandler(async (req, res) => {
  res.json(await revenueForAgent(agentId(req)));
});

// ---------------------------------------------------------------------
// The same two, for an admin looking at somebody else's partner account.
// Mounted under /admin, so requireAuth('admin') in admin.routes.js is what
// separates these from the two above.
// ---------------------------------------------------------------------

const partnerIdParam = (req) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id) || id <= 0) throw Errors.badRequest('VALIDATION', 'id must be a business partner id');
  return id;
};

export const adminListReferrals = asyncHandler(async (req, res) => {
  const id = partnerIdParam(req);
  const [agent] = await query('SELECT business_partner_id FROM business_agents WHERE business_partner_id = ?', [id]);
  if (!agent) throw Errors.notFound('Business partner not found');
  res.json(await referralsForAgent(id));
});

export const adminGetRevenue = asyncHandler(async (req, res) => {
  res.json(await revenueForAgent(partnerIdParam(req)));
});
