/**
 * Every route in the API, exercised once.
 *
 * The other suites follow journeys -- a booking from request to rating. This
 * one goes the other way: it walks the route table and makes sure nothing is
 * quietly broken just because no journey happens to pass through it.
 *
 * Run it against a freshly seeded database.
 */
const BASE = process.env.SATHIYAA_API ?? process.env.API_BASE ?? 'http://localhost:4000/api/v1';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? 'Admin@123';

let passed = 0;
const failures = [];
const untested = [];

function section(title) {
  console.log(`\n${'-'.repeat(70)}\n  ${title}\n${'-'.repeat(70)}`);
}
function ok(label, condition, detail = '') {
  if (condition) {
    passed++;
    console.log(`  PASS  ${label}`);
  } else {
    failures.push(label);
    console.log(`  FAIL  ${label}${detail ? `\n          ${detail}` : ''}`);
  }
}
function skip(label, why) {
  untested.push(`${label} (${why})`);
  console.log(`  ----  ${label}  [${why}]`);
}

function device(deviceId) {
  let token = null;
  return {
    deviceId,
    get token() { return token; },
    set token(t) { token = t; },
    async call(method, path, body) {
      const res = await fetch(BASE + path, {
        method,
        headers: {
          'Content-Type': 'application/json',
          'X-Device-Id': deviceId,
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
      });
      const text = await res.text();
      let json;
      try { json = JSON.parse(text); } catch { json = text; }
      return { status: res.status, ok: res.ok, json };
    },
  };
}

const brief = (r) => `${r.status} ${JSON.stringify(r.json).slice(0, 150)}`;
const rnd = (p) => `${p}${Math.floor(Math.random() * 90000000) + 10000000}`;
const pad = (n) => String(n).padStart(2, '0');
const ymd = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
function weekday(inDays = 2) {
  const d = new Date(Date.now() + inDays * 864e5);
  while (d.getDay() === 0 || d.getDay() === 6) d.setDate(d.getDate() + 1);
  return ymd(d);
}
const day = weekday();

const cust = device('audit-customer');
const prov = device('audit-provider');
const org = device('audit-org');
const emp = device('audit-employee');
const admin = device('audit-admin');
const partner = device('audit-partner');

// ===================================================================== AUTH
section('AUTH  (10 routes)');

const custMobile = rnd('97');
let r = await cust.call('POST', '/auth/customer/register', { name: 'Audit Customer', mobile: custMobile });
ok('POST /auth/customer/register', r.ok && !!r.json.devOtp, brief(r));

r = await cust.call('POST', '/auth/customer/verify-otp', { mobile: custMobile, otp: r.json.devOtp });
ok('POST /auth/customer/verify-otp', r.ok, brief(r));
cust.token = r.json.token;
const custId = r.json.customer?.customerId;

r = await cust.call('POST', '/auth/customer/login', { mobile: custMobile });
ok('POST /auth/customer/login  (asks for a fresh OTP)', r.ok, brief(r));
const loginOtp = r.json.devOtp;
r = await cust.call('POST', '/auth/customer/verify-otp', { mobile: custMobile, otp: loginOtp });
ok('  and that OTP verifies', r.ok, brief(r));
cust.token = r.json.token ?? cust.token;

r = await cust.call('POST', '/auth/customer/reset-otp', { mobile: custMobile });
ok('POST /auth/customer/reset-otp', r.ok, brief(r));

r = await cust.call('POST', '/auth/customer/verify-otp', { mobile: custMobile, otp: '000000' });
ok('  a wrong OTP is refused', !r.ok, brief(r));

const provMobile = rnd('96');
r = await prov.call('POST', '/auth/provider/register', {
  providerKind: 'freelancer', name: 'Audit Provider', gender: 'female', dob: '1990-03-03',
  mobile: provMobile, pin: '246810', hourlyRate: 400, deviceId: prov.deviceId,
  languages: ['English'],
  addresses: [{ addressType: 'home', line1: '9 Audit Lane', city: 'Ahmedabad', latitude: 23.0109, longitude: 72.5768 }],
  workHours: ['mon', 'tue', 'wed', 'thu', 'fri', 'sat'].map((d) => ({ dayOfWeek: d, startTime: '08:00:00', endTime: '20:00:00' })),
  expertise: [{ serviceType: 'nurse', yearsExperience: 5 }],
});
ok('POST /auth/provider/register', r.status === 201, brief(r));
prov.token = r.json.token;
const provId = r.json.provider?.providerId;

r = await prov.call('POST', '/auth/provider/login', { mobile: provMobile, pin: '246810' });
ok('POST /auth/provider/login', r.ok, brief(r));
prov.token = r.json.token ?? prov.token;

r = await prov.call('POST', '/auth/provider/login', { mobile: provMobile, pin: '999999' });
ok('  a wrong PIN is refused', !r.ok, brief(r));

r = await prov.call('POST', '/auth/provider/reset-pin-otp', { mobile: provMobile });
ok('POST /auth/provider/reset-pin-otp', r.ok, brief(r));

r = await admin.call('POST', '/auth/admin/login', { email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD });
ok('POST /auth/admin/login', r.ok, brief(r));
admin.token = r.json.token;

r = await admin.call('POST', '/auth/admin/login', { email: 'admin@sathiyaa.com', password: 'wrong' });
ok('  a wrong admin password is refused', !r.ok, brief(r));

r = await partner.call('POST', '/auth/business-agent/login', { identifier: 'BP-000001', password: 'Partner@123' });
ok('POST /auth/business-agent/login', r.ok, brief(r));
partner.token = r.json.token;

r = await partner.call('POST', '/auth/business-agent/reset-otp', { identifier: 'BP-000001' });
ok('POST /auth/business-agent/reset-otp', r.ok, brief(r));

// ================================================================ CUSTOMER
section('CUSTOMER PROFILE  (30 routes)');

r = await cust.call('POST', '/customers/me/accept-terms', { accepted: true });
ok('POST /customers/me/accept-terms', r.ok, brief(r));
ok('  and refuses to record agreement that was not given',
   !(await cust.call('POST', '/customers/me/accept-terms', { accepted: false })).ok);

r = await cust.call('PUT', '/customers/me', {
  gender: 'female', dob: '1972-08-14', bloodGroup: 'O+', email: 'audit@example.com',
  heightCm: 162, weightKg: 61, preferredCommMode: 'email,call,sms',
  preferredCommTimeframe: '09:00-18:00', preferredLanguages: ['English', 'Hindi'],
});
ok('PUT /customers/me', r.ok, brief(r));
ok('  all three contact modes stored', r.json.preferredCommMode === 'email,call,sms', `got ${r.json.preferredCommMode}`);
ok('  BMI computed', r.json.bmi != null, brief(r));

r = await cust.call('GET', '/customers/me');
ok('GET /customers/me', r.ok, brief(r));

r = await cust.call('PUT', '/customers/me/addresses', {
  primary: { line1: '4 Audit Road', city: 'Ahmedabad', pincode: '380001', latitude: 23.0293, longitude: 72.6176 },
  secondary: { line1: '7 Second Street', city: 'Ahmedabad', latitude: 22.9809, longitude: 72.5968 },
});
ok('PUT /customers/me/addresses  (both)', r.ok, brief(r));
ok('  both addresses returned', (r.json.addresses || []).length === 2, brief(r));

// --- the five capped health sections -----------------------------------
const sections = [
  ['vitals', { vitalType: 'bp', valuePrimary: 128, valueSecondary: 82, recordedAt: `${ymd(new Date())} 09:00:00` }, { vitalType: 'bp', valuePrimary: 120, valueSecondary: 80, recordedAt: `${ymd(new Date())} 10:00:00` }],
  ['medications', { medicineName: 'Metformin', frequency: 'Twice daily' }, { medicineName: 'Metformin', frequency: 'Once daily' }],
  ['surgeries', { surgeryName: 'Knee replacement', surgeryDate: '2019-05-02' }, { surgeryName: 'Knee replacement', surgeryDate: '2019-06-02' }],
  ['allergies', { allergyName: 'Penicillin', onsetDate: '2005-01-01' }, { allergyName: 'Penicillin', onsetDate: '2006-01-01' }],
  ['family', { name: 'Ravi Audit', relationship: 'Son', contactNumber: rnd('98') }, { name: 'Ravi Audit', relationship: 'Son', contactNumber: rnd('98') }],
];

for (const [name, create, update] of sections) {
  r = await cust.call('GET', `/customers/me/${name}`);
  ok(`GET /customers/me/${name}`, r.ok, brief(r));

  r = await cust.call('POST', `/customers/me/${name}`, create);
  ok(`POST /customers/me/${name}`, r.ok, brief(r));
  const id = r.json?.id ?? r.json?.[name]?.[0]?.id;

  if (id) {
    r = await cust.call('PUT', `/customers/me/${name}/${id}`, update);
    ok(`PUT /customers/me/${name}/:id`, r.ok, brief(r));
    r = await cust.call('DELETE', `/customers/me/${name}/${id}`);
    // A customer must always have at least one family contact, so deleting the
    // only one is meant to be refused -- with a message saying so.
    const mustKeepOne = name === 'family' && r.status === 422;
    ok(`DELETE /customers/me/${name}/:id`, r.ok || mustKeepOne, brief(r));
    if (mustKeepOne) console.log('          (refused on purpose: at least one family member is required)');
  } else {
    skip(`PUT+DELETE /customers/me/${name}/:id`, 'create returned no id');
  }
}

r = await cust.call('GET', '/customers/me/insurance');
ok('GET /customers/me/insurance', r.ok, brief(r));
r = await cust.call('POST', '/customers/me/insurance', {
  insuredWith: 'Star Health', policyNumber: 'SH-AUDIT-1', startDate: '2026-01-01', endDate: '2027-01-01',
});
ok('POST /customers/me/insurance', r.ok, brief(r));

r = await cust.call('POST', '/customers/me/registration-payment', {});
ok('POST /customers/me/registration-payment', r.ok, brief(r));

// --- linked providers ---------------------------------------------------
r = await cust.call('GET', '/customers/me/linked-providers');
ok('GET /customers/me/linked-providers', r.ok, brief(r));
r = await cust.call('POST', '/customers/me/linked-providers', { providerId: 1 });
ok('POST /customers/me/linked-providers', r.ok, brief(r));
r = await cust.call('DELETE', '/customers/me/linked-providers/1');
ok('DELETE /customers/me/linked-providers/:id', r.ok, brief(r));

// ================================================================ PROVIDER
section('PROVIDER  (35 routes)');

r = await prov.call('GET', '/providers/me');
ok('GET /providers/me', r.ok, brief(r));

r = await prov.call('PUT', '/providers/me', { distanceFromHomePrefKm: 12 });
ok('PUT /providers/me', r.ok, brief(r));

r = await prov.call('POST', '/providers/me/registration-payment', {});
ok('POST /providers/me/registration-payment', r.ok, brief(r));

r = await prov.call('PUT', '/providers/me/work-hours', {
  workHours: ['mon', 'tue', 'wed', 'thu', 'fri', 'sat'].map((d) => ({ dayOfWeek: d, startTime: '07:00:00', endTime: '21:00:00' })),
});
ok('PUT /providers/me/work-hours', r.ok, brief(r));

r = await prov.call('GET', '/providers/me/calendar-blocks');
ok('GET /providers/me/calendar-blocks', r.ok, brief(r));
r = await prov.call('POST', '/providers/me/calendar-blocks', {
  blockStart: `${weekday(30)} 00:00:00`, blockEnd: `${weekday(31)} 23:59:59`, reason: 'Audit leave',
});
ok('POST /providers/me/calendar-blocks', r.ok, brief(r));
const blockId = r.json?.id ?? r.json?.block?.id;
if (blockId) {
  ok('DELETE /providers/me/calendar-blocks/:id', (await prov.call('DELETE', `/providers/me/calendar-blocks/${blockId}`)).ok);
} else {
  skip('DELETE /providers/me/calendar-blocks/:id', 'create returned no id');
}

ok('PATCH /providers/me/location', (await prov.call('PATCH', '/providers/me/location', { lat: 23.0109, lng: 72.5768 })).ok);

r = await prov.call('GET', '/providers/me/dashboard');
ok('GET /providers/me/dashboard', r.ok, brief(r));
r = await prov.call('GET', '/providers/me/appointments');
ok('GET /providers/me/appointments', r.ok, brief(r));
r = await prov.call('GET', '/providers/me/time-bank');
ok('GET /providers/me/time-bank', r.ok, brief(r));
r = await prov.call('GET', '/providers/me/requests');
ok('GET /providers/me/requests', r.ok, brief(r));
r = await prov.call('GET', `/providers/search?service_type=nurse&date_from=${day}&time_from=09:00:00&time_to=13:00:00&lat=23.0293&lng=72.6176&radius_km=25`);
ok('GET /providers/search', r.ok && r.json.count >= 0, brief(r));

// ===================================================== APPROVE, THEN BOOK
section('ADMIN APPROVAL + A FULL BOOKING');

r = await prov.call('GET', `/providers/${provId}`);
ok('GET /providers/:id  hides an unapproved provider', r.status === 404, brief(r));

ok('POST /admin/providers/:id/approve', (await admin.call('POST', `/admin/providers/${provId}/approve`, {})).ok);

r = await prov.call('GET', `/providers/${provId}`);
ok('GET /providers/:id  shows an approved one', r.ok, brief(r));

r = await cust.call('POST', '/bookings', {
  serviceType: 'nurse', startDate: day, endDate: day, timeFrom: '09:00:00', timeTo: '13:00:00',
  latitude: 23.0293, longitude: 72.6176,
});
ok('POST /bookings', r.status === 201, brief(r));
const bid = r.json?.bookingId;

r = await cust.call('GET', '/bookings');
ok('GET /bookings', r.ok, brief(r));
r = await cust.call('GET', '/bookings?scope=current');
ok('GET /bookings?scope=current', r.ok, brief(r));
r = await cust.call('GET', `/bookings/${bid}`);
ok('GET /bookings/:id', r.ok, brief(r));

await prov.call('PUT', '/providers/me', { locationOn: true });
await prov.call('PATCH', '/providers/me/location', { lat: 23.0109, lng: 72.5768 });
ok('POST /providers/me/requests/:id/accept', (await prov.call('POST', `/providers/me/requests/${bid}/accept`, {})).ok);

r = await cust.call('GET', `/bookings/${bid}/track`);
ok('GET /bookings/:id/track', r.ok, brief(r));

ok('POST /bookings/:id/pay', (await cust.call('POST', `/bookings/${bid}/pay`, {})).ok);

r = await prov.call('GET', `/providers/me/bookings/${bid}/directions`);
ok('GET /providers/me/bookings/:id/directions', r.ok, brief(r));
ok('  a real road route came back', !!r.json?.polyline, brief(r));

await prov.call('PATCH', '/providers/me/location', { lat: 23.0293, lng: 72.6176 });
r = await prov.call('POST', `/providers/me/bookings/${bid}/start`, { selfieUrl: '/uploads/selfie/audit.jpg' });
ok('POST /providers/me/bookings/:id/start', r.ok, brief(r));

r = await cust.call('GET', `/bookings/${bid}/otp`);
ok('GET /bookings/:id/otp', r.ok && !!r.json.otp, brief(r));
ok('POST /providers/me/bookings/:id/verify-start-otp',
   (await prov.call('POST', `/providers/me/bookings/${bid}/verify-start-otp`, { otp: r.json.otp })).ok);

ok('POST /providers/me/bookings/:id/running-late',
   (await prov.call('POST', `/providers/me/bookings/${bid}/running-late`, { minutes: 15 })).ok);

r = await cust.call('POST', `/bookings/${bid}/masked-call`, {});
ok('POST /bookings/:id/masked-call', r.ok, brief(r));

r = await prov.call('POST', `/providers/me/bookings/${bid}/end`, {});
ok('POST /providers/me/bookings/:id/end', r.ok, brief(r));
const due = r.json?.payment?.amountDue ?? 0;

r = await prov.call('POST', `/providers/me/bookings/${bid}/payment-reminder`, {});
ok('POST /providers/me/bookings/:id/payment-reminder', r.ok, brief(r));

r = await prov.call('POST', `/providers/me/bookings/${bid}/payments`, { amount: due || 1, paymentType: 'full' });
ok('POST /providers/me/bookings/:id/payments', r.ok, brief(r));

ok('  a reminder on a settled booking is refused',
   !(await prov.call('POST', `/providers/me/bookings/${bid}/payment-reminder`, {})).ok);

ok('POST /providers/me/bookings/:id/rate-customer',
   (await prov.call('POST', `/providers/me/bookings/${bid}/rate-customer`, { rating: 5, comment: 'Audit' })).ok);
ok('POST /bookings/:id/rating',
   (await cust.call('POST', `/bookings/${bid}/rating`, { rating: 5, comment: 'Audit' })).ok);

// --- cancellation, on a second booking ---------------------------------
r = await cust.call('POST', '/bookings', {
  serviceType: 'nurse', startDate: weekday(6), endDate: weekday(6), timeFrom: '09:00:00', timeTo: '13:00:00',
  latitude: 23.0293, longitude: 72.6176,
});
const cancelBid = r.json?.bookingId;
r = await cust.call('POST', `/bookings/${cancelBid}/cancel`, { reason: 'Audit cancellation' });
ok('POST /bookings/:id/cancel', r.ok, brief(r));

// ============================================================ ORGANISATION
section('ORGANISATION  (employees, allocation, utilisation)');

const orgMobile = rnd('95');
r = await org.call('POST', '/auth/provider/register', {
  providerKind: 'organization', name: 'Audit Care Services', gender: 'other',
  mobile: orgMobile, pin: '135791', hourlyRate: 500, deviceId: org.deviceId, languages: ['English'],
  addresses: [{ addressType: 'home', line1: '1 Org Road', city: 'Ahmedabad', latitude: 23.0209, longitude: 72.5668 }],
  workHours: ['mon', 'tue', 'wed', 'thu', 'fri'].map((d) => ({ dayOfWeek: d, startTime: '09:00:00', endTime: '18:00:00' })),
  expertise: [{ serviceType: 'companion', yearsExperience: 4 }],
});
ok('an organization can register', r.status === 201, brief(r));
org.token = r.json.token;
const orgId = r.json.provider?.providerId;
await admin.call('POST', `/admin/providers/${orgId}/approve`, {});

r = await org.call('GET', '/providers/employees');
ok('GET /providers/employees', r.ok, brief(r));

// A carer with no papers can no longer be allocated work -- that is the
// point of the change, not an accident of it -- so the fixture carries the
// Aadhaar and the police verification any real carer would.
const auditPoliceFrom = new Date(Date.now() - 365 * 24 * 3600 * 1000).toISOString().slice(0, 10);
const auditPoliceTo = new Date(Date.now() + 730 * 24 * 3600 * 1000).toISOString().slice(0, 10);
// The expertise and the hours matter now: an organisation is surfaced to a
// family on the strength of the carers it can actually send, not on its own
// row, so a carer with no service type and no working days makes the whole
// agency unbookable.
r = await org.call('POST', '/providers/employees', {
  name: 'Audit Employee', gender: 'female', mobile: rnd('94'), address: '2 Org Road',
  expertise: [{ serviceType: 'companion' }],
  workHours: ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat']
    .map((d) => ({ dayOfWeek: d, startTime: '00:00', endTime: '23:59' })),
  aadharDocUrl: '/uploads/aadhar/audit-employee.png',
  policeVerificationUrl: '/uploads/police-verification/audit-employee.png',
  policeVerificationValidFrom: auditPoliceFrom,
  policeVerificationValidTo: auditPoliceTo,
});
ok('POST /providers/employees', r.ok, brief(r));
const empId = r.json?.employee?.providerId ?? r.json?.providerId ?? r.json?.id;

// A carer an organisation adds is pending until an administrator checks them
// -- having the documents is not the same as somebody having looked at them.
// Allocation refuses anybody unapproved, quite rightly, so the fixture goes
// through the approval it would go through in real life.
if (empId) {
  await admin.call('POST', `/admin/providers/${empId}/approve`, { notes: 'audit fixture' });
}

if (empId) {
  r = await org.call('PUT', `/providers/employees/${empId}`, { name: 'Audit Employee Renamed' });
  ok('PUT /providers/employees/:id', r.ok, brief(r));
  r = await org.call('PATCH', `/providers/employees/${empId}/status`, { status: 'blocked' });
  ok('PATCH /providers/employees/:id/status', r.ok, brief(r));
  await org.call('PATCH', `/providers/employees/${empId}/status`, { status: 'active' });
} else {
  skip('PUT + PATCH /providers/employees/:id', 'create returned no id');
}

r = await org.call('GET', '/providers/me/utilization');
ok('GET /providers/me/utilization', r.ok, brief(r));
r = await org.call('GET', '/providers/me/schedule-overview');
ok('GET /providers/me/schedule-overview', r.ok, brief(r));

// --- a booking that routes through the organisation --------------------
await org.call('PUT', '/providers/me', { locationOn: true, allocateViaOrg: true });
await org.call('PATCH', '/providers/me/location', { lat: 23.0209, lng: 72.5668 });

r = await cust.call('POST', '/bookings', {
  serviceType: 'companion', startDate: weekday(8), endDate: weekday(8),
  timeFrom: '10:00:00', timeTo: '12:00:00', latitude: 23.0293, longitude: 72.6176,
});
const orgBid = r.json?.bookingId;
r = await org.call('POST', `/providers/me/requests/${orgBid}/accept`, {});
ok('an organization can accept a request', r.ok, brief(r));

if (empId && r.ok) {
  // Allocation happens on a confirmed booking, so the customer confirms first.
  await cust.call('POST', `/bookings/${orgBid}/pay`, {});
  r = await org.call('POST', `/providers/me/bookings/${orgBid}/allocate`, { employeeId: empId });
  ok('POST /providers/me/bookings/:id/allocate', r.ok, brief(r));
  r = await org.call('POST', `/providers/me/bookings/${orgBid}/reallocate`, { employeeId: empId });
  ok('POST /providers/me/bookings/:id/reallocate', r.ok, brief(r));
  r = await org.call('POST', `/providers/me/bookings/${orgBid}/org-cancel`, { reason: 'Audit' });
  ok('POST /providers/me/bookings/:id/org-cancel', r.ok, brief(r));
} else {
  skip('allocate / reallocate / org-cancel', 'no employee or the accept failed');
}

// --- transfer between freelancers --------------------------------------
r = await cust.call('POST', '/bookings', {
  serviceType: 'nurse', startDate: weekday(10), endDate: weekday(10),
  timeFrom: '09:00:00', timeTo: '11:00:00', latitude: 23.0293, longitude: 72.6176,
});
const transferBid = r.json?.bookingId;
await prov.call('POST', `/providers/me/requests/${transferBid}/accept`, {});
await cust.call('POST', `/bookings/${transferBid}/pay`, {});
r = await prov.call('POST', `/providers/me/bookings/${transferBid}/transfer`, { toProviderId: 3 });
ok('POST /providers/me/bookings/:id/transfer', r.ok, brief(r));
const transferId = r.json?.transferId ?? r.json?.id;
if (transferId) {
  const other = device('audit-other-provider');
  const login = await other.call('POST', '/auth/provider/login', { mobile: '9600000274', pin: '123456' });
  other.token = login.json?.token;
  r = await other.call('POST', `/providers/me/transfers/${transferId}/respond`, { action: 'accept' });
  ok('POST /providers/me/transfers/:id/respond', r.ok, brief(r));
} else {
  skip('POST /providers/me/transfers/:id/respond', 'transfer returned no id');
}

// ======================================================== BUSINESS PARTNER
section('BUSINESS PARTNER  (5 routes)');

r = await partner.call('GET', '/business-agents/me');
ok('GET /business-agents/me', r.ok, brief(r));
r = await partner.call('PUT', '/business-agents/me', { contactNumber2: rnd('93') });
ok('PUT /business-agents/me', r.ok, brief(r));
r = await partner.call('GET', '/business-agents/me/referrals');
ok('GET /business-agents/me/referrals', r.ok, brief(r));
r = await partner.call('POST', '/business-agents/me/referrals', {
  customerName: 'Audit Referral', mobileNumber: rnd('92'), gender: 'female',
  serviceType: 'nurse', durationStart: weekday(14), durationEnd: weekday(16),
  timeFrom: '10:00:00', timeTo: '14:00:00', address: '12 Referral Road, Ahmedabad',
});
ok('POST /business-agents/me/referrals', r.ok, brief(r));
const referralId = r.json?.referralId ?? r.json?.id;
r = await partner.call('GET', '/business-agents/me/revenue');
ok('GET /business-agents/me/revenue', r.ok, brief(r));

// ==================================================================== ADMIN
section('ADMIN CONSOLE  (27 routes)');

for (const [label, path] of [
  ['GET /admin/providers', '/admin/providers?status=all'],
  ['GET /admin/customers', '/admin/customers'],
  ['GET /admin/business-agents', '/admin/business-agents'],
  ['GET /admin/config', '/admin/config'],
  ['GET /admin/revenue-sharing', '/admin/revenue-sharing'],
  ['GET /admin/time-bank-config', '/admin/time-bank-config'],
  ['GET /admin/broadcast', '/admin/broadcast'],
  ['GET /admin/tracking/providers', '/admin/tracking/providers'],
  ['GET /admin/reports/dashboard', '/admin/reports/dashboard'],
  ['GET /admin/reports/growth', '/admin/reports/growth?period=month'],
  ['GET /admin/audit-log', '/admin/audit-log'],
]) {
  r = await admin.call('GET', path);
  ok(label, r.ok, brief(r));
}

r = await admin.call('PUT', '/admin/config', { customer_booking_amount: 99 });
ok('PUT /admin/config', r.ok, brief(r));
r = await admin.call('PUT', '/admin/revenue-sharing', {
  serviceType: 'nurse', customerRatePerHour: 450, providerRatePerHour: 340,
  businessPartnerFlatPerHour: 45,
});
ok('PUT /admin/revenue-sharing', r.ok, brief(r));

// Updating only the customer and provider rates must not silently zero what
// business partners earn -- it used to, and their revenue page then showed
// hours worked against nothing earned.
await admin.call('PUT', '/admin/revenue-sharing', {
  serviceType: 'nurse', customerRatePerHour: 460, providerRatePerHour: 345,
});
r = await admin.call('GET', '/admin/revenue-sharing');
const nurseRow = (r.json.revenueSharing || []).find((x) => x.service_type === 'nurse');
ok('  a partial rate update keeps the partner rate',
   Number(nurseRow?.business_partner_flat_per_hour) === 45,
   `partner rate is now ${nurseRow?.business_partner_flat_per_hour}`);

// Put it back the way the seed had it.
await admin.call('PUT', '/admin/revenue-sharing', {
  serviceType: 'nurse', customerRatePerHour: 450, providerRatePerHour: 340,
  businessPartnerFlatPerHour: 45,
});
r = await admin.call('PUT', '/admin/time-bank-config', {
  serviceType: 'nurse', pointsPerHour: 10, applicationYear: new Date().getFullYear(),
});
ok('PUT /admin/time-bank-config', r.ok, brief(r));
r = await admin.call('POST', '/admin/broadcast', { title: 'Audit', message: 'Audit broadcast', audience: 'both' });
ok('POST /admin/broadcast', r.ok, brief(r));

r = await admin.call('POST', '/admin/business-agents', {
  entityName: 'Audit Diagnostics', partnerName: 'Audit Partner', contactNumber1: rnd('91'),
  email: 'auditbp@example.com', password: 'Audit@1234', address: '1 Audit Street',
});
ok('POST /admin/business-agents', r.ok, brief(r));
const newBpId = r.json?.businessPartnerId ?? r.json?.id;
if (newBpId) {
  r = await admin.call('PUT', `/admin/business-agents/${newBpId}`, {
    entityName: 'Audit Diagnostics Renamed', partnerName: 'Audit Partner',
    contactNumber1: rnd('91'), status: 'active',
  });
  ok('PUT /admin/business-agents/:id', r.ok, brief(r));
} else {
  skip('PUT /admin/business-agents/:id', 'create returned no id');
}

if (referralId) {
  r = await admin.call('POST', `/admin/business-agents/referrals/${referralId}/allocate`, { providerId: provId });
  ok('POST /admin/business-agents/referrals/:id/allocate', r.ok, brief(r));
} else {
  skip('POST /admin/business-agents/referrals/:id/allocate', 'no referral id');
}

// --- provider status actions, each verified by reading it back ----------
const readProvider = async (id) =>
  (await admin.call('GET', '/admin/providers?status=all')).json.providers.find((p) => p.provider_id === id);

ok('POST /admin/providers/:id/hold', (await admin.call('POST', `/admin/providers/${provId}/hold`, { note: 'Audit' })).ok);
ok('  the row really says hold', (await readProvider(provId))?.approval_status === 'hold');

ok('POST /admin/providers/:id/reject', (await admin.call('POST', `/admin/providers/${provId}/reject`, { note: 'Audit' })).ok);
ok('  the row really says rejected', (await readProvider(provId))?.approval_status === 'rejected');

r = await prov.call('GET', `/providers/${provId}`);
ok('GET /providers/:id  hides an unapproved provider', r.status === 404, brief(r));

ok('POST /admin/providers/:id/approve', (await admin.call('POST', `/admin/providers/${provId}/approve`, {})).ok);

r = await prov.call('GET', `/providers/${provId}`);
ok('GET /providers/:id  shows an approved one', r.ok, brief(r));
ok('  the row really says approved', (await readProvider(provId))?.approval_status === 'approved');

ok('POST /admin/providers/:id/block', (await admin.call('POST', `/admin/providers/${provId}/block`, { note: 'Audit' })).ok);
let row = await readProvider(provId);
ok('  the row really says blocked', row?.status === 'blocked');
ok('  and blocking did not change the approval', row?.approval_status === 'approved');

ok('POST /admin/providers/:id/unblock', (await admin.call('POST', `/admin/providers/${provId}/unblock`, {})).ok);
ok('  the row is active again', (await readProvider(provId))?.status === 'active');

ok('POST /admin/providers/:id/reset-device', (await admin.call('POST', `/admin/providers/${provId}/reset-device`, {})).ok);

ok('POST /admin/customers/:id/block', (await admin.call('POST', `/admin/customers/${custId}/block`, {})).ok);
ok('  a blocked customer cannot ask for an OTP',
   !(await device('fresh').call('POST', '/auth/customer/register', { name: 'Audit Customer', mobile: custMobile })).ok);
ok('POST /admin/customers/:id/unblock', (await admin.call('POST', `/admin/customers/${custId}/unblock`, {})).ok);

// --- deletes, refused where there is history ---------------------------
r = await admin.call('DELETE', `/admin/customers/${custId}`);
ok('DELETE /admin/customers/:id  refuses one with bookings', !r.ok, brief(r));
r = await admin.call('DELETE', `/admin/providers/${provId}`);
ok('DELETE /admin/providers/:id  refuses one with history', !r.ok, brief(r));
const throwaway = device('audit-throwaway');
r = await throwaway.call('POST', '/auth/provider/register', {
  providerKind: 'freelancer', name: 'Audit Throwaway', gender: 'male', mobile: rnd('89'),
  pin: '778899', hourlyRate: 250, deviceId: 'audit-throwaway', languages: ['English'],
  addresses: [{ addressType: 'home', line1: '1 Throwaway Rd', city: 'Ahmedabad', latitude: 23.0109, longitude: 72.5768 }],
  workHours: [{ dayOfWeek: 'mon', startTime: '09:00:00', endTime: '18:00:00' }],
  expertise: [{ serviceType: 'companion' }],
});
const throwawayId = r.json?.provider?.providerId;
r = await admin.call('DELETE', `/admin/providers/${throwawayId}`);
ok('DELETE /admin/providers/:id  allows one with no history', r.ok, brief(r));
ok('  and it is gone from the directory',
   !(await admin.call('GET', '/admin/providers?status=all')).json.providers.some((x) => x.provider_id === throwawayId));

r = await admin.call('DELETE', `/admin/providers/${orgId}`);
ok('DELETE /admin/providers/:id  refuses the organization that took a booking', !r.ok, brief(r));

// =================================================================== EDGES
section('EDGE CASES AND REFUSALS');

r = await device('nobody').call('GET', '/customers/me');
ok('no token means no customer profile', r.status === 401, brief(r));
r = await device('nobody').call('GET', '/admin/providers');
ok('no token means no admin', r.status === 401, brief(r));
r = await cust.call('GET', '/admin/providers');
ok('a customer token cannot reach admin', !r.ok, brief(r));
r = await prov.call('GET', '/customers/me');
ok('a provider token cannot reach the customer profile', !r.ok, brief(r));

const forged = device('forger');
forged.token = 'eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYWRtaW4iLCJpZCI6MX0.nope';
ok('a forged token is rejected', !(await forged.call('GET', '/admin/providers')).ok);

r = await cust.call('GET', `/providers/search?service_type=nurse&date_from=not-a-date`);
ok('a malformed date gives 422, not an empty list', r.status === 422, brief(r));
r = await cust.call('GET', `/providers/search?date_from=${day}`);
ok('a search with no service type is refused', !r.ok, brief(r));
r = await cust.call('GET', `/providers/search?service_type=nurse&date_from=${day}`);
ok('a search with no hours still finds people', r.ok && r.json.count > 0, brief(r));

r = await cust.call('PUT', '/customers/me', { preferredCommMode: 'smoke-signal' });
ok('an unknown contact mode gives a clear 422', r.status === 422, brief(r));

r = await cust.call('PUT', '/customers/me', { gender: 'n/a' });
ok('an unknown gender gives a clear 422, not a 500', r.status === 422, brief(r));

r = await device('gender-probe').call('POST', '/auth/provider/register', {
  providerKind: 'freelancer', name: 'Gender Probe', gender: 'n/a', mobile: rnd('90'),
  pin: '112233', hourlyRate: 300, deviceId: 'gender-probe', languages: ['English'],
  addresses: [{ addressType: 'home', line1: '1 Probe Rd', city: 'Ahmedabad', latitude: 23.0109, longitude: 72.5768 }],
  workHours: [{ dayOfWeek: 'mon', startTime: '09:00:00', endTime: '18:00:00' }],
  expertise: [{ serviceType: 'nurse' }],
});
ok('registering with an unknown gender gives 422, not 500', r.status === 422, brief(r));

r = await cust.call('GET', '/bookings/999999');
ok('a booking that does not exist gives 404', r.status === 404, brief(r));

r = await cust.call('POST', '/bookings', { serviceType: 'nurse' });
ok('an incomplete booking is refused', !r.ok, brief(r));

r = await cust.call('GET', "/customers/me/vitals?type=' OR 1=1--");
ok('an injection attempt does not damage anything', r.ok || r.status === 422, brief(r));

// ==================================================================== DONE
console.log(`\n${'='.repeat(70)}`);
console.log(`  ${passed}/${passed + failures.length} passed`);
if (failures.length) {
  console.log('\n  FAILED:');
  for (const f of failures) console.log(`    - ${f}`);
}
if (untested.length) {
  console.log('\n  NOT REACHED:');
  for (const u of untested) console.log(`    - ${u}`);
}
console.log('='.repeat(70));
if (failures.length) process.exitCode = 1;
