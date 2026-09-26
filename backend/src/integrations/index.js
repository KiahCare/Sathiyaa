/**
 * Which integrations are real, and are they configured?
 *
 * Called once at boot. Two jobs:
 *
 *  1. Print a table, so it is never a mystery whether a running server is
 *     charging real cards or pretending to.
 *  2. Fail fast. If someone sets `PAYMENT_PROVIDER=razorpay` and forgets the
 *     secret, the server refuses to start and names the missing variable —
 *     far better than discovering it when the first customer taps Pay.
 */
import { env } from '../config/env.js';
import * as payment from './payment.js';
import * as sms from './sms.js';
import * as faceMatch from './faceMatch.js';
import * as maps from './maps.js';
import * as push from './push.js';
import * as call from './call.js';

/** What each live provider cannot run without. */
const REQUIRED = {
  razorpay: ['RAZORPAY_KEY_ID', 'RAZORPAY_KEY_SECRET'],
  msg91: ['MSG91_AUTH_KEY', 'MSG91_OTP_TEMPLATE_ID'],
  twilio: ['TWILIO_ACCOUNT_SID', 'TWILIO_AUTH_TOKEN', 'TWILIO_FROM_NUMBER'],
  azure: ['AZURE_FACE_ENDPOINT', 'AZURE_FACE_KEY'],
  // The region has a default, so it is not listed: a missing one would run
  // in ap-south-1, which is where everything else already is.
  rekognition: ['AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY'],
  google: ['GOOGLE_MAPS_API_KEY'],
  // OpenStreetMap needs no account, so there is nothing to check.
  osm: [],
  fcm: ['FCM_PROJECT_ID', 'FCM_CLIENT_EMAIL', 'FCM_PRIVATE_KEY'],
  exotel: ['EXOTEL_SID', 'EXOTEL_API_KEY', 'EXOTEL_API_TOKEN', 'EXOTEL_CALLER_ID'],
};

export function integrationStatus() {
  return [
    { name: 'Payment', provider: payment.providerName, live: payment.isLive, envVar: 'PAYMENT_PROVIDER' },
    { name: 'SMS / OTP', provider: sms.providerName, live: sms.isLive, envVar: 'SMS_PROVIDER' },
    { name: 'Face match', provider: faceMatch.providerName, live: faceMatch.isLive, envVar: 'FACE_PROVIDER' },
    { name: 'Maps', provider: maps.providerName, live: maps.isLive, envVar: 'MAPS_PROVIDER' },
    { name: 'Push', provider: push.providerName, live: push.isLive, envVar: 'PUSH_PROVIDER' },
    { name: 'Masked calls', provider: call.providerName, live: call.isLive, envVar: 'CALL_PROVIDER' },
  ];
}

/** Throws if any selected live provider is missing credentials. */
export function assertIntegrationsConfigured() {
  const problems = [];
  for (const row of integrationStatus()) {
    if (!row.live) continue;
    const needed = REQUIRED[row.provider] || [];
    const missing = needed.filter((key) => !process.env[key]);
    if (missing.length) {
      problems.push(`  ${row.name}: ${row.envVar}=${row.provider} but missing ${missing.join(', ')}`);
    }
  }
  if (problems.length) {
    throw new Error(
      `Integrations are selected but not configured:\n${problems.join('\n')}\n` +
        `Either supply those variables, or unset the *_PROVIDER variable to fall back to the stub.`
    );
  }
}

export function logIntegrationStatus() {
  const rows = integrationStatus();
  const liveCount = rows.filter((r) => r.live).length;

  console.log('[integrations] ' + (liveCount === 0
    ? 'all stubbed - nothing is charged, sent, or called out to.'
    : `${liveCount} live, ${rows.length - liveCount} stubbed.`));

  for (const r of rows) {
    const tag = r.live ? 'LIVE' : 'stub';
    console.log(`               ${tag.padEnd(4)}  ${r.name.padEnd(12)} ${r.provider}`);
  }

  if (liveCount > 0 && !env.isProd) {
    console.log('[integrations] NOTE: live providers are enabled outside production. ' +
      'Make sure these are test/sandbox credentials.');
  }
}
