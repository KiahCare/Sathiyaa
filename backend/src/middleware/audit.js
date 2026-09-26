import { query } from '../db/pool.js';

/**
 * Writes one audit_log row. Used directly by background jobs (user_type
 * 'system') and via req.audit(...) (attached by attachAudit middleware)
 * from controllers.
 */
export async function writeAuditLog({
  userType = 'system',
  userId = null,
  userName = null,
  deviceId = null,
  locationId = null,
  formName,
  action,
  metadata = null,
}) {
  try {
    await query(
      `INSERT INTO audit_log (user_type, user_id, user_name, device_id, location_id, form_name, action, metadata)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        userType,
        userId,
        userName,
        deviceId,
        locationId,
        formName,
        action,
        metadata ? JSON.stringify(metadata) : null,
      ]
    );
  } catch (err) {
    // Audit logging must never break the request it's attached to.
    console.error('[audit] failed to write audit_log row:', err.message);
  }
}

/**
 * Middleware: attaches req.audit(formName, action, metadata) which
 * captures user_type/user_id/user_name from req.user (if authenticated)
 * and device_id/location_id from request headers, so controllers just
 * call `await req.audit('CustomerLogin', 'LOGIN')` after a successful
 * mutation instead of hand-rolling the insert every time.
 *
 * Pre-auth flows (register / verify-otp / login) don't have req.user set
 * by the JWT middleware yet — those controllers pass a 4th `overrideUser`
 * arg ({ role, id, name }) once they know who just registered/logged in,
 * so the row still attributes to the right person instead of 'system'.
 */
export function attachAudit(req, res, next) {
  const deviceId = req.headers['x-device-id'] || null;
  const locationId = req.headers['x-location'] || null;

  req.audit = (formName, action, metadata = null, overrideUser = null) => {
    const user = overrideUser || req.user || {};
    return writeAuditLog({
      userType: user.role || 'system',
      userId: user.id || null,
      userName: user.name || null,
      deviceId,
      locationId,
      formName,
      action,
      metadata,
    });
  };

  next();
}
