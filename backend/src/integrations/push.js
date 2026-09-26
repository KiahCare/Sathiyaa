/**
 * Push notifications.
 *
 * New in this pass: "running late", payment reminders and broadcasts were
 * previously persisted but never delivered anywhere. They now go through here,
 * which by default logs rather than sending — so the behaviour is unchanged
 * until `PUSH_PROVIDER=fcm`, but there is now exactly one place to switch on.
 */
import { env } from '../config/env.js';
import * as fcm from './providers/fcm.js';

const useFcm = env.integrations.push === 'fcm';

export const providerName = useFcm ? 'fcm' : 'stub';
export const isLive = useFcm;

/**
 * Notifies a person. Never throws: a notification failing must not roll back
 * the thing it was announcing. A provider who marked themselves late is late
 * whether or not the message got through.
 */
export async function notify({ userType, userId, title, body, data }) {
  try {
    if (useFcm) return await fcm.sendToUser({ userType, userId, title, body, data });
    console.log(`[push] ${userType}#${userId}: ${title} — ${body}`);
    return { sent: false, provider: 'stub', userType, userId, title, body, data };
  } catch (err) {
    console.error(`[push] failed to notify ${userType}#${userId}: ${err.message}`);
    return { sent: false, provider: providerName, error: err.message };
  }
}

/** Fan-out for admin broadcasts. */
export async function notifyMany(recipients, { title, body, data }) {
  const results = await Promise.all(recipients.map((r) => notify({ ...r, title, body, data })));
  return { attempted: results.length, sent: results.filter((r) => r.sent).length, provider: providerName };
}
