// Messages between a customer and the carer on their booking.
//
// The behaviour worth testing is not "a message can be sent" — it is who is
// allowed to read one. A thread exists only where a booking does, and the two
// rules that matter are that a stranger cannot open it and that reading it
// clears the *other* side's messages, not your own.
//
// Runs the happy path far enough to get a confirmed booking, then talks on it.

const BASE = process.env.SATHIYAA_API ?? process.env.API_BASE ?? 'http://localhost:4000/api/v1';
const KEY = process.env.API_ACCESS_KEY ?? '';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? 'Admin@123';

let pass = 0;
let fail = 0;
const check = (label, ok, detail = '') => {
  if (ok) { console.log(`  PASS  ${label}`); pass++; }
  else { console.log(`  FAIL  ${label}${detail ? ` — ${detail}` : ''}`); fail++; }
};

async function api(path, { method = 'GET', body, token, device = 'test-messages' } = {}) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      'X-Device-Id': device,
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

console.log('\nBooking messages\n');

// --- a customer with a booking -------------------------------------------------
const mobile = '99888' + String(Math.floor(Math.random() * 90000) + 10000);
await api('/auth/customer/register', { method: 'POST', body: { name: 'Message Test (QA)', mobile } });
const otp = await api('/auth/customer/login', { method: 'POST', body: { mobile } });
const cv = await api('/auth/customer/verify-otp', {
  method: 'POST', body: { mobile, otp: otp.data.devOtp },
});
const CT = cv.data.token;
check('customer signed in', !!CT);
if (!CT) process.exit(1);

// A date and a slot of its own. Provider matching skips anyone whose calendar
// is already taken for the range asked for, so sharing today's 09:00-12:00
// with happy-path.mjs meant whichever ran second found nobody free — an
// ordering accident dressed up as a failure.
// A different day each run, but never a weekend.
//
// Provider matching skips anyone whose calendar is already taken for the range
// asked for. A fixed day meant this collided first with happy-path.mjs and
// then, once that was fixed, with *itself*: the booking the previous run left
// confirmed still held the slot. The run cancels its own booking at the end,
// and the varying day means a crashed run that never got that far does not
// block every run after it.
//
// Seeded carers work Monday to Saturday, so a Sunday matches nobody at all and
// the whole script fails on `providersNotified: 0` for a reason that has
// nothing to do with messages. That is what one run in seven used to do. And
// the date has to be the local one: toISOString() shifts local midnight back
// to the previous UTC day, which is its own way of landing on a Sunday.
const d = new Date(Date.now() + (20 + Math.floor(Math.random() * 40)) * 864e5);
while (d.getDay() === 0 || d.getDay() === 6) d.setDate(d.getDate() + 1);
const localYmd = (x) =>
  `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`;
const day = localYmd(d);
const created = await api('/bookings', {
  method: 'POST',
  token: CT,
  body: {
    serviceType: 'companion', startDate: day, endDate: day,
    timeFrom: '14:00:00', timeTo: '16:00:00', latitude: 23.0225, longitude: 72.5714,
  },
});
const bookingId = created.data.bookingId;
check('booking created', !!bookingId, `status ${created.status}`);
check('  ...and reached at least one carer', (created.data.providersNotified ?? 0) > 0,
  `notified ${created.data.providersNotified}`);

// A thread before anyone has accepted is not a thread.
const tooEarly = await api(`/bookings/${bookingId}/messages`, { token: CT });
check('messages are closed while the booking is still searching', tooEarly.status === 409,
  `status ${tooEarly.status}`);

// --- get a carer onto it -------------------------------------------------------
const admin = await api('/auth/admin/login', {
  method: 'POST', body: { email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD },
});
const AT = admin.data.token;
const provs = await api('/admin/providers?search=9600000000', { token: AT });
const target = (provs.data.providers ?? []).find((p) => p.mobile_number === '9600000000');
if (target) {
  await api(`/admin/providers/${target.provider_id}/reset-device`, { method: 'POST', token: AT });
}

const pl = await api('/auth/provider/login', {
  method: 'POST',
  device: 'test-messages',
  body: { mobile: '9600000000', pin: '123456', deviceId: 'test-messages' },
});
const PT = pl.data.token;
check('provider signed in', !!PT, `status ${pl.status}`);

await api('/providers/me', { method: 'PUT', token: PT, body: { locationOn: true } });
await api('/providers/me/location', { method: 'PATCH', token: PT, body: { lat: 23.0225, lng: 72.5714 } });
const mine = await api('/providers/me/requests', { token: PT });
const wasAsked = (mine.data.requests ?? []).some((r) => (r.bookingId ?? r.booking_id) === bookingId);
check('the test carer was among those asked', wasAsked,
  'not in their request list — matching skipped them (busy, or out of radius)');

const accepted = await api(`/providers/me/requests/${bookingId}/accept`, { method: 'POST', token: PT });
check('provider accepted the booking', accepted.status === 200, `status ${accepted.status}`);
await api(`/bookings/${bookingId}/pay`, { method: 'POST', token: CT, body: { paymentRef: 'test' } });

// --- talking --------------------------------------------------------------------
const said = await api(`/bookings/${bookingId}/messages`, {
  method: 'POST', token: CT, body: { body: 'The gate code is 4417.' },
});
check('customer can send a message once confirmed', said.status === 201, `status ${said.status}`);

const blank = await api(`/bookings/${bookingId}/messages`, {
  method: 'POST', token: CT, body: { body: '   ' },
});
check('an empty message is refused', blank.status === 400, `status ${blank.status}`);

const replied = await api(`/providers/me/bookings/${bookingId}/messages`, {
  method: 'POST', token: PT, body: { body: 'Thank you, on my way.' },
});
check('carer can reply', replied.status === 201, `status ${replied.status}`);

const thread = await api(`/providers/me/bookings/${bookingId}/messages`, { token: PT });
check('the thread holds both messages', (thread.data.messages ?? []).length === 2,
  `got ${(thread.data.messages ?? []).length}`);
check('  ...and names who it is with', !!thread.data.withName, `got ${thread.data.withName}`);

// --- badges ----------------------------------------------------------------------
// The carer just read the thread, so their own badge is clear and the
// customer's is not: one unread, the carer's reply.
const custList = await api('/bookings', { token: CT });
const row = (custList.data.bookings ?? []).find((b) => b.bookingId === bookingId);
check('the customer has an unread badge for the reply', row?.unreadMessages === 1,
  `got ${row?.unreadMessages}`);

await api(`/bookings/${bookingId}/messages`, { token: CT });
const after = await api('/bookings', { token: CT });
const rowAfter = (after.data.bookings ?? []).find((b) => b.bookingId === bookingId);
check('reading the thread clears it', rowAfter?.unreadMessages === 0, `got ${rowAfter?.unreadMessages}`);

// --- a stranger ------------------------------------------------------------------
const otherMobile = '99887' + String(Math.floor(Math.random() * 90000) + 10000);
await api('/auth/customer/register', { method: 'POST', body: { name: 'Nosy Parker (QA)', mobile: otherMobile } });
const o = await api('/auth/customer/login', { method: 'POST', body: { mobile: otherMobile } });
const ov = await api('/auth/customer/verify-otp', {
  method: 'POST', body: { mobile: otherMobile, otp: o.data.devOtp },
});
const OT = ov.data.token;

const snoop = await api(`/bookings/${bookingId}/messages`, { token: OT });
// 404, not 403: a different answer for "not yours" and "no such booking" is a
// way to find out which bookings exist.
check('somebody not on the booking cannot read the thread', snoop.status === 404,
  `status ${snoop.status}`);

const snoopWrite = await api(`/bookings/${bookingId}/messages`, {
  method: 'POST', token: OT, body: { body: 'hello?' },
});
check('  ...nor write to it', snoopWrite.status === 404, `status ${snoopWrite.status}`);

// --- tidy up ---------------------------------------------------------------------
// The booking is cancelled so the carer's calendar is free for the next run.
// Leaving it confirmed is what made this test fail the second time it ran.
if (bookingId) {
  const cancelled = await api(`/bookings/${bookingId}/cancel`, {
    method: 'POST', token: CT, body: { reason: 'automated test' },
  });
  check('the test booking is cancelled, freeing the slot for the next run',
    cancelled.status === 200, `status ${cancelled.status}`);
}

console.log(`\n=== ${pass}/${pass + fail} passed ===`);
console.log('  (leaves two QA customers and one booking — run cleanup-test-rows.mjs)\n');
process.exit(fail === 0 ? 0 : 1);
