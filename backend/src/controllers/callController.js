import { query } from '../db/pool.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { Errors } from '../utils/apiError.js';
import * as calls from '../integrations/call.js';

/**
 * Non-functional requirement: phone calls between customer and provider
 * must never expose either party's real number. The number returned here is
 * a Sathiyaa number that bridges the two parties; with CALL_PROVIDER=exotel
 * that bridge is real, and by default it is a minted placeholder. Either way
 * neither real number is ever sent to the other side.
 */
export const startMaskedCall = asyncHandler(async (req, res) => {
  const { id } = req.params; // booking id
  const role = req.user.role;
  let sql = 'SELECT * FROM bookings WHERE booking_id = ?';
  const params = [id];
  if (role === 'customer') { sql += ' AND customer_id = ?'; params.push(req.user.id); }
  else if (role === 'provider') { sql += ' AND confirmed_provider_id = ?'; params.push(req.user.id); }
  else throw Errors.forbidden('Only customer or provider can initiate a masked call');

  const [booking] = await query(sql, params);
  if (!booking) throw Errors.notFound('Booking not found');

  const virtualNumber = calls.virtualNumber();
  const expiresAt = new Date(Date.now() + 30 * 60 * 1000);
  const result = await query('INSERT INTO masked_call_sessions (booking_id, virtual_number, expires_at) VALUES (?, ?, ?)', [
    booking.booking_id, virtualNumber, expiresAt,
  ]);
  await req.audit('MaskedCallStart', 'CREATE', { bookingId: booking.booking_id });

  res.status(201).json({
    callSessionId: result.insertId,
    virtualNumber,
    expiresAt,
    provider: calls.providerName,
    message: 'Dial this number; it bridges to the other party without exposing either real number.',
  });
});
