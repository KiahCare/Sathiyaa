/**
 * Real SMS delivery — MSG91 and Twilio.
 *
 * Written and ready, but only used when `SMS_PROVIDER` is set. Both are plain
 * REST, so there is no SDK to install.
 *
 *   SMS_PROVIDER=msg91
 *   MSG91_AUTH_KEY=...
 *   MSG91_SENDER_ID=SATHYA          (6 characters, approved on your DLT account)
 *   MSG91_OTP_TEMPLATE_ID=...       (the approved OTP template)
 *   MSG91_SMS_TEMPLATE_ID=...       (approved transactional template)
 *
 *   SMS_PROVIDER=twilio
 *   TWILIO_ACCOUNT_SID=AC...
 *   TWILIO_AUTH_TOKEN=...
 *   TWILIO_FROM_NUMBER=+1...
 *
 * **India, before any of this works:** transactional SMS requires the sender
 * id and every message template to be registered on a DLT platform (Jio,
 * Airtel, Vodafone, BSNL) and approved. Approval typically takes one to two
 * weeks and is a business process, not a code change — start it early. Until
 * it clears, leave SMS_PROVIDER unset and the OTP keeps coming back in the
 * API response for testing.
 */
import { env } from '../../config/env.js';
import { basicAuth, httpJson, requireConfig } from './_shared.js';

/** India is the only market so far; +91 unless a country code is already there. */
function e164(mobileNumber) {
  const digits = String(mobileNumber).replace(/\D/g, '');
  if (digits.length === 10) return `91${digits}`;
  return digits;
}

// ---------------------------------------------------------------- MSG91 ---

async function msg91SendOtp({ mobileNumber, otp }) {
  requireConfig('MSG91', {
    MSG91_AUTH_KEY: env.msg91.authKey,
    MSG91_OTP_TEMPLATE_ID: env.msg91.otpTemplateId,
  });
  const res = await httpJson('MSG91', 'https://control.msg91.com/api/v5/otp', {
    method: 'POST',
    headers: { authkey: env.msg91.authKey },
    body: {
      template_id: env.msg91.otpTemplateId,
      mobile: e164(mobileNumber),
      otp: String(otp),
      // Sathiyaa generates and stores the OTP hash itself, so MSG91 is only
      // being asked to deliver it, not to own it.
      otp_expiry: env.otpTtlMinutes,
    },
  });
  return { sent: res?.type !== 'error', provider: 'msg91', mobileNumber, response: res };
}

async function msg91SendSms({ mobileNumber, message, variables }) {
  requireConfig('MSG91', {
    MSG91_AUTH_KEY: env.msg91.authKey,
    MSG91_SMS_TEMPLATE_ID: env.msg91.smsTemplateId,
    MSG91_SENDER_ID: env.msg91.senderId,
  });
  // DLT requires a pre-approved template; free-text bodies are rejected, so
  // `message` is only a fallback for providers that allow it.
  const res = await httpJson('MSG91', 'https://control.msg91.com/api/v5/flow/', {
    method: 'POST',
    headers: { authkey: env.msg91.authKey },
    body: {
      template_id: env.msg91.smsTemplateId,
      sender: env.msg91.senderId,
      recipients: [{ mobiles: e164(mobileNumber), ...(variables || { message }) }],
    },
  });
  return { sent: res?.type !== 'error', provider: 'msg91', mobileNumber, response: res };
}

// --------------------------------------------------------------- Twilio ---

async function twilioSend({ mobileNumber, body }) {
  requireConfig('Twilio', {
    TWILIO_ACCOUNT_SID: env.twilio.accountSid,
    TWILIO_AUTH_TOKEN: env.twilio.authToken,
    TWILIO_FROM_NUMBER: env.twilio.fromNumber,
  });
  const res = await httpJson(
    'Twilio',
    `https://api.twilio.com/2010-04-01/Accounts/${env.twilio.accountSid}/Messages.json`,
    {
      method: 'POST',
      headers: { Authorization: basicAuth(env.twilio.accountSid, env.twilio.authToken) },
      form: { To: `+${e164(mobileNumber)}`, From: env.twilio.fromNumber, Body: body },
    }
  );
  return { sent: res?.status !== 'failed', provider: 'twilio', mobileNumber, sid: res?.sid };
}

// -------------------------------------------------------------- exports ---

export async function sendOtp({ mobileNumber, otp, purpose = 'login' }) {
  if (env.integrations.sms === 'msg91') return msg91SendOtp({ mobileNumber, otp, purpose });
  return twilioSend({
    mobileNumber,
    body: `${otp} is your Sathiyaa verification code. It expires in ${env.otpTtlMinutes} minutes. Do not share it with anyone.`,
  });
}

export async function sendSms({ mobileNumber, message, variables }) {
  if (env.integrations.sms === 'msg91') return msg91SendSms({ mobileNumber, message, variables });
  return twilioSend({ mobileNumber, body: message });
}
