import { query } from '../db/pool.js';

/**
 * Records which handset an account is being used from.
 *
 * Until now the only thing stored was one opaque `device_id` string per
 * account — enough to refuse a login from a second phone, and useless for the
 * thing it was wanted for: after something goes wrong on a visit, being able
 * to say which device it actually was.
 *
 * What gets recorded is what the handset reports about itself to any installed
 * app — make, model, OS version, app version — plus the address the request
 * arrived from. Nothing that follows a person between apps: no advertising id,
 * no IMEI. Android stopped handing that out at version 10 and it was the wrong
 * thing to collect before that.
 */

const HEADER = {
  id: 'x-device-id',
  platform: 'x-device-platform',
  manufacturer: 'x-device-manufacturer',
  model: 'x-device-model',
  os: 'x-device-os',
  appVersion: 'x-app-version',
  physical: 'x-device-physical',
};

/**
 * Accounts seen recently, so a burst of requests is one write rather than
 * fifty. Key is "type:id:device", value is when we last wrote.
 *
 * In memory, so it is per process: with more than one instance each keeps its
 * own and the worst case is a few extra upserts. That is the right trade at
 * this size — a Redis round trip to save a single indexed upsert is not a
 * saving.
 */
const recentlySeen = new Map();
const WRITE_EVERY_MS = 5 * 60 * 1000;

/** Stops the map growing without bound on a long-running process. */
function prune(now) {
  if (recentlySeen.size < 5000) return;
  for (const [k, at] of recentlySeen) {
    if (now - at > WRITE_EVERY_MS) recentlySeen.delete(k);
  }
}

/** Trim to the column width rather than letting MySQL truncate silently. */
const fit = (v, n) => (typeof v === 'string' && v.length > 0 ? v.slice(0, n) : null);

/**
 * The address the request actually came from.
 *
 * Express only trusts X-Forwarded-For when `trust proxy` is configured, which
 * app.js does from TRUST_PROXY_HOPS. Reading the header directly here would
 * mean believing whatever a caller claims about itself, which is how a rate
 * limiter gets walked around one invented address at a time.
 */
function callerIp(req) {
  const ip = req.ip || req.socket?.remoteAddress || null;
  // Node reports IPv4 over IPv6 sockets as ::ffff:1.2.3.4. The prefix is noise
  // in a console column.
  return ip ? fit(ip.replace(/^::ffff:/, ''), 45) : null;
}

/**
 * Upserts one row for this account and device. Never throws into the request:
 * a failure to record a device must not stop somebody booking a nurse.
 */
export async function recordDevice(req, user) {
  try {
    const deviceId = fit(req.headers[HEADER.id], 255);
    if (!deviceId || !user?.role || !user?.id) return;
    if (!['customer', 'provider', 'business_agent', 'admin'].includes(user.role)) return;

    const key = `${user.role}:${user.id}:${deviceId}`;
    const now = Date.now();
    const last = recentlySeen.get(key);
    const physicalHeader = req.headers[HEADER.physical];

    // A device whose details changed — an OS upgrade, an app update — is
    // written through immediately rather than waiting out the interval.
    const detailsKey = [
      req.headers[HEADER.model],
      req.headers[HEADER.os],
      req.headers[HEADER.appVersion],
    ].join('|');
    const seenDetails = recentlySeen.get(`${key}:details`);

    if (last && now - last < WRITE_EVERY_MS && seenDetails === detailsKey) return;

    recentlySeen.set(key, now);
    recentlySeen.set(`${key}:details`, detailsKey);
    prune(now);

    await query(
      `INSERT INTO user_devices
         (user_type, user_id, device_id, platform, manufacturer, model,
          os_version, app_version, is_physical, last_ip, last_user_agent, last_seen_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
       ON DUPLICATE KEY UPDATE
         platform        = COALESCE(VALUES(platform), platform),
         manufacturer    = COALESCE(VALUES(manufacturer), manufacturer),
         model           = COALESCE(VALUES(model), model),
         os_version      = COALESCE(VALUES(os_version), os_version),
         app_version     = COALESCE(VALUES(app_version), app_version),
         is_physical     = COALESCE(VALUES(is_physical), is_physical),
         last_ip         = COALESCE(VALUES(last_ip), last_ip),
         last_user_agent = COALESCE(VALUES(last_user_agent), last_user_agent),
         last_seen_at    = NOW()`,
      [
        user.role,
        user.id,
        deviceId,
        fit(req.headers[HEADER.platform], 30),
        fit(req.headers[HEADER.manufacturer], 80),
        fit(req.headers[HEADER.model], 120),
        fit(req.headers[HEADER.os], 60),
        fit(req.headers[HEADER.appVersion], 40),
        physicalHeader === undefined ? null : physicalHeader === 'true',
        callerIp(req),
        fit(req.headers['user-agent'], 255),
      ]
    );
  } catch (err) {
    console.error('[devices] could not record device:', err.message);
  }
}

