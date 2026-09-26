import { timingSafeEqual } from 'node:crypto';

import { env } from '../config/env.js';
import { Errors } from '../utils/apiError.js';

/**
 * A shared key that every caller must present, on top of whatever
 * authentication the endpoint itself requires.
 *
 * This is not a substitute for authentication and is not pretending to be one.
 * It is a door on the building. While the one-time code comes back in the
 * response body, an endpoint anyone can reach is an account anyone can enter;
 * the key means a scanner that stumbles on the hostname gets 401 on every path
 * instead of a working login flow.
 *
 * It is baked into the two apps and into the admin console build, so anybody
 * who unpacks an APK can read it. That is understood. It stops automated
 * discovery and casual poking, which is the realistic threat to a demo server,
 * and it costs one header.
 *
 * When API_ACCESS_KEY is empty the middleware does nothing, so local
 * development is unaffected. Preflight refuses to start a public deployment
 * without one.
 */
export function requireAccessKey(req, res, next) {
  if (!env.accessKey) return next();

  const given = req.get('X-Sathiyaa-Key') || '';
  if (!given) {
    return next(Errors.unauthorized('Missing API access key'));
  }

  // Compare in constant time. The lengths have to match for timingSafeEqual,
  // and a length mismatch is itself a mismatch, so check it first.
  const a = Buffer.from(given);
  const b = Buffer.from(env.accessKey);
  if (a.length !== b.length || !timingSafeEqual(a, b)) {
    return next(Errors.unauthorized('Invalid API access key'));
  }

  next();
}
