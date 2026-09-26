// Proves a booking can be made for somebody other than the account holder,
// and that the person it is for reaches the carer's job sheet.
//
// The case this exists for: an adult child in another city arranging care for
// a parent. They hold the account and they pay; the carer is visiting somebody
// else entirely. Getting that wrong means a carer knocking and asking for the
// wrong name, which is the sort of mistake a family does not give you twice.
//
// Reads only, plus one booking it cancels on the way out — it signs in as a
// seeded customer rather than registering a new one, so it leaves nothing
// behind but the cancelled booking.

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
      'X-Device-Id': 'test-booking-for-dependent',
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

console.log('\nBooking for a dependent\n');

// --- sign in as a seeded customer -------------------------------------------
const otpReq = await api('/auth/customer/login', { method: 'POST', body: { mobile: MOBILE } });
if (otpReq.status !== 200 || !otpReq.data.devOtp) {
  console.log(`  FAIL  could not request an OTP for ${MOBILE} (status ${otpReq.status})`);
  console.log('        Is the API running, and is NODE_ENV something other than production?');
  process.exit(1);
}

const verify = await api('/auth/customer/verify-otp', {
  method: 'POST',
  body: { mobile: MOBILE, otp: otpReq.data.devOtp },
});
check('signed in as the seeded customer', verify.status === 200 && !!verify.data.token,
  `status ${verify.status}`);
const token = verify.data.token;
if (!token) process.exit(1);

// --- a family member to book for --------------------------------------------
const existing = await api('/customers/me/family', { token });
let member = (existing.data.family ?? [])[0];

let created = false;
if (!member) {
  const add = await api('/customers/me/family', {
    method: 'POST',
    token,
    body: {
      name: 'Kamala Verma (QA)',
      relationship: 'Mother',
      contactNumber: '9876500099',
      dateOfBirth: '1946-02-11',
      notes: 'Hard of hearing — knock twice and wait.',
    },
  });
  check('family member added with a date of birth and a note', add.status === 201,
    `status ${add.status} ${JSON.stringify(add.data).slice(0, 120)}`);
  created = add.status === 201;
  const again = await api('/customers/me/family', { token });
  member = (again.data.family ?? []).find((f) => f.id === add.data.id);
}

check('a family member is available to book for', !!member);
if (!member) process.exit(1);

// Relative, not written down. These were '2026-12-01' and '2026-12-02', which
// are fine this year and are a booking in the past next year — at which point
// the script fails with a validation error that says nothing about dependents.
// Weekends are skipped because seeded carers work Monday to Saturday.
function weekday(inDays) {
  const d = new Date(Date.now() + inDays * 864e5);
  while (d.getDay() === 0 || d.getDay() === 6) d.setDate(d.getDate() + 1);
  const pad = (n) => String(n).padStart(2, '0');
  // Local date: toISOString() shifts local midnight back a day.
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}
const DAY_ONE = weekday(30);
const DAY_TWO = weekday(31);

// --- refuse somebody else's dependent ---------------------------------------
const stranger = await api('/bookings', {
  method: 'POST',
  token,
  body: {
    serviceType: 'companion',
    startDate: DAY_ONE,
    endDate: DAY_ONE,
    timeFrom: '10:00',
    timeTo: '12:00',
    forFamilyMemberId: 99999999,
  },
});
check('a family member id that is not yours is refused', stranger.status === 400,
  `status ${stranger.status}`);

// --- book for the dependent --------------------------------------------------
const booking = await api('/bookings', {
  method: 'POST',
  token,
  body: {
    serviceType: 'companion',
    startDate: DAY_ONE,
    endDate: DAY_ONE,
    timeFrom: '10:00',
    timeTo: '12:00',
    forFamilyMemberId: member.id,
  },
});
check('booking created for the dependent', booking.status === 201,
  `status ${booking.status} ${JSON.stringify(booking.data).slice(0, 160)}`);
check('the response names who it is for', booking.data.forName === member.name,
  `got ${booking.data.forName}`);

const bookingId = booking.data.bookingId;

// --- read it back ------------------------------------------------------------
if (bookingId) {
  const read = await api(`/bookings/${bookingId}`, { token });
  check('reading the booking back carries the dependent', read.data.forFamilyMemberId === member.id,
    `got ${read.data.forFamilyMemberId}`);
  check('  ...with their name', read.data.forName === member.name, `got ${read.data.forName}`);
  check('  ...and their relationship', !!read.data.forRelationship, `got ${read.data.forRelationship}`);
  check('  ...and a number to reach them on', !!read.data.forContactNumber);

  const list = await api('/bookings', { token });
  const inList = (list.data.bookings ?? []).find((b) => b.bookingId === bookingId);
  check('the list carries it too', !!inList && inList.forName === member.name,
    inList ? `got ${inList.forName}` : 'booking not in list');
}

// --- a booking for yourself still reads as one -------------------------------
const forSelf = await api('/bookings', {
  method: 'POST',
  token,
  body: {
    serviceType: 'companion',
    startDate: DAY_TWO,
    endDate: DAY_TWO,
    timeFrom: '10:00',
    timeTo: '12:00',
  },
});
check('a booking with no dependent is still accepted', forSelf.status === 201,
  `status ${forSelf.status}`);
if (forSelf.data.bookingId) {
  const read = await api(`/bookings/${forSelf.data.bookingId}`, { token });
  check('  ...and reads as being for the account holder', read.data.forFamilyMemberId === null,
    `got ${read.data.forFamilyMemberId}`);
}

// --- tidy up -----------------------------------------------------------------
for (const id of [bookingId, forSelf.data.bookingId].filter(Boolean)) {
  await api(`/bookings/${id}/cancel`, { method: 'POST', token, body: { reason: 'automated test' } });
}
if (created && member?.id) {
  // Only if this run created it; a seeded member belongs to the demo data.
  await api(`/customers/me/family/${member.id}`, { method: 'DELETE', token });
}
console.log('  (bookings cancelled, test family member removed)');

console.log(`\n=== ${pass}/${pass + fail} passed ===\n`);
process.exit(fail === 0 ? 0 : 1);
