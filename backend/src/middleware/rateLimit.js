import rateLimit from 'express-rate-limit';

import { env } from '../config/env.js';

/**
 * Request throttling, in two strengths.
 *
 * The limits are deliberately generous for ordinary traffic and tight on the
 * endpoints that hand something back for free: issuing a one-time code, and
 * trying a password. Both are cheap to call and expensive to get wrong — the
 * first becomes an SMS bill the moment a provider is wired up, the second is a
 * brute-force surface for as long as an account has a password.
 *
 * Counting is per IP and in memory, which is right for one instance and wrong
 * for several. If this ever runs behind a load balancer with more than one box,
 * move the store to Redis before trusting these numbers.
 */

const envelope = (message) => ({
  handler: (req, res) => res.status(429).json({ error: { code: 'RATE_LIMITED', message } }),
  standardHeaders: 'draft-7',
  legacyHeaders: false,
});

/** Everything. Wide enough that a person tapping around never sees it. */
export const generalLimiter = rateLimit({
  windowMs: 5 * 60 * 1000,
  limit: env.publicDeployment ? 600 : 100000,
  ...envelope('Too many requests. Wait a minute and try again.'),
});

/**
 * Sign-in and code-request endpoints.
 *
 * Twenty attempts in a quarter of an hour is more than anyone mistyping a PIN
 * needs, and far less than a dictionary attack wants.
 */
export const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: env.publicDeployment ? 20 : 100000,
  skipSuccessfulRequests: false,
  ...envelope('Too many attempts from this device. Try again in fifteen minutes.'),
});
