/**
 * Exotel — number masking, so a customer and a provider can speak without
 * either seeing the other's real number, which is the non-functional
 * requirement "route the call via Sathiyaa number only".
 *
 * Written and ready, but only used when `CALL_PROVIDER=exotel`.
 *
 *   CALL_PROVIDER=exotel
 *   EXOTEL_SID=...
 *   EXOTEL_API_KEY=...
 *   EXOTEL_API_TOKEN=...
 *   EXOTEL_CALLER_ID=0XXXXXXXXXX      (the Exophone shown to both parties)
 *   EXOTEL_SUBDOMAIN=api.exotel.com   (or api.in.exotel.com)
 *
 * Exotel connects the two legs itself: it rings the first party from the
 * Exophone, and on answer dials the second. Neither sees the other's number,
 * and the numbers never leave the server.
 */
import { env } from '../../config/env.js';
import { basicAuth, httpJson, requireConfig } from './_shared.js';

function config() {
  requireConfig('Exotel', {
    EXOTEL_SID: env.exotel.sid,
    EXOTEL_API_KEY: env.exotel.apiKey,
    EXOTEL_API_TOKEN: env.exotel.apiToken,
    EXOTEL_CALLER_ID: env.exotel.callerId,
  });
  return env.exotel;
}

/**
 * Bridges two numbers. `from` is rung first; when they answer, `to` is dialled.
 * Both see `callerId`.
 */
export async function connectCall({ from, to, bookingId }) {
  const cfg = config();
  const res = await httpJson(
    'Exotel',
    `https://${cfg.subdomain}/v1/Accounts/${cfg.sid}/Calls/connect.json`,
    {
      method: 'POST',
      headers: { Authorization: basicAuth(cfg.apiKey, cfg.apiToken) },
      form: {
        From: from,
        To: to,
        CallerId: cfg.callerId,
        CallType: 'trans',
        TimeLimit: 1800, // 30 minutes is plenty for a care call
        ...(bookingId ? { CustomField: `booking:${bookingId}` } : {}),
      },
    }
  );
  const call = res?.Call || {};
  return {
    provider: 'exotel',
    callSid: call.Sid,
    status: call.Status,
    virtualNumber: cfg.callerId,
    // Neither real number is returned — that is the whole point.
  };
}

/** The number the app should display and dial. */
export function virtualNumber() {
  return config().callerId;
}
