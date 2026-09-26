/**
 * Who does a broadcast go to?
 *
 * Split out from the controller because the admin console asks the same
 * question twice: once to show "this will reach 34 people" while the form is
 * being filled in, and once when Send is pressed. Two code paths answering it
 * would eventually disagree, and the one that disagrees is the one that has
 * already gone out.
 *
 * The filters compose as an AND: audience narrows to customers or providers,
 * then city/pincode narrows further, and an explicit list of ids overrides the
 * lot.
 *
 * Who is excluded: blocked accounts, and only blocked accounts. The previous
 * version filtered on `status = 'active'`, which sounds like the same thing and
 * is not: a customer is 'pending_payment' from the moment they register until
 * they pay the registration fee, so everybody who had signed up but not yet
 * paid silently received nothing. They are exactly the people an announcement
 * is most likely to be aimed at. `<> 'blocked'` says what the original comment
 * on this code already claimed it said -- "a blocked user should not be
 * receiving marketing" -- rather than quietly meaning more than that.
 */
import { query } from '../db/pool.js';
import { Errors } from '../utils/apiError.js';

export const AUDIENCES = ['customers', 'providers', 'both'];

/** Trimmed, de-duplicated, empties dropped. */
function cleanList(v) {
  if (!Array.isArray(v)) return [];
  const out = new Set();
  for (const x of v) {
    const s = `${x ?? ''}`.trim();
    if (s) out.add(s);
  }
  return [...out];
}

function cleanIds(v) {
  if (!Array.isArray(v)) return [];
  const out = new Set();
  for (const x of v) {
    const n = Number(x);
    if (Number.isInteger(n) && n > 0) out.add(n);
  }
  return [...out];
}

/**
 * Normalises whatever the console sent into one shape, and rejects anything
 * that would quietly reach the wrong people.
 */
export function parseTargeting(body) {
  const audience = body.audience;
  if (!AUDIENCES.includes(audience)) {
    throw Errors.badRequest('VALIDATION', `audience must be one of ${AUDIENCES.join(', ')}`);
  }

  const cities = cleanList(body.cities);
  const pincodes = cleanList(body.pincodes);
  const customerIds = cleanIds(body.customerIds);
  const providerIds = cleanIds(body.providerIds);
  const explicit = customerIds.length > 0 || providerIds.length > 0;

  // Picking people by hand and also by city is ambiguous: does the city add to
  // the list or filter it? Rather than guess, refuse -- the console does not
  // offer both at once, so this only fires for an API caller.
  if (explicit && (cities.length > 0 || pincodes.length > 0)) {
    throw Errors.badRequest(
      'VALIDATION',
      'Choose people by hand or by area, not both. A hand-picked list is sent exactly as given.'
    );
  }

  // An explicit list of providers with audience "customers" would send to
  // nobody and look like it worked.
  if (explicit) {
    if (audience === 'customers' && providerIds.length > 0) {
      throw Errors.badRequest('VALIDATION', 'providerIds were given but the audience is customers only');
    }
    if (audience === 'providers' && customerIds.length > 0) {
      throw Errors.badRequest('VALIDATION', 'customerIds were given but the audience is providers only');
    }
  }

  return { audience, cities, pincodes, customerIds, providerIds, explicit };
}

/**
 * The actual people, as `{ userType, userId, name }`.
 *
 * Address matching goes through the address tables, which is where city and
 * pincode live -- a customer's on `customer_addresses`, a provider's on
 * `service_provider_addresses`. Somebody with no address on file matches no
 * city, which is correct: we do not know where they are, so "everyone in
 * Bengaluru" cannot honestly include them.
 */
export async function resolveRecipients(t) {
  const out = [];

  const wantsCustomers = t.audience === 'customers' || t.audience === 'both';
  const wantsProviders = t.audience === 'providers' || t.audience === 'both';

  if (wantsCustomers) {
    if (t.explicit) {
      if (t.customerIds.length > 0) {
        const rows = await query(
          `SELECT customer_id AS id, name FROM customers
            WHERE status <> 'blocked' AND customer_id IN (${t.customerIds.map(() => '?').join(',')})`,
          t.customerIds
        );
        out.push(...rows.map((r) => ({ userType: 'customer', userId: r.id, name: r.name })));
      }
    } else {
      const where = ["c.status <> 'blocked'"];
      const params = [];
      if (t.cities.length > 0) {
        where.push(`LOWER(a.city) IN (${t.cities.map(() => '?').join(',')})`);
        params.push(...t.cities.map((c) => c.toLowerCase()));
      }
      if (t.pincodes.length > 0) {
        where.push(`a.pincode IN (${t.pincodes.map(() => '?').join(',')})`);
        params.push(...t.pincodes);
      }
      const needsAddress = t.cities.length > 0 || t.pincodes.length > 0;
      const rows = await query(
        `SELECT DISTINCT c.customer_id AS id, c.name
           FROM customers c
           ${needsAddress ? 'JOIN' : 'LEFT JOIN'} customer_addresses a ON a.customer_id = c.customer_id
          WHERE ${where.join(' AND ')}`,
        params
      );
      out.push(...rows.map((r) => ({ userType: 'customer', userId: r.id, name: r.name })));
    }
  }

  if (wantsProviders) {
    if (t.explicit) {
      if (t.providerIds.length > 0) {
        const rows = await query(
          `SELECT provider_id AS id, name FROM service_providers
            WHERE status <> 'blocked' AND provider_id IN (${t.providerIds.map(() => '?').join(',')})`,
          t.providerIds
        );
        out.push(...rows.map((r) => ({ userType: 'provider', userId: r.id, name: r.name })));
      }
    } else {
      const where = ["p.status <> 'blocked'"];
      const params = [];
      if (t.cities.length > 0) {
        where.push(`LOWER(a.city) IN (${t.cities.map(() => '?').join(',')})`);
        params.push(...t.cities.map((c) => c.toLowerCase()));
      }
      if (t.pincodes.length > 0) {
        where.push(`a.pincode IN (${t.pincodes.map(() => '?').join(',')})`);
        params.push(...t.pincodes);
      }
      const needsAddress = t.cities.length > 0 || t.pincodes.length > 0;
      const rows = await query(
        `SELECT DISTINCT p.provider_id AS id, p.name
           FROM service_providers p
           ${needsAddress ? 'JOIN' : 'LEFT JOIN'} service_provider_addresses a ON a.provider_id = p.provider_id
          WHERE ${where.join(' AND ')}`,
        params
      );
      out.push(...rows.map((r) => ({ userType: 'provider', userId: r.id, name: r.name })));
    }
  }

  return out;
}

/**
 * Every city that has anybody in it, for the console's picker.
 *
 * Counted per audience so the admin can see that "Pune" means four customers
 * and no carers before sending something that reaches four people.
 */
export async function availableCities() {
  const rows = await query(
    `SELECT city, SUM(customers) AS customers, SUM(providers) AS providers FROM (
        SELECT a.city AS city, COUNT(DISTINCT c.customer_id) AS customers, 0 AS providers
          FROM customer_addresses a
          JOIN customers c ON c.customer_id = a.customer_id AND c.status <> 'blocked'
         WHERE a.city IS NOT NULL AND a.city <> ''
         GROUP BY a.city
        UNION ALL
        SELECT a.city AS city, 0 AS customers, COUNT(DISTINCT p.provider_id) AS providers
          FROM service_provider_addresses a
          JOIN service_providers p ON p.provider_id = a.provider_id AND p.status <> 'blocked'
         WHERE a.city IS NOT NULL AND a.city <> ''
         GROUP BY a.city
     ) t
     GROUP BY city
     ORDER BY city`
  );
  return rows.map((r) => ({
    city: r.city,
    customers: Number(r.customers) || 0,
    providers: Number(r.providers) || 0,
  }));
}
