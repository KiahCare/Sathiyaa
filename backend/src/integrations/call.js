/**
 * Masked calling.
 *
 * `CALL_PROVIDER` chooses the implementation; the default stub mints a fake
 * virtual number so `masked_call_sessions` and the customer-facing flow work
 * without a telephony account. Either way, neither party's real number is ever
 * returned to the other.
 */
import { env } from '../config/env.js';
import * as exotel from './providers/exotel.js';

const useExotel = env.integrations.call === 'exotel';

export const providerName = useExotel ? 'exotel' : 'stub';
export const isLive = useExotel;

export async function connectCall({ from, to, bookingId }) {
  if (useExotel) return exotel.connectCall({ from, to, bookingId });
  const number = `+91800${String(Math.floor(Math.random() * 1e7)).padStart(7, '0')}`;
  return { provider: 'stub', callSid: `stub_call_${Date.now()}`, status: 'queued', virtualNumber: number };
}

export function virtualNumber() {
  if (useExotel) return exotel.virtualNumber();
  return `+91800${String(Math.floor(Math.random() * 1e7)).padStart(7, '0')}`;
}
