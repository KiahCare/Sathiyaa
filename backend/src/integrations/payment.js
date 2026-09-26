/**
 * Payment gateway.
 *
 * Which implementation runs is decided by `PAYMENT_PROVIDER`, and the default
 * is the stub — so a fresh checkout takes payments "successfully" without an
 * account, keys, or a single rupee moving. Set `PAYMENT_PROVIDER=razorpay`
 * and the same calls go to Razorpay instead; no caller changes.
 */
import { env } from '../config/env.js';
import * as stub from './providers/paymentStub.js';
import * as razorpay from './providers/razorpay.js';

const impl = env.integrations.payment === 'razorpay' ? razorpay : stub;

export const providerName = env.integrations.payment === 'razorpay' ? 'razorpay' : 'stub';
export const isLive = providerName !== 'stub';

export const createOrder = (...args) => impl.createOrder(...args);
export const verifyPayment = (...args) => impl.verifyPayment(...args);

/**
 * Refunds. The stub has nothing to refund, so it reports success without
 * moving anything, which keeps the cancellation flow testable offline.
 */
export const refund = (...args) =>
  impl.refund ? impl.refund(...args) : Promise.resolve({ refundId: `stub_refund_${Date.now()}`, status: 'processed', gateway: 'stub' });

export const verifyWebhook = (...args) => (impl.verifyWebhook ? impl.verifyWebhook(...args) : true);
