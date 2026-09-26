import { query } from '../db/pool.js';
import { getConfigNumber } from './appConfig.js';

function round2(n) {
  return Math.round(n * 100) / 100;
}

/**
 * Time Bank: credits a No-Fees provider's donated hours as points, using
 * the admin-configured points-per-hour for this service_type + the
 * calendar year the session actually happened in. Falls back to 0 points
 * (still logs the donated hours) if no config row exists for that year —
 * an admin oversight shouldn't block the provider from completing service.
 */
export async function creditTimeBank({ providerId, bookingId, serviceType, hours, onDate = new Date() }) {
  const year = onDate.getFullYear();
  const [cfg] = await query(
    'SELECT points_per_hour FROM time_bank_config WHERE service_type = ? AND application_year = ?',
    [serviceType, year]
  );
  const pointsPerHour = cfg ? Number(cfg.points_per_hour) : 0;
  const pointsEarned = round2(Number(hours) * pointsPerHour);
  await query(
    'INSERT INTO time_bank_ledger (provider_id, booking_id, service_type, hours, points_earned) VALUES (?, ?, ?, ?, ?)',
    [providerId, bookingId, serviceType, hours, pointsEarned]
  );
  return { pointsPerHour, pointsEarned };
}

export async function getTimeBankSummary(providerId) {
  const [totals] = await query(
    'SELECT COALESCE(SUM(hours), 0) AS totalHours, COALESCE(SUM(points_earned), 0) AS totalPoints FROM time_bank_ledger WHERE provider_id = ?',
    [providerId]
  );
  const entries = await query(
    'SELECT id, booking_id, service_type, hours, points_earned, recorded_at FROM time_bank_ledger WHERE provider_id = ? ORDER BY recorded_at DESC',
    [providerId]
  );
  return {
    totalHours: Number(totals.totalHours),
    totalPoints: Number(totals.totalPoints),
    entries,
  };
}

/**
 * Organization billing: "if Sathiyaa says 20% of service amount of 100/hr
 * then it will show as INR 120/hr to the customer". The organization sets
 * its own per-service fee (organization_service_fees, falling back to the
 * employee's own hourly_rate when the org hasn't overridden it); Sathiyaa's
 * revenue share is an ADDITIVE markup on top of that fee for the customer
 * -facing amount — distinct from the freelancer deduction-based
 * revenue_sharing_config, and the organization keeps the full fee amount.
 */
export async function computeOrgBilling({ organizationId, employeeHourlyRate, serviceType, totalHours }) {
  const [override] = await query(
    'SELECT fee_per_hour FROM organization_service_fees WHERE organization_id = ? AND service_type = ?',
    [organizationId, serviceType]
  );
  const feePerHour = override ? Number(override.fee_per_hour) : Number(employeeHourlyRate) || 0;
  const markupPercent = await getConfigNumber('org_revenue_share_percent', 0);
  const hours = Number(totalHours) || 0;

  const providerEarning = round2(feePerHour * hours);
  const customerAmount = round2(providerEarning * (1 + markupPercent / 100));

  return { feePerHour, markupPercent, providerEarning, customerAmount };
}
