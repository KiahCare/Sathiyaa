/**
 * Cancellation fee tiers (per MVP requirements):
 *  - < 24h before start:  no refund (100% fee)
 *  - 24h-36h before start: 50% fee / 50% refund
 *  - >= 36h before start:  full refund, no fee
 *
 * `baseAmount` is the amount already collected for the booking, i.e.
 * bookings.booking_charge_amount (the upfront confirmation charge — the
 * schema does not model an upfront full-service payment, only this
 * booking charge, so this is the only amount there is to fee/refund
 * against at cancellation time).
 */
export function computeCancellation({ hoursBeforeStart, baseAmount }) {
  const amount = Number(baseAmount) || 0;
  let feeAmount;
  let refundAmount;
  let tier;

  if (hoursBeforeStart < 24) {
    tier = 'no_refund';
    feeAmount = amount;
    refundAmount = 0;
  } else if (hoursBeforeStart < 36) {
    tier = 'fifty_percent_fee';
    feeAmount = round2(amount * 0.5);
    refundAmount = round2(amount - feeAmount);
  } else {
    tier = 'full_refund';
    feeAmount = 0;
    refundAmount = amount;
  }

  return { tier, feeAmount, refundAmount };
}

/** hours between now and the booking's scheduled start (start_date + time_from) */
export function hoursUntilStart(startDate, timeFrom, now = new Date()) {
  const startDateTime = new Date(`${startDate}T${timeFrom}`);
  const diffMs = startDateTime.getTime() - now.getTime();
  return diffMs / (1000 * 60 * 60);
}

function round2(n) {
  return Math.round(n * 100) / 100;
}
