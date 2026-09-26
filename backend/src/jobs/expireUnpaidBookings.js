import { query, withTransaction } from '../db/pool.js';
import { writeAuditLog } from '../middleware/audit.js';
import { env } from '../config/env.js';

/**
 * Two housekeeping sweeps, run on an interval (no real cron daemon needed
 * for this MVP — see jobs/index.js):
 *  1. Bookings stuck in 'pending_payment' past their 15-min payment
 *     deadline -> 'expired', freeing the provider back up.
 *  2. booking_requests still 'pending' long after being sent (the
 *     provider never responded) -> 'expired', so a stale fan-out request
 *     doesn't linger forever in a provider's inbox.
 */
export async function expireUnpaidBookings() {
  const expiredBookings = await query(
    `SELECT booking_id FROM bookings WHERE status = 'pending_payment' AND payment_deadline_at < NOW()`
  );

  for (const b of expiredBookings) {
    await withTransaction(async (conn) => {
      await conn.query('UPDATE bookings SET status = "expired" WHERE booking_id = ? AND status = "pending_payment"', [b.booking_id]);
      await conn.query('UPDATE booking_requests SET status = "invalidated" WHERE booking_id = ? AND status IN ("pending","accepted")', [b.booking_id]);
    });
    await writeAuditLog({ userType: 'system', formName: 'ExpireUnpaidBooking', action: 'EXPIRE', metadata: { bookingId: b.booking_id } });
  }

  const staleThreshold = new Date(Date.now() - env.bookingRequestStaleMinutes * 60 * 1000);
  const result = await query(
    `UPDATE booking_requests SET status = 'expired' WHERE status = 'pending' AND sent_at < ?`,
    [staleThreshold]
  );
  if (result.affectedRows > 0) {
    await writeAuditLog({ userType: 'system', formName: 'ExpireStaleBookingRequests', action: 'EXPIRE', metadata: { count: result.affectedRows } });
  }

  return { expiredBookings: expiredBookings.length, expiredRequests: result.affectedRows };
}
