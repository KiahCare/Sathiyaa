// Dumps the real JSON shape of every endpoint the Flutter apps will call, so
// the Dart parsers are written against what the server actually returns
// rather than against the contract's prose.
const BASE = process.env.SATHIYAA_API ?? process.env.API_BASE ?? 'http://localhost:4000/api/v1';

async function call(method, path, { token, body } = {}) {
  const res = await fetch(BASE + path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      'X-Device-Id': 'shape-probe',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const text = await res.text();
  try { return { status: res.status, json: JSON.parse(text) }; } catch { return { status: res.status, json: text }; }
}

function shape(v, depth = 0) {
  if (v === null) return 'null';
  if (Array.isArray(v)) return v.length ? `[${shape(v[0], depth + 1)}]` : '[]';
  if (typeof v === 'object') {
    if (depth > 2) return '{...}';
    return '{' + Object.entries(v).map(([k, val]) => `${k}:${shape(val, depth + 1)}`).join(', ') + '}';
  }
  return typeof v;
}

// Dumping shapes is still making live calls. A 5xx means the server broke,
// and that has to reach the exit code -- otherwise a runner reads the zero
// and calls a broken server green.
let serverErrors = 0;
function show(label, r) {
  const bad = r.status >= 500;
  if (bad) serverErrors += 1;
  console.log(`\n### ${label}  [${r.status}]${bad ? '  <-- SERVER ERROR' : ''}`);
  console.log(shape(r.json));
}

const mobile = '98888' + String(Math.floor(Math.random() * 90000) + 10000);
const reg = await call('POST', '/auth/customer/register', { body: { name: 'Shape Probe', mobile } });
show('POST /auth/customer/register', reg);
const ver = await call('POST', '/auth/customer/verify-otp', { body: { mobile, otp: reg.json.devOtp } });
show('POST /auth/customer/verify-otp', ver);
const CT = ver.json.token;

show('GET /customers/me', await call('GET', '/customers/me', { token: CT }));
show('PUT /customers/me', await call('PUT', '/customers/me', { token: CT, body: { name: 'Shape Probe', gender: 'female', bloodGroup: 'B+', heightCm: 160, weightKg: 60, email: 'p@example.com', preferredLanguages: ['English'] } }));
show('PUT /customers/me/addresses', await call('PUT', '/customers/me/addresses', { token: CT, body: { primary: { line1: '1 Probe St', city: 'Ahmedabad', latitude: 23.0225, longitude: 72.5714 }, secondary: { line1: '2 Probe Rd', city: 'Ahmedabad', latitude: 23.0309, longitude: 72.5768 } } }));
show('POST /customers/me/vitals', await call('POST', '/customers/me/vitals', { token: CT, body: { vitalType: 'bp', systolic: 120, diastolic: 80, recordedAt: '2026-09-01' } }));
show('GET /customers/me/vitals', await call('GET', '/customers/me/vitals', { token: CT }));
show('POST /customers/me/medications', await call('POST', '/customers/me/medications', { token: CT, body: { medicineName: 'Probe 500', frequency: 'Daily' } }));
show('GET /customers/me/medications', await call('GET', '/customers/me/medications', { token: CT }));
show('POST /customers/me/surgeries', await call('POST', '/customers/me/surgeries', { token: CT, body: { surgeryName: 'Probe op', surgeryDate: '2020-01-01' } }));
show('GET /customers/me/surgeries', await call('GET', '/customers/me/surgeries', { token: CT }));
show('POST /customers/me/allergies', await call('POST', '/customers/me/allergies', { token: CT, body: { allergyName: 'Dust', onsetDate: '2019-05-01', isActive: true } }));
show('GET /customers/me/allergies', await call('GET', '/customers/me/allergies', { token: CT }));
show('POST /customers/me/insurance', await call('POST', '/customers/me/insurance', { token: CT, body: { insuredWith: 'Star', policyNumber: 'P1', startDate: '2026-01-01', endDate: '2026-12-31' } }));
show('GET /customers/me/insurance', await call('GET', '/customers/me/insurance', { token: CT }));
show('POST /customers/me/family', await call('POST', '/customers/me/family', { token: CT, body: { name: 'Kin', relationship: 'Son', contactNumber: '9000000001' } }));
show('GET /customers/me/family', await call('GET', '/customers/me/family', { token: CT }));
show('POST /customers/me/accept-terms', await call('POST', '/customers/me/accept-terms', { token: CT, body: { accepted: true } }));
show('POST /customers/me/registration-payment', await call('POST', '/customers/me/registration-payment', { token: CT, body: {} }));

const d = new Date(Date.now() + 3 * 864e5);
while (d.getDay() === 0 || d.getDay() === 6) d.setDate(d.getDate() + 1);
// Local calendar date, not toISOString(): the latter shifts local midnight
// back to the previous UTC day and silently picks a Sunday.
const localYmd = (d) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const day = localYmd(d);

const search = await call('GET', `/providers/search?service_type=companion&date_from=${day}&time_from=09:00:00&time_to=12:00:00&lat=23.0225&lng=72.5714&radius_km=50`);
show('GET /providers/search', search);
const firstProvider = (search.json.providers ?? search.json.data ?? [])[0];
if (firstProvider) show('GET /providers/:id', await call('GET', `/providers/${firstProvider.providerId ?? firstProvider.provider_id ?? firstProvider.id}`));

show('GET /customers/me/linked-providers', await call('GET', '/customers/me/linked-providers', { token: CT }));

const booking = await call('POST', '/bookings', { token: CT, body: { serviceType: 'companion', startDate: day, endDate: day, timeFrom: '09:00:00', timeTo: '12:00:00', latitude: 23.0225, longitude: 72.5714 } });
show('POST /bookings', booking);
const bid = booking.json.bookingId ?? booking.json.booking?.bookingId ?? booking.json.id;
show('GET /bookings?scope=current', await call('GET', '/bookings?scope=current', { token: CT }));
show('GET /bookings/:id', await call('GET', `/bookings/${bid}`, { token: CT }));

const plogin = await call('POST', '/auth/provider/login', { body: { mobile: '9600000000', pin: '123456', deviceId: 'shape-probe' } });
show('POST /auth/provider/login', plogin);
const PT = plogin.json.token;
show('GET /providers/me', await call('GET', '/providers/me', { token: PT }));
show('GET /providers/me/requests', await call('GET', '/providers/me/requests', { token: PT }));
show('GET /providers/me/appointments?scope=future', await call('GET', '/providers/me/appointments?scope=future', { token: PT }));
show('GET /providers/me/dashboard', await call('GET', '/providers/me/dashboard?period=month', { token: PT }));
show('GET /providers/me/time-bank', await call('GET', '/providers/me/time-bank', { token: PT }));
show('PATCH /providers/me/location', await call('PATCH', '/providers/me/location', { token: PT, body: { lat: 23.0225, lng: 72.5714 } }));
show('POST /providers/me/calendar-blocks', await call('POST', '/providers/me/calendar-blocks', { token: PT, body: { blockStart: '2027-01-05 00:00:00', blockEnd: '2027-01-06 23:59:59', reason: 'probe' } }));

const orgLogin = await call('POST', '/auth/provider/login', { body: { mobile: '9611122233', pin: '123456', deviceId: 'shape-probe-org' } });
const OT = orgLogin.json.token;
show('GET /providers/employees (org)', await call('GET', '/providers/employees', { token: OT }));
show('GET /providers/me/utilization (org)', await call('GET', '/providers/me/utilization', { token: OT }));
show('GET /providers/me/schedule-overview (org)', await call('GET', `/providers/me/schedule-overview?date=${day}`, { token: OT }));

show('ERROR envelope (bad token)', await call('GET', '/customers/me', { token: 'not-a-token' }));

console.log(serverErrors
  ? `\n${serverErrors} endpoint(s) returned 5xx`
  : '\nno endpoint returned 5xx');
if (serverErrors) process.exitCode = 1;
