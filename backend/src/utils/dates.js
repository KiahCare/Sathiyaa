/**
 * Dates as the calendar shows them, not as UTC happens to land.
 *
 * `new Date().toISOString().slice(0, 10)` is the obvious way to get today, and
 * it is wrong everywhere east of Greenwich: it converts to UTC first, so in
 * India it returns *yesterday* for the first five and a half hours of every
 * day. Bookings then land in the wrong tab, "today's" dashboard shows
 * yesterday's work, and a rate set at 1am takes effect a day early -- all of
 * it only between midnight and half past five, which is exactly when nobody
 * is looking.
 */

const pad = (n) => String(n).padStart(2, '0');

/** Today, as YYYY-MM-DD on the server's own calendar. */
export function localToday() {
  return localYmd(new Date());
}

/** Any Date as YYYY-MM-DD on the server's own calendar. */
export function localYmd(d) {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}
