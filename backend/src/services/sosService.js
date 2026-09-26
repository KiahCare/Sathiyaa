import { query } from '../db/pool.js';
import { sendSms, isLive as smsIsLive, providerName as smsProvider } from '../integrations/sms.js';

/**
 * Raising an emergency alert.
 *
 * Two rules shape everything here.
 *
 * **The alert is recorded before anything is sent.** If the SMS gateway is
 * down, or misconfigured, or simply not connected yet, the fact that somebody
 * pressed the button still has to survive. "We have no record of that" is the
 * worst answer to give a family afterwards.
 *
 * **Nothing is claimed that did not happen.** With no SMS provider configured
 * the row is marked `simulated` and the app is told so in as many words. A
 * screen that says "your family has been notified" when no message left is
 * worse than one that says nothing — it stops somebody picking up the phone
 * themselves.
 */

/** 160 characters, because a longer message is two messages and two bills. */
function alertText({ customerName, addressText, mapsUrl, note }) {
  const where = addressText ? ` at ${addressText}` : '';
  const link = mapsUrl ? ` ${mapsUrl}` : '';
  const extra = note ? ` Note: ${note}` : '';
  return `SATHIYAA EMERGENCY: ${customerName} has raised an alert${where}.${link}${extra} Please call them now.`;
}

export async function raiseSosAlert({ customer, latitude, longitude, addressText, note, bookingId }) {
  // Everyone worth telling: the family on the account, and the carer if a
  // visit is happening right now — they are the only person already in the
  // building.
  const family = await query(
    `SELECT name, relationship, contact_number
       FROM customer_family_members
      WHERE customer_id = ? AND deleted_at IS NULL`,
    [customer.customer_id]
  );

  let activeCarer = null;
  if (bookingId) {
    const [row] = await query(
      `SELECT p.name, p.mobile_number
         FROM bookings b
         JOIN service_providers p ON p.provider_id = b.confirmed_provider_id
        WHERE b.booking_id = ? AND b.customer_id = ? AND b.status = 'in_progress'`,
      [bookingId, customer.customer_id]
    );
    if (row) activeCarer = row;
  }

  const targets = [
    ...family.map((f) => ({
      name: f.name,
      relationship: f.relationship,
      number: f.contact_number,
    })),
    ...(activeCarer
      ? [{ name: activeCarer.name, relationship: 'Carer on the visit', number: activeCarer.mobile_number }]
      : []),
  ].filter((t) => t.number);

  const mapsUrl =
    latitude != null && longitude != null
      ? `https://www.openstreetmap.org/?mlat=${latitude}&mlon=${longitude}#map=18/${latitude}/${longitude}`
      : null;

  const message = alertText({
    customerName: customer.name,
    addressText,
    mapsUrl,
    note,
  });

  // Recorded first. Everything after this point can fail without losing the
  // fact that an alert was raised.
  const insert = await query(
    `INSERT INTO sos_alerts
       (customer_id, latitude, longitude, address_text, booking_id, note, delivery, notified_count, recipients)
     VALUES (?, ?, ?, ?, ?, ?, 'simulated', 0, ?)`,
    [
      customer.customer_id,
      latitude ?? null,
      longitude ?? null,
      addressText ?? null,
      bookingId ?? null,
      note ?? null,
      JSON.stringify(targets.map((t) => ({ ...t, ok: null }))),
    ]
  );
  const alertId = insert.insertId;

  // One failure must not stop the rest going out, so each is settled on its
  // own rather than with Promise.all, which rejects on the first error.
  const results = await Promise.allSettled(
    targets.map((t) => sendSms({ mobileNumber: t.number, message }))
  );

  const recipients = targets.map((t, i) => {
    const r = results[i];
    return {
      ...t,
      ok: r.status === 'fulfilled',
      error: r.status === 'rejected' ? String(r.reason?.message ?? r.reason).slice(0, 200) : null,
    };
  });

  const okCount = recipients.filter((r) => r.ok).length;

  // `simulated` is its own state, not a kind of success. The distinction is
  // the whole reason the app can be honest on screen.
  const delivery = !smsIsLive
    ? 'simulated'
    : okCount === 0
      ? 'failed'
      : okCount === targets.length
        ? 'sent'
        : 'partial';

  await query(
    'UPDATE sos_alerts SET delivery = ?, notified_count = ?, recipients = ? WHERE id = ?',
    [delivery, okCount, JSON.stringify(recipients), alertId]
  );

  return {
    alertId,
    delivery,
    smsProvider,
    smsIsLive,
    notifiedCount: okCount,
    recipients: recipients.map((r) => ({
      name: r.name,
      relationship: r.relationship,
      number: r.number,
      notified: r.ok,
    })),
    mapsUrl,
    message,
  };
}
