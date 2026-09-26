// End-to-end smoke test of the documented Sathiyaa happy path, run against a
// live backend + MySQL. Mirrors the curl flow in backend/README.md.
const BASE = process.env.SATHIYAA_API ?? process.env.API_BASE ?? 'http://localhost:4000/api/v1';
// Rotated on any real deployment, so it has to be overridable rather than
// baked in — see _builds/DEPLOY-AWS.md step 3.
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? 'Admin@123';
let step = 0;
const results = [];

async function call(label, method, path, { token, body } = {}) {
  step += 1;
  const res = await fetch(BASE + path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      'X-Device-Id': 'smoke-device-1',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = text; }
  const ok = res.status >= 200 && res.status < 300;
  results.push({ step, label, status: res.status, ok });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${String(step).padStart(2)}. ${label} -> ${res.status}`);
  if (!ok) console.log('        ', JSON.stringify(json).slice(0, 300));
  return json;
}

const mobile = '99999' + String(Math.floor(Math.random() * 90000) + 10000);

const reg = await call('customer register', 'POST', '/auth/customer/register', { body: { name: 'Smoke Customer', mobile } });
const ver = await call('customer verify OTP', 'POST', '/auth/customer/verify-otp', { body: { mobile, otp: reg.devOtp } });
const CT = ver.token;

await call('set primary address', 'PUT', '/customers/me/addresses', {
  token: CT,
  body: { primary: { line1: '123 Smoke St', city: 'Ahmedabad', latitude: 23.0225, longitude: 72.5714 } },
});

// Seeded providers work Mon-Fri (some Mon-Sat), so roll forward to the next
// weekday - a Sunday date legitimately matches nobody.
const d = new Date(Date.now() + 3 * 864e5);
while (d.getDay() === 0 || d.getDay() === 6) d.setDate(d.getDate() + 1);
// Local calendar date, not toISOString(): the latter shifts local midnight
// back to the previous UTC day and silently picks a Sunday.
const localYmd = (d) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const today = localYmd(d);
const search = await call('search providers', 'GET',
  `/providers/search?service_type=companion&date_from=${today}&time_from=09:00:00&time_to=12:00:00&lat=23.0225&lng=72.5714&radius_km=50`);
console.log(`        found ${(search.providers ?? search.data ?? []).length} providers`);

const booking = await call('create booking', 'POST', '/bookings', {
  token: CT,
  body: { serviceType: 'companion', startDate: today, endDate: today, timeFrom: '09:00:00', timeTo: '12:00:00', latitude: 23.0225, longitude: 72.5714 },
});
const bookingId = booking.bookingId ?? booking.booking?.bookingId ?? booking.id;

// Release the provider's device binding before signing in.
//
// This script tests the happy path, not device binding — three-devices.mjs
// tests that, properly, on its own account. But an account is bound to the
// first device that signs in, so whichever of the two scripts ran first left
// this one failing with 403 and every step after it cascading into 401s. That
// is an ordering accident, not a finding, and a suite that depends on the
// order its scripts happen to run in tells you nothing.
//
// Done quietly: a failure here is not a test result, it is housekeeping.
const preAdmin = await fetch(BASE + '/auth/admin/login', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', 'X-Device-Id': 'smoke-device-1' },
  body: JSON.stringify({ email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD }),
}).then((r) => r.json()).catch(() => ({}));

if (preAdmin.token) {
  const list = await fetch(`${BASE}/admin/providers?search=9600000000`, {
    headers: { Authorization: `Bearer ${preAdmin.token}`, 'X-Device-Id': 'smoke-device-1' },
  }).then((r) => r.json()).catch(() => ({}));

  const target = (list.providers ?? []).find((p) => p.mobile_number === '9600000000');
  if (target) {
    await fetch(`${BASE}/admin/providers/${target.provider_id}/reset-device`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${preAdmin.token}`, 'X-Device-Id': 'smoke-device-1' },
    }).catch(() => {});
    console.log('        (released the test provider\'s device binding first)');
  }
}

const plogin = await call('provider PIN login', 'POST', '/auth/provider/login', { body: { mobile: '9600000000', pin: '123456', deviceId: 'smoke-device-1' } });
const PT = plogin.token;

await call('provider location on', 'PUT', '/providers/me', { token: PT, body: { locationOn: true } });
await call('provider location ping', 'PATCH', '/providers/me/location', { token: PT, body: { lat: 23.0225, lng: 72.5714 } });
await call('provider accepts request', 'POST', `/providers/me/requests/${bookingId}/accept`, { token: PT });
await call('customer pays booking fee', 'POST', `/bookings/${bookingId}/pay`, { token: CT, body: {} });
await call('provider starts (face+geofence)', 'POST', `/providers/me/bookings/${bookingId}/start`, { token: PT, body: { selfieUrl: 'https://example.com/s.jpg' } });
const otp = await call('customer reads start OTP', 'GET', `/bookings/${bookingId}/otp`, { token: CT });
await call('provider verifies start OTP', 'POST', `/providers/me/bookings/${bookingId}/verify-start-otp`, { token: PT, body: { otp: otp.otp ?? otp.code } });
const end = await call('provider ends service', 'POST', `/providers/me/bookings/${bookingId}/end`, { token: PT });
console.log('        totals:', JSON.stringify(end.bookingTotals ?? end).slice(0, 200));
await call('customer rates provider', 'POST', `/bookings/${bookingId}/rating`, { token: CT, body: { rating: 5, comments: 'Smoke test' } });

// The seed generates a fresh referral code each run, so sign in by the mobile
// number, which is stable.
const agent = await call('business agent login', 'POST', '/auth/business-agent/login', { body: { identifier: '9800000001', password: 'Partner@123' } });
await call('agent lists referrals', 'GET', '/business-agents/me/referrals', { token: agent.token });

const admin = await call('admin login', 'POST', '/auth/admin/login', { body: { email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD } });
await call('admin lists providers', 'GET', '/admin/providers?status=active', { token: admin.token });
await call('admin reads audit log', 'GET', '/admin/audit-log?limit=5', { token: admin.token });

const failed = results.filter((r) => !r.ok);
console.log(`\n=== ${results.length - failed.length}/${results.length} passed ===`);
if (failed.length) { console.log('failed steps:', failed.map((f) => `${f.step}. ${f.label} (${f.status})`).join(', ')); process.exit(1); }
