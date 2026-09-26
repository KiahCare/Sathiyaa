import { query } from '../db/pool.js';
import { localYmd } from '../utils/dates.js';

/**
 * Returns the currently-effective revenue_sharing_config row for a
 * service_type: the row with the latest effective_from <= today.
 */
export async function getEffectiveRevenueConfig(serviceType, onDate = new Date()) {
  // Local calendar date: toISOString() would ask for yesterday's rates
  // during the small hours, which is a real rate for a real session.
  const dateStr = localYmd(onDate);
  const rows = await query(
    `SELECT * FROM revenue_sharing_config
     WHERE service_type = ? AND effective_from <= ?
     ORDER BY effective_from DESC
     LIMIT 1`,
    [serviceType, dateStr]
  );
  return rows[0] || null;
}

/**
 * Computes the revenue split for a completed service session:
 *  - customerAmount: what the customer is billed (hours * customer_rate_per_hour)
 *  - providerEarning: what the provider earns (hours * provider_rate_per_hour)
 *  - businessPartnerEarning: flat rate/hr paid to the referring business
 *    partner, only if the booking carries a referral_code (0 otherwise)
 */
export async function computeRevenueSplit({ serviceType, totalHours, hasReferral }) {
  const config = await getEffectiveRevenueConfig(serviceType);
  if (!config) {
    return {
      config: null,
      customerAmount: 0,
      providerEarning: 0,
      businessPartnerEarning: 0,
    };
  }

  const hours = Number(totalHours) || 0;
  const customerAmount = round2(hours * Number(config.customer_rate_per_hour));
  const providerEarning = round2(hours * Number(config.provider_rate_per_hour));
  const businessPartnerEarning = hasReferral
    ? round2(hours * Number(config.business_partner_flat_per_hour))
    : 0;

  return { config, customerAmount, providerEarning, businessPartnerEarning };
}

function round2(n) {
  return Math.round(n * 100) / 100;
}
