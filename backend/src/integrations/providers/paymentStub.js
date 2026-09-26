/**
 * Payment gateway integration stub.
 * Swap in Razorpay/Stripe here — this file is the ONLY place that needs
 * to change. Keep the exported function signatures stable.
 */

/**
 * Create a payment order for a given amount.
 * Real impl: call razorpay.orders.create({ amount, currency, receipt }).
 */
export async function createOrder({ amount, currency = 'INR', receipt }) {
  await new Promise((r) => setTimeout(r, 50)); // simulate network latency
  return {
    orderId: `mock_order_${Date.now()}_${Math.floor(Math.random() * 1e6)}`,
    amount,
    currency,
    receipt,
    status: 'created',
  };
}

/**
 * Verify a payment (webhook/signature verification in a real gateway).
 * Stub: always succeeds and returns a mock gateway reference id.
 */
export async function verifyPayment({ orderId, paymentRef }) {
  await new Promise((r) => setTimeout(r, 50));
  return {
    verified: true,
    gateway: 'mock_gateway',
    gatewayRefId: paymentRef || `mock_pay_${Date.now()}`,
    status: 'success',
  };
}
