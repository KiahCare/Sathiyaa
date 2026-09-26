/**
 * Firebase Cloud Messaging — the push channel the spec needs for "running
 * late", payment reminders, new booking requests and broadcast messages.
 *
 * Written and ready, but only used when `PUSH_PROVIDER=fcm`.
 *
 *   PUSH_PROVIDER=fcm
 *   FCM_PROJECT_ID=sathiyaa-xxxx
 *   FCM_CLIENT_EMAIL=firebase-adminsdk-...@....iam.gserviceaccount.com
 *   FCM_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMII...\n-----END PRIVATE KEY-----\n"
 *
 * All three come from one file: Firebase console -> Project settings ->
 * Service accounts -> Generate new private key. Keep the newlines in the key
 * escaped as \n, which is why env.js unescapes them.
 *
 * FCM's HTTP v1 API wants an OAuth access token rather than a static key, so
 * this signs a short-lived JWT with the service-account key and swaps it for
 * one. `jsonwebtoken` is already a dependency, so still no new packages.
 *
 * Devices have to register their token first — there is no device-token table
 * yet, so `sendToUser` is a no-op that logs until one exists. That table is
 * the remaining piece of push, and it needs the Flutter side
 * (`firebase_messaging`) to have something to send.
 */
import jwt from 'jsonwebtoken';

import { env } from '../../config/env.js';
import { httpJson, requireConfig } from './_shared.js';

let cachedToken = null;
let cachedUntil = 0;

async function accessToken() {
  requireConfig('FCM', {
    FCM_PROJECT_ID: env.fcm.projectId,
    FCM_CLIENT_EMAIL: env.fcm.clientEmail,
    FCM_PRIVATE_KEY: env.fcm.privateKey,
  });

  const now = Math.floor(Date.now() / 1000);
  // Re-use the token until a minute before it lapses.
  if (cachedToken && now < cachedUntil - 60) return cachedToken;

  const assertion = jwt.sign(
    {
      iss: env.fcm.clientEmail,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    },
    env.fcm.privateKey,
    { algorithm: 'RS256' }
  );

  const res = await httpJson('FCM', 'https://oauth2.googleapis.com/token', {
    method: 'POST',
    form: { grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion },
  });
  cachedToken = res.access_token;
  cachedUntil = now + (res.expires_in || 3600);
  return cachedToken;
}

/** Sends to one device token. */
export async function sendToToken({ token, title, body, data }) {
  const bearer = await accessToken();
  return httpJson('FCM', `https://fcm.googleapis.com/v1/projects/${env.fcm.projectId}/messages:send`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${bearer}` },
    body: {
      message: {
        token,
        notification: { title, body },
        // Data values must all be strings, or FCM rejects the message.
        data: Object.fromEntries(Object.entries(data || {}).map(([k, v]) => [k, String(v)])),
        android: { priority: 'high' },
      },
    },
  });
}

/**
 * Sends to a person rather than a device.
 *
 * There is no `device_tokens` table yet, so this logs and returns instead of
 * throwing — enabling push must not break flows that merely try to notify.
 */
export async function sendToUser({ userType, userId, title, body, data }) {
  console.log(
    `[fcm.sendToUser] no device_tokens table yet — would notify ${userType}#${userId}: ${title} / ${body}`
  );
  return { sent: false, provider: 'fcm', reason: 'no_device_token_registry', userType, userId, title, data };
}
