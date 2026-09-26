import { expireUnpaidBookings } from './expireUnpaidBookings.js';

const INTERVAL_MS = 60 * 1000; // run every minute — fine for an MVP; swap for real cron/queue at scale

let handle = null;

export function startJobs() {
  if (handle) return;
  handle = setInterval(() => {
    expireUnpaidBookings().catch((err) => console.error('[jobs] expireUnpaidBookings failed:', err));
  }, INTERVAL_MS);
  // also do an immediate first pass on boot
  expireUnpaidBookings().catch((err) => console.error('[jobs] expireUnpaidBookings failed:', err));
  console.log(`[jobs] background sweep started (every ${INTERVAL_MS / 1000}s)`);
}

export function stopJobs() {
  if (handle) {
    clearInterval(handle);
    handle = null;
  }
}
