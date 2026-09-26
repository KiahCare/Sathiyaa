import { verifyToken } from '../utils/jwt.js';
import { Errors } from '../utils/apiError.js';
import { recordDevice } from './deviceRegistry.js';

/**
 * requireAuth(...roles) — verifies the JWT and (optionally) restricts to
 * a set of roles. Populates req.user = { role, id, name }.
 * With no roles listed, any authenticated user of any role passes.
 */
export function requireAuth(...roles) {
  return (req, res, next) => {
    const header = req.headers.authorization || '';
    const [scheme, token] = header.split(' ');
    if (scheme !== 'Bearer' || !token) {
      return next(Errors.unauthorized('Missing or malformed Authorization header'));
    }
    try {
      const payload = verifyToken(token);
      if (roles.length > 0 && !roles.includes(payload.role)) {
        return next(Errors.forbidden(`Requires role: ${roles.join(' or ')}`));
      }
      req.user = payload;
      // Every authenticated request passes through here, so this is the one
      // place device tracking cannot be forgotten when a route group is added.
      // Deliberately not awaited: recording which handset made a call must
      // never sit between a carer and the booking they are accepting.
      void recordDevice(req, payload);
      next();
    } catch (err) {
      next(Errors.unauthorized('Invalid or expired token'));
    }
  };
}

/** Optional auth: populates req.user if a valid token is present, else continues anonymously. */
export function optionalAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');
  if (scheme === 'Bearer' && token) {
    try {
      req.user = verifyToken(token);
    } catch {
      // ignore invalid token in optional mode
    }
  }
  next();
}
