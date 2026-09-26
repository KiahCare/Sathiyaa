// Proves a customer can pick which carers get asked, rather than the request
// going to everybody in range.
//
// What this is really about: the app used to show one carer's profile and say
// "requesting Lakshmi Iyer" while the server quietly asked every provider who
// matched. Neither half was wrong on its own; together they were a lie. Now the
// customer chooses a shortlist, the server asks exactly those, and the first to
// accept takes the visit.
//
// The shortlist is intersected with the carers who are actually free, not
// trusted outright — somebody off duty or already booked must not receive a
// request they cannot accept, and an id from nowhere must not become one at
// all.
//
// Signs in as a seeded customer and cancels every booking it makes.

const BASE = process.env.SATHIYAA_API ?? process.env.API_BASE ?? 'http://localhost:4000/api/v1';
const KEY = process.env.API_ACCESS_KEY ?? '';
const MOBILE = process.env.TEST_CUSTOMER ?? '9700000000';

let pass = 0;
let fail = 0;

function check(label, ok, detail = '') {
  if (ok) {
    console.log(`  PASS  ${label}`);
    pass++;
  } else {
    console.log(`  FAIL  ${label}${detail ? ` — ${detail}` : ''}`);
    fail++;
  }
}

async function api(path, { method = 'GET', body, token } = {}) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      'X-Device-Id': 'test-choose-carers',
      ...(KEY ? { 'X-Sathiyaa-Key': KEY } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let data;
  try {
    data = text ? JSON.parse(text) : {};
  } catch {
    data = { raw: text };
  }
  return { status: res.status, data };
}

console.log('\nChoosing which carers to ask\n');

// --- sign in ------------------------------------------------------------------
const otpReq = await api('/auth/customer/login', { method: 'POST', body: { mobile: MOBILE } });
if (otpReq.status !== 200 || !otpReq.data.devOtp) {
  console.log(`  FAIL  could not request an OTP for ${MOBILE} (status ${otpReq.status})`);
  console.log('        Is the API running, and is NODE_ENV something other than production?');
  process.exit(1);
}
const verified = await api('/auth/customer/verify-otp', {
  method: 'POST',
  body: { mobile: MOBILE, otp: otpReq.data.devOtp },
});
const token = verified.data.token;
check('customer signed in', !!token, `status ${verified.status}`);
if (!token) process.exit(1);

// --- a weekday, because seeded carers work Monday to Saturday -----------------
const d = new Date(Date.now() + (25 + Math.floor(Math.random() * 30)) * 864e5);
while (d.getDay() === 0 || d.getDay() === 6) d.setDate(d.getDate() + 1);
const pad = (n) => String(n).padStart(2, '0');
const day = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

const WINDOW = { timeFrom: '11:00:00', timeTo: '13:00:00' };
const WHERE = { latitude: 23.0225, longitude: 72.5714 };

// --- who is actually free that day --------------------------------------------
const search = await api(
  `/providers/search?service_type=companion&date_from=${day}&time_from=${WINDOW.timeFrom}` +
  `&time_to=${WINDOW.timeTo}&lat=${WHERE.latitude}&lng=${WHERE.longitude}&radius_km=50`,
  { token }
);
const found = search.data.providers ?? search.data ?? [];
check('search returns carers to choose between', Array.isArray(found) && found.length >= 3,
  `got ${Array.isArray(found) ? found.length : typeof found}`);
if (!Array.isArray(found) || found.length < 3) process.exit(1);

const ids = found.slice(0, 3).map((p) => p.provider_id ?? p.providerId);
const created = [];

async function book(body) {
  const r = await api('/bookings', {
    method: 'POST',
    token,
    body: { serviceType: 'companion', startDate: day, endDate: day, ...WINDOW, ...WHERE, ...body },
  });
  if (r.data?.bookingId) created.push(r.data.bookingId);
  return r;
}

// --- 1. ask exactly the two chosen --------------------------------------------
const two = await book({ providerIds: ids.slice(0, 2) });
check('a booking naming two carers is accepted', two.status === 201, `status ${two.status}`);
check('  ...and exactly those two are asked', two.data.providersNotified === 2,
  `notified ${two.data.providersNotified}`);
check('  ...and it says the customer chose them', two.data.chosenByCustomer === true,
  `chosenByCustomer ${two.data.chosenByCustomer}`);
check('  ...and names them back, so the app can say who is being asked',
  Array.isArray(two.data.providers) && two.data.providers.length === 2
    && two.data.providers.every((p) => p.name),
  JSON.stringify(two.data.providers ?? []).slice(0, 120));

const askedIds = (two.data.providers ?? []).map((p) => Number(p.providerId)).sort();
check('  ...and they are the two that were named', askedIds.join() === ids.slice(0, 2).map(Number).sort().join(),
  `asked ${askedIds.join()} for chosen ${ids.slice(0, 2).join()}`);

// --- 2. a carer who cannot take it is dropped, not faked ----------------------
const withGhost = await book({ providerIds: [...ids.slice(0, 2), 99999999] });
check('an id that is nobody is dropped rather than refused outright',
  withGhost.status === 201 && withGhost.data.providersNotified === 2,
  `status ${withGhost.status}, notified ${withGhost.data.providersNotified}`);
check('  ...and the count of who could not be asked is reported',
  withGhost.data.unavailableCount === 1,
  `unavailableCount ${withGhost.data.unavailableCount}`);

// --- 3. nobody available at all is a clear refusal, not an empty booking ------
const none = await book({ providerIds: [99999998, 99999999] });
check('choosing only carers who cannot take it is refused', none.status === 422,
  `status ${none.status}`);
check('  ...with a message a person can act on',
  /none of the carers|pick somebody else/i.test(none.data?.error?.message ?? ''),
  none.data?.error?.message ?? JSON.stringify(none.data).slice(0, 100));

// --- 4. omitting the list keeps the old behaviour ------------------------------
const everyone = await book({});
check('a booking with no shortlist still goes to everyone in range',
  everyone.status === 201 && everyone.data.providersNotified > 2,
  `status ${everyone.status}, notified ${everyone.data.providersNotified}`);
check('  ...and does not claim the customer chose them',
  everyone.data.chosenByCustomer === false,
  `chosenByCustomer ${everyone.data.chosenByCustomer}`);

// --- 5. only somebody who was asked can accept ---------------------------------
// The third carer was deliberately left off the first booking's shortlist.
//
// Search deliberately does not hand out mobile numbers — a directory that lets
// anyone read every carer's phone number is a different product — so the number
// to sign in with comes from the admin API, which is allowed to know it.
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? 'Admin@123';
const adminLogin = await api('/auth/admin/login', {
  method: 'POST',
  body: { email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD },
});
let mobile;
if (adminLogin.data.token) {
  const list = await api(`/admin/providers?status=all&search=`, { token: adminLogin.data.token });
  const row = (list.data.providers ?? []).find(
    (p) => Number(p.provider_id) === Number(ids[2])
  );
  mobile = row?.mobile_number;
}
check('the un-asked carer can be looked up to test with', !!mobile,
  `no mobile for provider ${ids[2]}`);

if (mobile && two.data.bookingId) {
  const pl = await api('/auth/provider/login', {
    method: 'POST',
    body: { mobile, pin: '123456', deviceId: 'test-choose-carers-provider' },
  });
  if (pl.data.token) {
    const accept = await api(`/providers/me/bookings/${two.data.bookingId}/accept`, {
      method: 'POST',
      token: pl.data.token,
    });
    check('a carer who was not asked cannot accept the booking',
      accept.status >= 400, `status ${accept.status}`);
  } else {
    console.log('  SKIP  could not sign in as the un-asked carer to test accept');
  }
} else {
  console.log('  SKIP  search did not return a mobile number for the un-asked carer');
}

// --- clean up -------------------------------------------------------------------
let cancelled = 0;
for (const id of created) {
  const r = await api(`/bookings/${id}/cancel`, { method: 'POST', token, body: { reason: 'test' } });
  if (r.status >= 200 && r.status < 300) cancelled++;
}
check(`the ${created.length} test booking(s) are cancelled`, cancelled === created.length,
  `cancelled ${cancelled} of ${created.length}`);

console.log(`\n  ${pass}/${pass + fail} passed\n`);
process.exit(fail === 0 ? 0 : 1);
