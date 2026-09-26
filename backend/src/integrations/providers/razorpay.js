/**
 * Razorpay payment gateway.
 *
 * Written and ready, but only used when `PAYMENT_PROVIDER=razorpay`. Uses the
 * REST API over plain HTTPS rather than the SDK, so there is no extra
 * dependency to keep current and nothing to install before it works.
 *
 * Enable it with:
 *   PAYMENT_PROVIDER=razorpay
 *   RAZORPAY_KEY_ID=rzp_test_xxxxxxxx
 *   RAZORPAY_KEY_SECRET=xxxxxxxx
 *   RAZORPAY_WEBHOOK_SECRET=xxxxxxxx   (only needed for webhooks)
 *
 * Start with the `rzp_test_` keys — they behave identically and move no money.
 */
import crypto from 'node:crypto';

import { env } from '../../config/env.js';
import { basicAuth, httpJson, requireConfig } from './_shared.js';

const BASE = 'https://api.razorpay.com/v1';

function auth() {
  requireConfig('Razorpay', {
    RAZORPAY_KEY_ID: env.razorpay.keyId,
    RAZORPAY_KEY_SECRET: env.razorpay.keySecret,
  });
  return basicAuth(env.razorpay.keyId, env.razorpay.keySecret);
}

/** Razorpay works in paise; every amount in this codebase is in rupees. */
function toPaise(rupees) {
  return Math.round(Number(rupees) * 100);
}

export async function createOrder({ amount, currency = 'INR', receipt }) {
  const order = await httpJson('Razorpay', `${BASE}/orders`, {
    method: 'POST',
    headers: { Authorization: auth() },
    body: {
      amount: toPaise(amount),
      currency,
      receipt: receipt ? String(receipt).slice(0, 40) : undefined,
      payment_capture: 1,
    },
  });

  return {
    orderId: order.id,
    amount,
    currency: order.currency,
    receipt: order.receipt,
    status: order.status,
    // The app needs the public key id to open the checkout sheet.
    keyId: env.razorpay.keyId,
  };
}

/**
 * Confirms a payment really happened.
 *
 * The client sends back `razorpay_order_id`, `razorpay_payment_id` and
 * `razorpay_signature`; the signature is an HMAC of the first two under the
 * key secret. Checking it is what stops a client simply claiming it paid.
 * The payment is then re-read from the API, because a valid signature on a
 * failed payment is still a failed payment.
 */
export async function verifyPayment({ orderId, paymentRef, signature }) {
  requireConfig('Razorpay', {
    RAZORPAY_KEY_ID: env.razorpay.keyId,
    RAZORPAY_KEY_SECRET: env.razorpay.keySecret,
  });

  if (!orderId || !paymentRef) {
    return { verified: false, gateway: 'razorpay', status: 'failed', reason: 'missing_order_or_payment_id' };
  }

  if (signature) {
    const expected = crypto
      .createHmac('sha256', env.razorpay.keySecret)
      .update(`${orderId}|${paymentRef}`)
      .digest('hex');
    if (!timingSafeEqual(expected, signature)) {
      return { verified: false, gateway: 'razorpay', status: 'failed', reason: 'signature_mismatch' };
    }
  }

  const payment = await httpJson('Razorpay', `${BASE}/payments/${encodeURIComponent(paymentRef)}`, {
    headers: { Authorization: auth() },
  });

  const ok = payment.status === 'captured' || payment.status === 'authorized';
  return {
    verified: ok,
    gateway: 'razorpay',
    gatewayRefId: payment.id,
    status: ok ? 'success' : payment.status,
    amount: payment.amount / 100,
    method: payment.method,
  };
}

/**
 * Refunds, which the cancellation-fee tiers need: a customer cancelling more
 * than 36 hours out is owed their booking charge back.
 */
export async function refund({ paymentRef, amount, reason }) {
  const body = { speed: 'normal', notes: reason ? { reason } : undefined };
  if (amount != null) body.amount = toPaise(amount);

  const res = await httpJson('Razorpay', `${BASE}/payments/${encodeURIComponent(paymentRef)}/refund`, {
    method: 'POST',
    headers: { Authorization: auth() },
    body,
  });
  return { refundId: res.id, amount: res.amount / 100, status: res.status, gateway: 'razorpay' };
}

/**
 * Validates a webhook body against the webhook secret. Razorpay signs the raw
 * body, so the caller must pass the exact bytes received — not a re-serialized
 * object.
 */
export function verifyWebhook(rawBody, signature) {
  requireConfig('Razorpay webhooks', { RAZORPAY_WEBHOOK_SECRET: env.razorpay.webhookSecret });
  const expected = crypto.createHmac('sha256', env.razorpay.webhookSecret).update(rawBody).digest('hex');
  return timingSafeEqual(expected, signature || '');
}

/** Constant-time compare, so a wrong signature leaks nothing through timing. */
function timingSafeEqual(a, b) {
  const bufA = Buffer.from(String(a));
  const bufB = Buffer.from(String(b));
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}
