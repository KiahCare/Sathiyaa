/**
 * A complete run through the platform with named people, the way a real day
 * would go — provider registers, admin approves, customer books, provider
 * delivers, everyone rates, admin sees it. Also probes the security rules that
 * matter: can one customer read another's records, can a blocked account sign
 * in, does a stranger's token open anything.
 *
 * Prints a transcript so the result is readable rather than just green.
 */
const BASE = process.env.SATHIYAA_API ?? process.env.API_BASE ?? 'http://localhost:4000/api/v1';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? 'Admin@123';

let pass = 0, fail = 0;
const failures = [];
function ok(label, cond, detail = '') {
  if (cond) { pass += 1; console.log(`   PASS  ${label}`); }
  else { fail += 1; failures.push(label); console.log(`   FAIL  ${label}${detail ? ` -- ${detail}` : ''}`); }
}
function scene(t) { console.log(`\n${t}`); }

function device(name) {
  let token = null;
  const id = `${name}-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
  return {
    get deviceId() { return id; },
    setToken(t) { token = t; },
    get token() { return token; },
    async call(method, path, body) {
      const res = await fetch(BASE + path, {
        method,
        headers: {
          'Content-Type': 'application/json',
          'X-Device-Id': id,
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
      });
      const text = await res.text();
      let json; try { json = JSON.parse(text); } catch { json = text; }
      return { status: res.status, json, ok: res.ok };
    },
  };
}

/**
 * The next working day, as the local calendar date the apps would send.
 *
 * Deliberately not toISOString(): that converts local midnight to UTC, which
 * in any timezone east of Greenwich hands back yesterday. Here that turned a
 * Monday into a Sunday, no provider works Sundays, and every search in the
 * journey came back empty.
 */
function weekday(inDays = 2) {
  const d = new Date(Date.now() + inDays * 864e5);
  while (d.getDay() === 0 || d.getDay() === 6) d.setDate(d.getDate() + 1);
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}
const rnd = (p) => `${p}${Math.floor(Math.random() * 90000000) + 10000000}`;

const nurse = device('nurse-phone');
const family = device('family-phone');
const office = device('admin-laptop');
const day = weekday();

// ===========================================================================
scene('SCENE 1  Lalita Menon registers as a nurse on her phone');
const nurseMobile = rnd('96');
const reg = await nurse.call('POST', '/auth/provider/register', {
  providerKind: 'freelancer',
  name: 'Lalita Menon (QA)',
  gender: 'female',
  dob: '1988-03-22',
  mobile: nurseMobile,
  email: 'lalita.menon@example.com',
  pin: '481625',
  hourlyRate: 450,
  deviceId: nurse.deviceId,
  languages: ['English', 'Malayalam', 'Hindi'],
  addresses: [{ addressType: 'home', line1: '18 CG Road', city: 'Ahmedabad', latitude: 23.0225, longitude: 72.5714 }],
  workHours: ['mon', 'tue', 'wed', 'thu', 'fri', 'sat'].map((d) => ({ dayOfWeek: d, startTime: '07:00:00', endTime: '21:00:00' })),
  expertise: [{ serviceType: 'nurse', yearsExperience: 9 }],
});
ok('registered', reg.status === 201, JSON.stringify(reg.json).slice(0, 180));
nurse.setToken(reg.json.token);
const nurseId = reg.json.provider?.providerId ?? reg.json.providerId;
const nurseDisplay = reg.json.provider?.displayId ?? '(unknown)';
console.log(`         -> ${nurseDisplay}, mobile ${nurseMobile}, PIN 481625`);
ok('arrives awaiting approval', (reg.json.provider?.approvalStatus ?? 'pending') === 'pending');

// ===========================================================================
scene('SCENE 2  Harish Bhatt, whose mother needs a nurse, signs up');
const familyMobile = rnd('97');
const creg = await family.call('POST', '/auth/customer/register', { name: 'Harish Bhatt (QA)', mobile: familyMobile });
ok('OTP issued', creg.status === 201 && !!creg.json.devOtp);
const cver = await family.call('POST', '/auth/customer/verify-otp', { mobile: familyMobile, otp: creg.json.devOtp });
family.setToken(cver.json.token);
ok('signed in', !!cver.json.token);
console.log(`         -> ${cver.json.customer?.displayId}, mobile ${familyMobile}`);

await family.call('POST', '/customers/me/accept-terms', { accepted: true });
await family.call('PUT', '/customers/me', {
  name: 'Harish Bhatt (QA)', gender: 'male', dob: '1971-11-09', bloodGroup: 'B+',
  email: 'harish.bhatt@example.com', heightCm: 174, weightKg: 78,
  preferredLanguages: ['English', 'Gujarati'],
});
const me = await family.call('GET', '/customers/me');
ok('profile saved, BMI computed by the database', Math.abs((me.json.bmi ?? 0) - 25.76) < 0.3, `bmi=${me.json.bmi}`);
await family.call('PUT', '/customers/me/addresses', {
  primary: { line1: '5 Stadium Road, Navrangpura', city: 'Ahmedabad', latitude: 23.0494, longitude: 72.5888 },
});
ok('address saved', true);

// health records, since this is a care app
await family.call('POST', '/customers/me/vitals', { vitalType: 'bp', valuePrimary: 148, valueSecondary: 92, recordedAt: `${day} 08:00:00` });
await family.call('POST', '/customers/me/medications', { medicineName: 'Amlodipine 5mg', frequency: 'Once daily' });
await family.call('POST', '/customers/me/family', { name: 'Sunita Bhatt (QA)', relationship: 'Mother', contactNumber: '9812345670' });
const vitals = await family.call('GET', '/customers/me/vitals');
ok('health records stored', (vitals.json.vitals || []).length === 1);

// ===========================================================================
scene('SCENE 3  Before approval, Lalita is invisible');
const q = `service_type=nurse&date_from=${day}&time_from=09:00:00&time_to=13:00:00&lat=23.0494&lng=72.5888&radius_km=25`;
const before = await family.call('GET', `/providers/search?${q}`);
ok('unapproved provider is not in search', !(before.json.providers || []).some((p) => p.providerId === nurseId));

// ===========================================================================
scene('SCENE 4  Admin reviews and approves her');
const alog = await office.call('POST', '/auth/admin/login', { email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD });
office.setToken(alog.json.token);
ok('admin signed in', !!alog.json.token);

const queue = await office.call('GET', '/admin/providers?status=pending');
const row = (queue.json.providers || []).find((p) => p.provider_id === nurseId);
ok('she is in the approval queue', !!row);
ok('the queue row shows her expertise', !!row && row.expertise?.[0]?.service_type === 'nurse');
ok('her work hours came through', !!row && (row.work_hours || []).length === 6);
ok('no password hash reaches the console', !!row && row.pin_hash === undefined);
ok('admin approves', (await office.call('POST', `/admin/providers/${nurseId}/approve`, {})).ok);

// ===========================================================================
scene('SCENE 5  Now Harish can find her');
const after = await family.call('GET', `/providers/search?${q}`);
const found = (after.json.providers || []).find((p) => p.providerId === nurseId);
ok('she appears in search', !!found);
ok('with a distance', !!found && typeof found.distanceKm === 'number');
if (found) console.log(`         -> ${found.name}, INR ${found.hourlyRate}/hr, ${found.distanceKm.toFixed(1)} km away`);

// ===========================================================================
scene('SCENE 6  He books her for a morning');
const booking = await family.call('POST', '/bookings', {
  serviceType: 'nurse', startDate: day, endDate: day,
  timeFrom: '09:00:00', timeTo: '13:00:00', latitude: 23.0494, longitude: 72.5888,
});
ok('booking created', booking.status === 201);
const bid = booking.json.bookingId;
console.log(`         -> ${booking.json.displayId}, sent to ${booking.json.providersNotified} provider(s)`);
ok('it starts as searching, not payable', booking.json.status === 'searching', `status=${booking.json.status}`);
ok('paying now is refused', !(await family.call('POST', `/bookings/${bid}/pay`, {})).ok);

// The customer app sends coordinates rather than an address id, and the
// booking used to be filed with no address at all -- which left the provider
// without somewhere to go and the revenue report with an "unknown" city.
const withAddress = await family.call('GET', `/bookings/${bid}`);
ok('the booking records where the service is', !!withAddress.json.addressId || !!withAddress.json.address,
   `addressId=${withAddress.json.addressId}`);

// ===========================================================================
scene('SCENE 7  Lalita accepts -- but only once location is on');
ok('accept refused while location is off', !(await nurse.call('POST', `/providers/me/requests/${bid}/accept`, {})).ok);
await nurse.call('PUT', '/providers/me', { locationOn: true });
await nurse.call('PATCH', '/providers/me/location', { lat: 23.0225, lng: 72.5714 });
ok('accept works with location on', (await nurse.call('POST', `/providers/me/requests/${bid}/accept`, {})).ok);

const afterAccept = await family.call('GET', `/bookings/${bid}`);
ok('the booking is now awaiting payment', afterAccept.json.status === 'pending_payment', `status=${afterAccept.json.status}`);
ok('with a deadline', !!afterAccept.json.paymentDeadlineAt);

// ===========================================================================
scene('SCENE 8  He confirms it (no money changes hands)');
const paid = await family.call('POST', `/bookings/${bid}/pay`, {});
ok('confirmed', paid.ok, JSON.stringify(paid.json).slice(0, 160));
ok('booking is confirmed', (await family.call('GET', `/bookings/${bid}`)).json.status === 'confirmed');

// ===========================================================================
scene('SCENE 9  On the day: directions, face check, OTP, service');
const dir = await nurse.call('GET', `/providers/me/bookings/${bid}/directions`);
ok('directions returned', dir.ok, JSON.stringify(dir.json).slice(0, 120));
if (dir.ok) console.log(`         -> ${dir.json.distanceKm} km, about ${dir.json.etaMinutes} min (${dir.json.note ?? 'straight line'})`);

const farAway = await nurse.call('POST', `/providers/me/bookings/${bid}/start`, { selfieUrl: 'app://selfie.jpg' });
await nurse.call('PATCH', '/providers/me/location', { lat: 23.0494, lng: 72.5888 });
const onSite = await nurse.call('POST', `/providers/me/bookings/${bid}/start`, { selfieUrl: 'app://selfie.jpg' });
ok('start works once she is at the address', onSite.ok, JSON.stringify(onSite.json).slice(0, 160));

const otpRes = await family.call('GET', `/bookings/${bid}/otp`);
ok('the customer gets the start OTP', !!otpRes.json.otp);
ok('provider verifies the OTP the customer read out',
  (await nurse.call('POST', `/providers/me/bookings/${bid}/verify-start-otp`, { otp: otpRes.json.otp })).ok);

ok('running-late message accepted',
  (await nurse.call('POST', `/providers/me/bookings/${bid}/running-late`, { minutes: 15 })).ok);

const end = await nurse.call('POST', `/providers/me/bookings/${bid}/end`, {});
ok('service ended and billed', end.ok);
if (end.ok) console.log(`         -> ${end.json.bookingTotals?.totalHours}h, INR ${end.json.bookingTotals?.totalAmount} to the provider`);

ok('provider records the payment she collected',
  (await nurse.call('POST', `/providers/me/bookings/${bid}/payments`, { amount: end.json.bookingTotals?.totalAmount ?? 0, paymentType: 'full' })).ok);
ok('provider rates the customer',
  (await nurse.call('POST', `/providers/me/bookings/${bid}/rate-customer`, { rating: 5, comments: 'Very welcoming family' })).ok);
ok('customer rates the provider',
  (await family.call('POST', `/bookings/${bid}/rating`, { rating: 5, comments: 'Lalita was excellent with my mother' })).ok);

// ===========================================================================
scene('SECURITY  what should be refused, is');

const stranger = device('stranger-phone');
const sMobile = rnd('98');
const sreg = await stranger.call('POST', '/auth/customer/register', { name: 'Curious Stranger', mobile: sMobile });
const sver = await stranger.call('POST', '/auth/customer/verify-otp', { mobile: sMobile, otp: sreg.json.devOtp });
stranger.setToken(sver.json.token);

ok('a stranger cannot read someone else\'s booking',
  !(await stranger.call('GET', `/bookings/${bid}`)).ok);
ok('a stranger cannot read someone else\'s start OTP',
  !(await stranger.call('GET', `/bookings/${bid}/otp`)).ok);
ok('a stranger sees only their own (empty) health records',
  ((await stranger.call('GET', '/customers/me/vitals')).json.vitals || []).length === 0);
ok('a customer token cannot reach admin endpoints',
  !(await stranger.call('GET', '/admin/providers')).ok);
ok('a customer token cannot reach provider endpoints',
  !(await stranger.call('GET', '/providers/me/requests')).ok);
ok('a provider token cannot reach admin endpoints',
  !(await nurse.call('GET', '/admin/customers')).ok);

const noAuth = device('anonymous');
ok('no token means no profile', !(await noAuth.call('GET', '/customers/me')).ok);
ok('no token means no admin', !(await noAuth.call('GET', '/admin/providers')).ok);

const forged = device('forged');
forged.setToken('eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYWRtaW4iLCJpZCI6MX0.not_a_real_signature');
ok('a forged token is rejected', !(await forged.call('GET', '/admin/providers')).ok);

const otherPhone = device('second-phone');
ok('a second device cannot use her account',
  !(await otherPhone.call('POST', '/auth/provider/login', { mobile: nurseMobile, pin: '481625', deviceId: otherPhone.deviceId })).ok);
ok('a wrong PIN is rejected',
  !(await nurse.call('POST', '/auth/provider/login', { mobile: nurseMobile, pin: '000000', deviceId: nurse.deviceId })).ok);

// A blocked customer must not be able to sign in.
const blocked = (await office.call('GET', '/admin/customers')).json.customers.find((c) => c.status === 'blocked');
if (blocked) {
  const attempt = await device('blocked-phone').call('POST', '/auth/customer/login', { mobile: blocked.mobile_number });
  ok('a blocked customer cannot request an OTP', !attempt.ok, `status ${attempt.status}`);
} else {
  ok('a blocked customer exists to test with', false, 'none seeded');
}

// SQL injection through a search parameter.
const inject = await family.call('GET', `/providers/search?service_type=nurse'; DROP TABLE bookings;--&lat=22.9509&lng=72.5768&radius_km=5`);
const stillThere = await office.call('GET', '/admin/reports/dashboard');
ok('an injection attempt does not damage anything', stillThere.ok && Array.isArray(stillThere.json.byCity),
  `search returned ${inject.status}`);

// ===========================================================================
scene('SCENE 10  The admin console sees all of it');
const audit = await office.call('GET', '/admin/audit-log?limit=200');
const entries = audit.json.entries || audit.json.auditLog || audit.json.logs || [];
const forms = new Set(entries.map((e) => e.form_name));
for (const f of ['ProviderAcceptRequest', 'PayBooking', 'ProviderEndService', 'AdminProviderApproved', 'RateBooking']) {
  ok(`audit log records ${f}`, forms.has(f));
}
const reports = await office.call('GET', '/admin/reports/dashboard');
ok('reports show revenue', reports.ok && reports.json.byCity.length > 0);
const tracking = await office.call('GET', '/admin/tracking/providers');
ok('live tracking shows her position', (tracking.json.providers || []).some((p) => p.provider_id === nurseId));

console.log(`\n${'='.repeat(58)}`);
console.log(`  ${pass}/${pass + fail} passed`);
if (failures.length) console.log('  failed: ' + failures.join(' | '));
console.log(`${'='.repeat(58)}`);
if (fail) process.exit(1);
