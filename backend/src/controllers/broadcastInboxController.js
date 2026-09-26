/**
 * The receiving end of a broadcast.
 *
 * Before this existed, an admin could send a broadcast and it went nowhere:
 * the row was written, the count was reported, the push adapter logged a line
 * and returned sent:false, and no endpoint anywhere let a customer or provider
 * ask what had been sent to them. Every broadcast in the history showed
 * delivered_count = 0, which was accurate.
 *
 * These three endpoints are the delivery. A phone with no push permission, no
 * Google Play services and no network at the moment of sending still gets the
 * message the next time it opens the app, which is more than push guarantees.
 */
import { query } from '../db/pool.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { Errors } from '../utils/apiError.js';

/** customer | provider, from the token rather than anything the caller sends. */
const who = (req) => ({
  userType: req.user.role === 'provider' ? 'provider' : 'customer',
  userId: req.user.id,
});

/** Everything sent to whoever is asking, newest first. */
export const listMine = asyncHandler(async (req, res) => {
  const { userType, userId } = who(req);
  const limit = Math.min(Number(req.query.limit) || 50, 200);

  const rows = await query(
    `SELECT r.id AS recipient_id, r.read_at,
            b.id AS broadcast_id, b.title, b.message_text, b.image_url, b.sent_at
       FROM broadcast_recipients r
       JOIN broadcast_messages b ON b.id = r.broadcast_id
      WHERE r.user_type = ? AND r.user_id = ?
      ORDER BY b.sent_at DESC
      LIMIT ${limit}`,
    [userType, userId]
  );

  res.json({
    broadcasts: rows.map((r) => ({
      id: r.broadcast_id,
      title: r.title,
      message: r.message_text,
      imageUrl: r.image_url,
      sentAt: r.sent_at,
      read: r.read_at != null,
    })),
    unread: rows.filter((r) => r.read_at == null).length,
  });
});

/** The badge count, without pulling every message down to compute it. */
export const unreadCount = asyncHandler(async (req, res) => {
  const { userType, userId } = who(req);
  const [row] = await query(
    `SELECT COUNT(*) AS n FROM broadcast_recipients
      WHERE user_type = ? AND user_id = ? AND read_at IS NULL`,
    [userType, userId]
  );
  res.json({ unread: Number(row?.n ?? 0) });
});

/**
 * Mark one as read, or all of them.
 *
 * Scoped by the token's own identity in the WHERE clause, so passing somebody
 * else's broadcast id marks nothing rather than marking theirs.
 */
export const markRead = asyncHandler(async (req, res) => {
  const { userType, userId } = who(req);
  const { id } = req.params;

  if (id === 'all') {
    await query(
      `UPDATE broadcast_recipients SET read_at = NOW()
        WHERE user_type = ? AND user_id = ? AND read_at IS NULL`,
      [userType, userId]
    );
    return res.json({ ok: true });
  }

  const broadcastId = Number(id);
  if (!Number.isInteger(broadcastId) || broadcastId <= 0) {
    throw Errors.badRequest('VALIDATION', 'id must be a broadcast id, or "all"');
  }

  const result = await query(
    `UPDATE broadcast_recipients SET read_at = NOW()
      WHERE user_type = ? AND user_id = ? AND broadcast_id = ? AND read_at IS NULL`,
    [userType, userId, broadcastId]
  );
  // affectedRows 0 means it was already read, or was never theirs. Neither is
  // an error worth failing a screen over.
  res.json({ ok: true, changed: result.affectedRows ?? 0 });
});
