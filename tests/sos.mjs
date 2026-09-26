// Proves an emergency alert is raised, recorded, and reaches the office.
//
// The behaviour that matters most is the one that is easiest to get wrong:
// with no SMS provider configured the alert must still be recorded, and the
// app must be told plainly that nothing was sent. A screen that says "your
// family has been notified" when no message left is worse than saying nothing,
// because it stops somebody picking up the phone themselves.

const BASE = process.env.SATHIYAA_API ?? process.env.API_BASE ?? 'http://localhost:4000/api/v1';
const KEY = process.env.API_ACCESS_KEY ?? '';
const MOBILE = process.env.TEST_CUSTOMER ?? '9700000000';

let pass = 0;
let fail = 0;

function check(label, ok, detail = '') {
  if (ok) { console.log(`  PASS  ${label}`); pass++; }
  else { console.log(`  FAIL  ${label}${detail ? ` — ${detail}` : ''}`); fail++; }
}

async function api(path, { method = 'GET', body, token } = {}) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      'X-Device-Id': 'test-sos',
      ...(KEY ? { 'X-Sathiyaa-Key': KEY } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let data;
  try { data = text ? JSON.parse(text) : {}; } catch { data = { raw: text }; }
  return { status: res.status, data };
}

console.log('\nEmergency alerts\n');

// --- customer side ------------------------------------------------------------
const otp = await api('/auth/customer/login', { method: 'POST', body: { mobile: MOBILE } });
if (otp.status !== 200 || !otp.data.devOtp) {
  console.log(`  FAIL  could not sign in as ${MOBILE} (status ${otp.status})`);
  process.exit(1);
}
const verify = await api('/auth/customer/verify-otp', {
  method: 'POST', body: { mobile: MOBILE, otp: otp.data.devOtp },
});
const token = verify.data.token;
check('signed in as the seeded customer', !!token);
if (!token) process.exit(1);

const raised = await api('/customers/me/sos', {
  method: 'POST',
  token,
  body: {
    latitude: 23.0293,
    longitude: 72.6176,
    addressText: '12 Shanti Nagar, Indiranagar, Ahmedabad',
    note: 'Automated test — please ignore.',
  },
});
check('alert raised', raised.status === 201,
  `status ${raised.status} ${JSON.stringify(raised.data).slice(0, 160)}`);
check('it has an id, so it can be found again', !!raised.data.alertId);
check('it says who it tried to reach', Array.isArray(raised.data.recipients));
check('it carries a map link for the location given', !!raised.data.mapsUrl);

// The honesty check. With SMS on `stub`, delivery must say simulated — not
// "sent", and not silence.
check('with no SMS provider it reports "simulated", not success',
  raised.data.delivery === 'simulated' || raised.data.smsIsLive === true,
  `delivery=${raised.data.delivery} smsIsLive=${raised.data.smsIsLive}`);
check('  ...and names the provider so the app can say which', !!raised.data.smsProvider,
  `got ${raised.data.smsProvider}`);

// --- an alert with nothing but the button press --------------------------------
const bare = await api('/customers/me/sos', { method: 'POST', token, body: {} });
check('an alert with no location and no note is still accepted', bare.status === 201,
  `status ${bare.status}`);

// --- the customer can see their own --------------------------------------------
const mine = await api('/customers/me/sos', { token });
check('the customer can see their own alerts', (mine.data.alerts ?? []).length >= 2,
  `got ${(mine.data.alerts ?? []).length}`);

// --- the office can see them ----------------------------------------------------
const admin = await api('/auth/admin/login', {
  method: 'POST',
  body: { email: 'admin@sathiyaa.com', password: process.env.ADMIN_PASSWORD ?? 'Admin@123' },
});
check('admin signed in', admin.status === 200, `status ${admin.status}`);
const adminToken = admin.data.token;

if (adminToken) {
  const all = await api('/admin/sos', { token: adminToken });
  check('the office sees the alert', (all.data.alerts ?? []).some((a) => a.id === raised.data.alertId));
  check('  ...with the customer named and a number to call',
    (all.data.alerts ?? []).some((a) => a.id === raised.data.alertId && a.customerName && a.customerMobile));
  check('  ...and an open count to act on', typeof all.data.openCount === 'number',
    `got ${all.data.openCount}`);

  // Closing without saying what happened is how an alert gets quietly buried.
  const blank = await api(`/admin/sos/${raised.data.alertId}/acknowledge`, {
    method: 'POST', token: adminToken, body: { resolution: '' },
  });
  check('closing an alert with no explanation is refused', blank.status === 400,
    `status ${blank.status}`);

  const closed = await api(`/admin/sos/${raised.data.alertId}/acknowledge`, {
    method: 'POST', token: adminToken, body: { resolution: 'Automated test. Called, no emergency.' },
  });
  check('closing it with a note works', closed.status === 200, `status ${closed.status}`);

  const twice = await api(`/admin/sos/${raised.data.alertId}/acknowledge`, {
    method: 'POST', token: adminToken, body: { resolution: 'again' },
  });
  check('closing it a second time is refused', twice.status === 409, `status ${twice.status}`);

  // Tidy the second one away too.
  if (bare.data.alertId) {
    await api(`/admin/sos/${bare.data.alertId}/acknowledge`, {
      method: 'POST', token: adminToken, body: { resolution: 'Automated test.' },
    });
  }
  console.log('  (both test alerts closed)');
}

console.log(`\n=== ${pass}/${pass + fail} passed ===\n`);
process.exit(fail === 0 ? 0 : 1);
