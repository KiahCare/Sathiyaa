/**
 * SMS/OTP delivery integration stub.
 * Swap in MSG91/Twilio here. Real impl would call the provider's SDK;
 * this stub logs to the console and lets the caller decide whether to
 * echo the OTP back in the API response (only in non-production envs,
 * via the `devOtp` field — see controllers/authController.js).
 */
export async function sendOtp({ mobileNumber, otp, purpose = 'login' }) {
  console.log(`[sms.sendOtp] purpose=${purpose} to=${mobileNumber} otp=${otp}`);
  await new Promise((r) => setTimeout(r, 20));
  return { sent: true, provider: 'mock_sms', mobileNumber };
}

export async function sendSms({ mobileNumber, message }) {
  console.log(`[sms.sendSms] to=${mobileNumber} message="${message}"`);
  await new Promise((r) => setTimeout(r, 20));
  return { sent: true, provider: 'mock_sms', mobileNumber };
}
