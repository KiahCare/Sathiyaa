/**
 * What an account pays to register, and what it pays a year later.
 *
 * The admin console has always had four fee fields: a new-customer fee and a
 * renewal fee, and the same pair for providers. Two of them were read by
 * nothing at all. `customer_annual_fee_existing` and
 * `provider_annual_fee_existing` saved, showed a success toast, and changed
 * what nobody paid -- there was no renewal anywhere in the product. From an
 * administrator's chair those fields looked exactly as working as the two
 * beside them.
 *
 * This is the missing half, and it is deliberately the SMALL version of it.
 *
 * WHAT IT DOES: works out whether an account is inside its paid year, and
 * charges the renewal rate rather than the joining rate once that year is up.
 *
 * WHAT IT DOES NOT DO: nothing lapses. An account that is a day past its
 * renewal date keeps working exactly as before -- it is simply *able* to pay
 * again, at the renewal price. Silently cutting off a family's ability to
 * book care because a date passed is not a thing to add as a side effect of
 * fixing a settings screen; if Sathiyaa ever wants that, it wants reminders
 * and a grace period first, and that is a feature with its own decisions in
 * it.
 *
 * There are also no reminders, and no proration.
 */
import { query } from '../db/pool.js';
import { getConfigNumber } from './appConfig.js';

const KINDS = {
  customer: {
    referenceType: 'customer',
    joining: 'customer_registration',
    renewal: 'annual_renewal_customer',
    newKey: 'customer_annual_fee_new',
    renewalKey: 'customer_annual_fee_existing',
    newFallback: 499,
    renewalFallback: 399,
  },
  provider: {
    referenceType: 'provider',
    joining: 'provider_registration',
    renewal: 'annual_renewal_provider',
    newKey: 'provider_annual_fee_new',
    renewalKey: 'provider_annual_fee_existing',
    newFallback: 999,
    renewalFallback: 799,
  },
};

/** One year on, handling 29 February the way every calendar does. */
function addYear(d) {
  const out = new Date(d.getTime());
  out.setFullYear(out.getFullYear() + 1);
  return out;
}

/**
 * Where this account stands on its fee.
 *
 * Returns `{ amount, isRenewal, canPay, paidAt, renewsAt }`:
 *
 *   amount      what they would be charged if they paid now
 *   isRenewal   whether that amount is the renewal rate
 *   canPay      whether a payment is currently accepted
 *   renewsAt    when the paid year runs out, or null if we cannot tell
 *
 * `renewsAt` is null when the row is marked paid but no transaction backs it
 * -- seeded data, or an account an administrator marked paid by hand. In that
 * case `canPay` is false: we will not charge somebody a renewal because our
 * own record of when they last paid is missing.
 */
export async function registrationStanding({ kind, referenceId, alreadyPaid }) {
  const k = KINDS[kind];
  if (!k) throw new Error(`unknown fee kind: ${kind}`);

  const [joining, renewal] = await Promise.all([
    getConfigNumber(k.newKey, k.newFallback),
    getConfigNumber(k.renewalKey, k.renewalFallback),
  ]);

  if (!alreadyPaid) {
    return { amount: joining, isRenewal: false, canPay: true, paidAt: null, renewsAt: null };
  }

  const [last] = await query(
    `SELECT created_at FROM transactions
      WHERE reference_type = ? AND reference_id = ?
        AND transaction_type IN (?, ?)
        AND status = 'success'
      ORDER BY created_at DESC
      LIMIT 1`,
    [k.referenceType, referenceId, k.joining, k.renewal]
  );

  if (!last) {
    return { amount: renewal, isRenewal: true, canPay: false, paidAt: null, renewsAt: null };
  }

  const paidAt = new Date(last.created_at);
  const renewsAt = addYear(paidAt);
  return {
    amount: renewal,
    isRenewal: true,
    canPay: renewsAt <= new Date(),
    paidAt,
    renewsAt,
  };
}

/** The transaction_type to write for a payment in this standing. */
export function transactionTypeFor(kind, isRenewal) {
  const k = KINDS[kind];
  return isRenewal ? k.renewal : k.joining;
}
