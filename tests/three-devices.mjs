/**
 * The scenario that matters: three people, three devices, one booking.
 *
 * A provider registers on their phone. An admin approves them from a laptop.
 * A customer on a different phone searches, finds them, and books. The
 * provider accepts, drives over, starts and finishes the job. The admin sees
 * the whole thing in the audit trail.
 *
 * Each actor gets its own device id and its own token, exactly as three
 * separate installs would. If this passes, three phones on one Wi-Fi will
 * behave the same way.
 */
const BASE = process.env.SATHIYAA_API ?? process.env.API_BASE ?? 'http://localhost:4000/api/v1';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? 'Admin@123';

let pass = 0;
let fail = 0;
function check(label, ok, detail = '') {
  if (ok) { pass += 1; console.log(`  PASS  ${label}`); }
  else { fail += 1; console.log(`  FAIL  ${label}${detail ? ` — ${detail}` : ''}`); }
}
function step(text) { console.log(`\n${text}`); }

/** One device: its own id, its own token. */
function device(name) {
  const state = { token: null, deviceId: `${name}-${Date.now()}` };
  return {
    ...state,
    async call(method, path, body) {
      const res = await fetch(BASE + path, {
        method,
        headers: {
          'Content-Type': 'application/json',
          'X-Device-Id': state.deviceId,
          ...(state.token ? { Authorization: `Bearer ${state.token}` } : {}),
        },
        ...(body ? { body: JSON.stringify(body) } : {}),
      });
      const text = await res.text();
      let json; try { json = JSON.parse(text); } catch { json = text; }
      return { status: res.status, json, ok: res.ok };
    },
    setToken(t) { state.token = t; },
    get deviceId() { return state.deviceId; },
  };
}

function nextWeekday(inDays = 2) {
  const d = new Date(Date.now() + inDays * 864e5);
  while (d.getDay() === 0 || d.getDay() === 6) d.setDate(d.getDate() + 1);
  const pad = (n) => String(n).padStart(2, '0');
  // Local date: toISOString() would shift midnight back a day and land on a Sunday.
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

const providerPhone = device('provider-phone');
const customerPhone = device('customer-phone');
const adminLaptop = device('admin-laptop');
const day = nextWeekday();
const mobile = (p) => `${p}${Math.floor(Math.random() * 90000000) + 10000000}`;

// =========================================================================
step('1. Provider registers on their own phone');
const providerMobile = mobile('96');
const reg = await providerPhone.call('POST', '/auth/provider/register', {
  providerKind: 'freelancer',
  name: 'Three-Device Test Provider',
  gender: 'female',
  mobile: providerMobile,
  pin: '778899',
  hourlyRate: 200,
  deviceId: providerPhone.deviceId,
  languages: ['English', 'Hindi'],
  addresses: [{ addressType: 'home', line1: '9 Test Lane', city: 'Ahmedabad', latitude: 23.0225, longitude: 72.5714 }],
  workHours: ['mon', 'tue', 'wed', 'thu', 'fri', 'sat'].map((d) => ({ dayOfWeek: d, startTime: '08:00:00', endTime: '20:00:00' })),
  expertise: [{ serviceType: 'companion' }],
});
check('provider registered', reg.status === 201, JSON.stringify(reg.json).slice(0, 200));
providerPhone.setToken(reg.json.token);
const providerId = reg.json.provider?.providerId ?? reg.json.providerId;
check('arrives awaiting approval', (reg.json.provider?.approvalStatus ?? 'pending') === 'pending');

// =========================================================================
step('2. Customer registers on a different phone');
const customerMobile = mobile('97');
const creg = await customerPhone.call('POST', '/auth/customer/register', { name: 'Three-Device Test Customer', mobile: customerMobile });
const cver = await customerPhone.call('POST', '/auth/customer/verify-otp', { mobile: customerMobile, otp: creg.json.devOtp });
customerPhone.setToken(cver.json.token);
check('customer signed in', !!cver.json.token);
await customerPhone.call('PUT', '/customers/me/addresses', {
  primary: { line1: '3 Customer Road', city: 'Ahmedabad', latitude: 23.0225, longitude: 72.5714 },
});

// =========================================================================
step('3. Before approval, the provider is invisible to customer search');
const q = `service_type=companion&date_from=${day}&time_from=09:00:00&time_to=12:00:00&lat=23.0225&lng=72.5714&radius_km=25`;
const before = await customerPhone.call('GET', `/providers/search?${q}`);
const foundBefore = (before.json.providers || []).some((p) => p.providerId === providerId);
check('unapproved provider does NOT appear in search', !foundBefore);

// =========================================================================
step('4. Admin approves them from a laptop');
const alogin = await adminLaptop.call('POST', '/auth/admin/login', { email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD });
adminLaptop.setToken(alogin.json.token);
check('admin signed in', !!alogin.json.token);

const queue = await adminLaptop.call('GET', '/admin/providers?status=pending');
const inQueue = (queue.json.providers || []).find((p) => p.provider_id === providerId);
check('the new provider is in the approval queue', !!inQueue);
check('the queue row carries the detail the console renders', !!inQueue && Array.isArray(inQueue.expertise) && inQueue.expertise.length > 0,
  inQueue ? `expertise=${JSON.stringify(inQueue.expertise)}` : 'row missing');
check('no credential hash reaches the console', !!inQueue && inQueue.pin_hash === undefined);

const approve = await adminLaptop.call('POST', `/admin/providers/${providerId}/approve`, {});
check('admin approves', approve.ok, JSON.stringify(approve.json).slice(0, 160));

// =========================================================================
step('5. Now the customer can find them');
const after = await customerPhone.call('GET', `/providers/search?${q}`);
const match = (after.json.providers || []).find((p) => p.providerId === providerId);
check('approved provider appears in search', !!match);
check('search reports the distance', !!match && typeof match.distanceKm === 'number');

// =========================================================================
step('6. Customer books; provider gets the request on their phone');
const booking = await customerPhone.call('POST', '/bookings', {
  serviceType: 'companion', startDate: day, endDate: day,
  timeFrom: '09:00:00', timeTo: '12:00:00', latitude: 23.0225, longitude: 72.5714,
});
check('booking created', booking.status === 201, JSON.stringify(booking.json).slice(0, 200));
const bookingId = booking.json.bookingId;

const requests = await providerPhone.call('GET', '/providers/me/requests');
const rows = requests.json.requests || requests.json.bookings || [];
check('the request reaches the provider phone', rows.some((r) => (r.bookingId ?? r.booking_id) === bookingId),
  `saw ${rows.length} request(s)`);

// =========================================================================
step('7. Provider must switch location on before accepting');
const tooEarly = await providerPhone.call('POST', `/providers/me/requests/${bookingId}/accept`, {});
check('accept refused while location is off', !tooEarly.ok, `status ${tooEarly.status}`);

await providerPhone.call('PUT', '/providers/me', { locationOn: true });
await providerPhone.call('PATCH', '/providers/me/location', { lat: 23.0225, lng: 72.5714 });
const accepted = await providerPhone.call('POST', `/providers/me/requests/${bookingId}/accept`, {});
check('accept works once location is on', accepted.ok, JSON.stringify(accepted.json).slice(0, 160));

// =========================================================================
step('8. Customer pays inside the 15-minute window');
const paid = await customerPhone.call('POST', `/bookings/${bookingId}/pay`, {});
check('booking charge paid', paid.ok, JSON.stringify(paid.json).slice(0, 160));
const state = await customerPhone.call('GET', `/bookings/${bookingId}`);
check('booking is confirmed', state.json.status === 'confirmed', `status=${state.json.status}`);

// =========================================================================
step('9. Provider arrives, passes the face + location check, starts');
const start = await providerPhone.call('POST', `/providers/me/bookings/${bookingId}/start`, { selfieUrl: 'app://selfie.jpg' });
check('start check passes on site', start.ok, JSON.stringify(start.json).slice(0, 200));

const otp = await customerPhone.call('GET', `/bookings/${bookingId}/otp`);
check('customer receives the start OTP on their own phone', !!otp.json.otp, JSON.stringify(otp.json).slice(0, 160));

const verify = await providerPhone.call('POST', `/providers/me/bookings/${bookingId}/verify-start-otp`, { otp: otp.json.otp });
check('provider enters the OTP the customer read out', verify.ok, JSON.stringify(verify.json).slice(0, 160));

// =========================================================================
step('10. Running late reaches the customer, then the job finishes');
const late = await providerPhone.call('POST', `/providers/me/bookings/${bookingId}/running-late`, { minutes: 15 });
check('running-late message accepted', late.ok, JSON.stringify(late.json).slice(0, 160));

const end = await providerPhone.call('POST', `/providers/me/bookings/${bookingId}/end`, {});
check('service ended and billed', end.ok, JSON.stringify(end.json?.bookingTotals ?? end.json).slice(0, 200));

const rate = await customerPhone.call('POST', `/bookings/${bookingId}/rating`, { rating: 5, comments: 'Three-device test' });
check('customer rates the provider', rate.status === 201 || rate.ok);

// =========================================================================
step('11. Device binding: a second phone is refused');
const secondPhone = device('provider-phone-2');
const stolen = await secondPhone.call('POST', '/auth/provider/login', {
  mobile: providerMobile, pin: '778899', deviceId: secondPhone.deviceId,
});
check('a second device with the right PIN is refused', !stolen.ok, `status ${stolen.status}`);

step('12. Admin can release the device so a new phone works');
const reset = await adminLaptop.call('POST', `/admin/providers/${providerId}/reset-device`, {});
check('admin resets the device binding', reset.ok, JSON.stringify(reset.json).slice(0, 160));
const newPhone = await secondPhone.call('POST', '/auth/provider/login', {
  mobile: providerMobile, pin: '778899', deviceId: secondPhone.deviceId,
});
check('the new phone can now sign in', newPhone.ok, JSON.stringify(newPhone.json).slice(0, 160));

// =========================================================================
step('13. Admin sees the whole thing in the audit trail');
const audit = await adminLaptop.call('GET', '/admin/audit-log?limit=100');
const entries = audit.json.entries || audit.json.auditLog || audit.json.logs || [];
const forms = new Set(entries.map((e) => e.form_name));
for (const expected of ['ProviderAcceptRequest', 'PayBooking', 'ProviderEndService', 'AdminProviderDeviceReset']) {
  check(`audit trail records ${expected}`, forms.has(expected));
}

console.log(`\n=== ${pass}/${pass + fail} passed ===`);
if (fail) process.exit(1);
