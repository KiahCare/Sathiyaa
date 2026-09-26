import { query } from '../db/pool.js';
import { Errors } from '../utils/apiError.js';

/**
 * Messages on a booking.
 *
 * The rule that shapes all of it: **a thread exists only where a booking
 * does.** A customer can write to the carer coming to their house; a carer can
 * write to the family they are visiting. Neither can write to anybody else.
 *
 * That is not a shortcut to be widened later. An open messaging surface
 * between strangers on a care platform is a safeguarding problem — the booking
 * is what makes the conversation legitimate, and taking it away takes away the
 * only thing that does.
 */

/** Statuses where a thread makes sense. */
const OPEN_STATES = ['confirmed', 'in_progress', 'completed'];

/**
 * Loads a booking and confirms this person is one of the two sides of it.
 *
 * Returns the booking, or throws. Never leaks whether a booking exists to
 * somebody who is not on it: the same 404 either way, because a different
 * answer for "not yours" and "no such booking" is a way to enumerate them.
 */
export async function assertOnBooking(bookingId, { role, id }) {
  const [booking] = await query(
    `SELECT b.*, c.name AS customer_name, p.name AS provider_name
       FROM bookings b
       JOIN customers c ON c.customer_id = b.customer_id
       LEFT JOIN service_providers p ON p.provider_id = b.confirmed_provider_id
      WHERE b.booking_id = ?`,
    [bookingId]
  );
  if (!booking) throw Errors.notFound('Booking not found');

  const isCustomer = role === 'customer' && booking.customer_id === id;
  const isProvider =
    role === 'provider' &&
    (booking.confirmed_provider_id === id || booking.assigned_employee_id === id);

  if (!isCustomer && !isProvider) throw Errors.notFound('Booking not found');

  if (!OPEN_STATES.includes(booking.status)) {
    throw Errors.conflict(
      'THREAD_CLOSED',
      booking.status === 'searching' || booking.status === 'pending_payment'
        ? 'Messages open once a carer has accepted and the booking is confirmed.'
        : 'This booking is closed, so the conversation is closed with it.'
    );
  }

  return booking;
}

export async function listMessages(bookingId) {
  return query(
    `SELECT id, sender_type AS senderType, sender_id AS senderId, body,
            read_at AS readAt, created_at AS createdAt
       FROM booking_messages
      WHERE booking_id = ?
      ORDER BY created_at ASC, id ASC`,
    [bookingId]
  );
}

export async function postMessage(bookingId, { senderType, senderId, body }) {
  const text = String(body ?? '').trim();
  if (!text) throw Errors.badRequest('VALIDATION', 'A message needs something in it.');
  if (text.length > 1000) {
    throw Errors.badRequest('VALIDATION', 'That is longer than a message should be — 1000 characters at most.');
  }

  const result = await query(
    'INSERT INTO booking_messages (booking_id, sender_type, sender_id, body) VALUES (?, ?, ?, ?)',
    [bookingId, senderType, senderId ?? null, text]
  );

  const [row] = await query(
    `SELECT id, sender_type AS senderType, sender_id AS senderId, body,
            read_at AS readAt, created_at AS createdAt
       FROM booking_messages WHERE id = ?`,
    [result.insertId]
  );
  return row;
}

/**
 * Marks everything the *other* side wrote as read.
 *
 * Only the other side: marking your own messages read would zero your own
 * badge and leave theirs, which is the wrong way round and the classic bug in
 * a two-sided thread.
 */
export async function markRead(bookingId, readerType) {
  const theirs = readerType === 'customer' ? 'provider' : 'customer';
  const result = await query(
    `UPDATE booking_messages
        SET read_at = NOW()
      WHERE booking_id = ? AND sender_type IN (?, 'system') AND read_at IS NULL`,
    [bookingId, theirs]
  );
  return result.affectedRows;
}

/** How many messages are waiting for this person, per booking. */
export async function unreadCounts(bookingIds, readerType) {
  if (bookingIds.length === 0) return {};
  const theirs = readerType === 'customer' ? 'provider' : 'customer';
  const placeholders = bookingIds.map(() => '?').join(',');
  const rows = await query(
    `SELECT booking_id AS bookingId, COUNT(*) AS n
       FROM booking_messages
      WHERE booking_id IN (${placeholders})
        AND sender_type IN (?, 'system')
        AND read_at IS NULL
      GROUP BY booking_id`,
    [...bookingIds, theirs]
  );
  return Object.fromEntries(rows.map((r) => [r.bookingId, Number(r.n)]));
}

/**
 * A note written into the thread by the app itself.
 *
 * Used for the things that happen rather than are said — the visit started,
 * the carer is running late — so the history reads as one sequence instead of
 * two that have to be merged in the reader's head.
 *
 * Never throws into the caller: a booking that could not have a note added is
 * not a reason to fail the thing that happened.
 */
export async function systemNote(bookingId, body) {
  try {
    await query(
      "INSERT INTO booking_messages (booking_id, sender_type, sender_id, body) VALUES (?, 'system', NULL, ?)",
      [bookingId, String(body).slice(0, 1000)]
    );
  } catch (err) {
    console.error('[messages] could not write a system note:', err.message);
  }
}
