import bcrypt from 'bcryptjs';

export function generateOtp() {
  return String(Math.floor(100000 + Math.random() * 900000)); // 6 digits
}

export async function hashOtp(otp) {
  return bcrypt.hash(otp, 8);
}

export async function compareOtp(otp, hash) {
  if (!otp || !hash) return false;
  return bcrypt.compare(String(otp), hash);
}

export function otpExpiryDate(minutes) {
  return new Date(Date.now() + minutes * 60 * 1000);
}
