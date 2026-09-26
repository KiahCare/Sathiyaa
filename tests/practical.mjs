/**
 * The practical, run as a script first.
 *
 * This is the exact sequence a person would follow by hand across three
 * devices: a provider registers with documents, admin reviews and approves,
 * a customer signs up and requests a service, the provider accepts, the
 * service runs, and the admin console shows every step of it.
 *
 * It exists so the walk-through cannot get stuck: if any step here fails, the
 * same step would have failed on the phone.
 */
const BASE = process.env.SATHIYAA_API ?? process.env.API_BASE ?? 'http://localhost:4000/api/v1';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? 'Admin@123';

let passed = 0;
let failed = 0;
const failures = [];

function scene(title) {
  console.log(`\n${'='.repeat(68)}\n  ${title}\n${'='.repeat(68)}`);
}
function ok(label, condition, detail = '') {
  if (condition) {
    passed++;
    console.log(`   PASS  ${label}`);
  } else {
    failed++;
    failures.push(label);
    console.log(`   FAIL  ${label}${detail ? `  -- ${detail}` : ''}`);
  }
}
function note(text) {
  console.log(`         -> ${text}`);
}

/** One device: its own token and its own device id, exactly like a handset. */
function device(deviceId) {
  let token = null;
  return {
    deviceId,
    get token() {
      return token;
    },
    set token(t) {
      token = t;
    },
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
      try {
        json = JSON.parse(text);
      } catch {
        json = text;
      }
      return { status: res.status, ok: res.ok, json };
    },
  };
}

/** The next working day, as a local calendar date. */
function weekday(inDays = 2) {
  const d = new Date(Date.now() + inDays * 864e5);
  while (d.getDay() === 0 || d.getDay() === 6) d.setDate(d.getDate() + 1);
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

const rnd = (prefix) => `${prefix}${Math.floor(Math.random() * 90000000) + 10000000}`;

const nursePhone = device('practical-nurse-phone');
const familyPhone = device('practical-family-phone');
const office = device('practical-admin-laptop');
const day = weekday();

// =====================================================================
scene('STEP 1  A nurse registers, with her documents');

const nurseMobile = rnd('98');
const nursePin = '481625';

// Documents are uploaded first, exactly as the app now does: pick, upload,
// then send the URL with the registration.
async function uploadDoc(dev, category, filename) {
  const body = Buffer.from(`fake ${category} scan for the practical run`);
  const boundary = '----practical' + Math.random().toString(16).slice(2);
  const parts = Buffer.concat([
    Buffer.from(
      `--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="${filename}"\r\n` +
        `Content-Type: image/jpeg\r\n\r\n`
    ),
    body,
    Buffer.from(`\r\n--${boundary}--\r\n`),
  ]);
  const res = await fetch(`${BASE}/uploads?category=${category}`, {
    method: 'POST',
    headers: {
      'Content-Type': `multipart/form-data; boundary=${boundary}`,
      'X-Device-Id': dev.deviceId,
      ...(dev.token ? { Authorization: `Bearer ${dev.token}` } : {}),
    },
    body: parts,
  });
  const text = await res.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    json = text;
  }
  return { status: res.status, ok: res.ok, json };
}

// Uploading needs a signed-in caller, so the account is created first and the
// documents go up immediately afterwards -- which is exactly what the app now
// does. Uploading during the form would have failed with a 401.
ok('an anonymous upload is refused',
   !(await uploadDoc(nursePhone, 'aadhar', 'nope.jpg')).ok);

const reg = await nursePhone.call('POST', '/auth/provider/register', {
  providerKind: 'freelancer',
  name: 'Anjali Deshpande (QA)',
  gender: 'female',
  dob: '1989-04-11',
  mobile: nurseMobile,
  email: 'anjali.deshpande@example.com',
  pin: nursePin,
  hourlyRate: 460,
  deviceId: nursePhone.deviceId,
  languages: ['English', 'Hindi', 'Marathi'],
  addresses: [
    {
      addressType: 'home',
      line1: '48 Jayanagar 4th Block',
      city: 'Ahmedabad',
      latitude: 22.9759,
      longitude: 72.5706,
    },
  ],
  workHours: ['mon', 'tue', 'wed', 'thu', 'fri', 'sat'].map((d) => ({
    dayOfWeek: d,
    startTime: '08:00:00',
    endTime: '20:00:00',
  })),
  expertise: [{ serviceType: 'nurse', yearsExperience: 11 }],
});
ok('registration accepted', reg.status === 201, `${reg.status} ${JSON.stringify(reg.json).slice(0, 120)}`);
const nurseId = reg.json?.provider?.providerId;
nursePhone.token = reg.json?.token;
note(`${reg.json?.provider?.displayId}  Anjali Deshpande  mobile ${nurseMobile}  PIN ${nursePin}`);
ok('she starts as pending, not approved', reg.json?.provider?.approvalStatus === 'pending');

// Now signed in, the documents go up and are saved on the profile -- the
// order the registration screen follows.
const aadhar = await uploadDoc(nursePhone, 'aadhar', 'aadhar.jpg');
ok('aadhar uploads once signed in', aadhar.ok, `${aadhar.status} ${JSON.stringify(aadhar.json).slice(0, 90)}`);
const police = await uploadDoc(nursePhone, 'police-verification', 'police.jpg');
ok('police verification uploads', police.ok);
const medical = await uploadDoc(nursePhone, 'medical-certificate', 'medical.jpg');
ok('medical certificate uploads', medical.ok);

const extras = await nursePhone.call('PUT', '/providers/me', {
  aadharDocUrl: aadhar.json?.url,
  policeVerificationUrl: police.json?.url,
  medicalCertificateUrl: medical.json?.url,
  medicalCertificateValidFrom: '2026-01-01',
  medicalCertificateValidTo: '2027-12-31',
  policeVerificationValidFrom: '2025-06-01',
  policeVerificationValidTo: '2027-05-31',
});
ok('documents and validity dates saved', extras.ok, `${extras.status}`);

// =====================================================================
scene('STEP 2  Admin reviews her application');

const adminLogin = await office.call('POST', '/auth/admin/login', {
  email: 'admin@sathiyaa.com',
  password: ADMIN_PASSWORD,
});
ok('admin signs in', adminLogin.ok);
office.token = adminLogin.json?.token;

const queue = await office.call('GET', '/admin/providers?status=pending');
const inQueue = (queue.json?.providers || []).find((p) => p.provider_id === nurseId);
ok('she is in the pending queue', !!inQueue);
ok('the queue row carries her documents', !!inQueue?.aadhar_doc_url && !!inQueue?.police_verification_url,
   `aadhar=${inQueue?.aadhar_doc_url} police=${inQueue?.police_verification_url}`);
ok('her expertise came through', (inQueue?.expertise || []).some((e) => e.service_type === 'nurse'));
ok('her work hours came through', (inQueue?.work_hours || []).length === 6);
ok('no PIN hash is exposed to the console', !('pin_hash' in (inQueue || {})));

const approve = await office.call('POST', `/admin/providers/${nurseId}/approve`, {});
ok('admin approves her', approve.ok);

// =====================================================================
scene('STEP 3  A family signs up and asks for a nurse');

const familyMobile = rnd('97');
const custReg = await familyPhone.call('POST', '/auth/customer/register', {
  name: 'Rohan Saxena (QA)',
  mobile: familyMobile,
});
ok('OTP issued', !!custReg.json?.devOtp, JSON.stringify(custReg.json).slice(0, 90));
const verify = await familyPhone.call('POST', '/auth/customer/verify-otp', {
  mobile: familyMobile,
  otp: custReg.json?.devOtp,
});
ok('signed in', verify.ok);
familyPhone.token = verify.json?.token;
note(`${verify.json?.customer?.displayId}  Rohan Saxena  mobile ${familyMobile}`);

await familyPhone.call('POST', '/customers/me/accept-terms', {});

// Every contact mode at once -- the combination that used to fail.
const profile = await familyPhone.call('PUT', '/customers/me', {
  gender: 'male',
  dob: '1979-02-20',
  bloodGroup: 'B+',
  email: 'rohan.saxena@example.com',
  heightCm: 176,
  weightKg: 79,
  preferredCommMode: 'email,call,sms',
  preferredCommTimeframe: '09:00-19:00',
  preferredLanguages: ['English', 'Hindi'],
});
ok('profile saves with all three contact modes', profile.ok, `${profile.status} ${JSON.stringify(profile.json).slice(0, 110)}`);
ok('all three came back', profile.json?.preferredCommMode === 'email,call,sms', `got ${profile.json?.preferredCommMode}`);
ok('BMI computed by the database', typeof profile.json?.bmi === 'number' || profile.json?.bmi != null);

const addr = await familyPhone.call('PUT', '/customers/me/addresses', {
  primary: {
    line1: '21 CG Road',
    city: 'Ahmedabad',
    pincode: '380038',
    latitude: 23.0293,
    longitude: 72.6176,
  },
});
ok('address saved', addr.ok, `${addr.status} ${JSON.stringify(addr.json).slice(0, 120)}`);

// =====================================================================
scene('STEP 4  She is findable, and gets booked');

const search = await familyPhone.call(
  'GET',
  `/providers/search?service_type=nurse&date_from=${day}&time_from=09:00:00&time_to=13:00:00` +
    `&lat=23.0293&lng=72.6176&radius_km=25`
);
const found = (search.json?.providers || []).find((p) => p.providerId === nurseId);
ok('she appears in search', !!found, `count=${search.json?.count}`);
ok('with a distance', typeof found?.distanceKm === 'number');
if (found) note(`${found.name}, INR ${found.hourlyRate}/hr, ${found.distanceKm.toFixed(1)} km away`);

const booking = await familyPhone.call('POST', '/bookings', {
  serviceType: 'nurse',
  startDate: day,
  endDate: day,
  timeFrom: '09:00:00',
  timeTo: '13:00:00',
  latitude: 23.0293,
  longitude: 72.6176,
});
ok('request created', booking.status === 201, `${booking.status} ${JSON.stringify(booking.json).slice(0, 110)}`);
const bid = booking.json?.bookingId;
note(`${booking.json?.displayId}, sent to ${booking.json?.providersNotified} provider(s)`);
ok('it goes out to at least one provider', (booking.json?.providersNotified ?? 0) > 0);
ok('it starts as searching', booking.json?.status === 'searching');
ok('confirming before anyone accepts is refused', !(await familyPhone.call('POST', `/bookings/${bid}/pay`, {})).ok);

// =====================================================================
scene('STEP 5  She sees it and accepts');

const requests = await nursePhone.call('GET', '/providers/me/requests');
const mine = (requests.json?.requests || requests.json?.bookings || []).find(
  (r) => (r.booking_id ?? r.bookingId) === bid
);
ok('the request is on her phone', !!mine, JSON.stringify(requests.json).slice(0, 140));

ok('accepting is refused while location is off',
   !(await nursePhone.call('POST', `/providers/me/requests/${bid}/accept`, {})).ok);
await nursePhone.call('PUT', '/providers/me', { locationOn: true });
await nursePhone.call('PATCH', '/providers/me/location', { lat: 22.9759, lng: 72.5706 });
const accept = await nursePhone.call('POST', `/providers/me/requests/${bid}/accept`, {});
ok('accepting works once location is on', accept.ok, `${accept.status} ${JSON.stringify(accept.json).slice(0, 100)}`);

const afterAccept = await familyPhone.call('GET', `/bookings/${bid}`);
ok('the family sees it awaiting confirmation', afterAccept.json?.status === 'pending_payment',
   `status=${afterAccept.json?.status}`);
ok('with a deadline to confirm by', !!afterAccept.json?.paymentDeadlineAt);
ok('and the address it is at', !!afterAccept.json?.addressId);

const confirm = await familyPhone.call('POST', `/bookings/${bid}/pay`, {});
ok('the family confirms (no money moves)', confirm.ok, `${confirm.status} ${JSON.stringify(confirm.json).slice(0, 100)}`);
ok('the booking is confirmed', (await familyPhone.call('GET', `/bookings/${bid}`)).json?.status === 'confirmed');

// =====================================================================
scene('STEP 6  On the day: directions, OTP, the visit');

const directions = await nursePhone.call('GET', `/providers/me/bookings/${bid}/directions`);
ok('directions come back', directions.ok);
if (directions.ok) {
  note(`${directions.json?.distanceKm} km, about ${directions.json?.etaMinutes} min` +
       `${directions.json?.note ? ` (${directions.json.note})` : ''}`);
  ok('from a real road route, not a straight line', !!directions.json?.polyline);
}

await nursePhone.call('PATCH', '/providers/me/location', { lat: 23.0293, lng: 72.6176 });

// The arrival photo, taken at the door. The app opens the camera for this;
// here we upload a stand-in so the same request shape is exercised.
const selfie = await uploadDoc(nursePhone, 'selfie', 'arrival.jpg');
ok('the arrival photo uploads', selfie.ok, `${selfie.status}`);

ok('starting without an arrival photo is refused',
   !(await nursePhone.call('POST', `/providers/me/bookings/${bid}/start`, {})).ok);

const start = await nursePhone.call('POST', `/providers/me/bookings/${bid}/start`, {
  selfieUrl: selfie.json?.url,
});
ok('she can start once she is at the address', start.ok, `${start.status} ${JSON.stringify(start.json).slice(0, 110)}`);

const otpRead = await familyPhone.call('GET', `/bookings/${bid}/otp`);
ok('the family is shown the start OTP', !!otpRead.json?.otp, JSON.stringify(otpRead.json).slice(0, 90));
const verifyOtp = await nursePhone.call('POST', `/providers/me/bookings/${bid}/verify-start-otp`, {
  otp: otpRead.json?.otp,
});
ok('she enters the OTP the family read out', verifyOtp.ok);

const late = await nursePhone.call('POST', `/providers/me/bookings/${bid}/running-late`, { minutes: 15 });
ok('a running-late message goes through', late.ok, `${late.status} ${JSON.stringify(late.json).slice(0, 110)}`);

const end = await nursePhone.call('POST', `/providers/me/bookings/${bid}/end`, {});
ok('the visit ends and is billed', end.ok, `${end.status} ${JSON.stringify(end.json).slice(0, 110)}`);
if (end.ok) note(`${end.json?.bookingTotals?.totalHours}h, INR ${end.json?.bookingTotals?.totalAmount} to the provider, ` +
     `INR ${end.json?.payment?.amountDue} due from the family`);

const recordPay = await nursePhone.call('POST', `/providers/me/bookings/${bid}/payments`, {
  amount: end.json?.payment?.amountDue ?? end.json?.bookingTotals?.totalCustomerAmount ?? 0,
  paymentType: 'full',
  note: 'Collected in cash at the door.',
});
ok('she records what the family paid her', recordPay.ok,
   `${recordPay.status} ${JSON.stringify(recordPay.json).slice(0, 110)}`);

ok('she rates the family', (await nursePhone.call('POST', `/providers/me/bookings/${bid}/rate-customer`, {
  rating: 5, comment: 'Very welcoming household.',
})).ok);
const familyRating = await familyPhone.call('POST', `/bookings/${bid}/rating`, {
  rating: 5, comment: 'Punctual and very kind.',
});
ok('the family rates her', familyRating.ok, `${familyRating.status} ${JSON.stringify(familyRating.json).slice(0, 110)}`);

// =====================================================================
scene('STEP 7  The admin console shows all of it');

const auditLog = await office.call('GET', '/admin/audit-log');
const forms = new Set((auditLog.json?.auditLog || []).map((r) => r.form_name));
for (const f of ['ProviderRegister', 'AdminProviderApproved', 'CreateBooking', 'ProviderAcceptRequest',
                 'PayBooking', 'ProviderStartService', 'ProviderEndService', 'ProviderRecordPayment']) {
  ok(`audit log records ${f}`, forms.has(f));
}

const reports = await office.call('GET', '/admin/reports/dashboard');
ok('reports show revenue by provider', (reports.json?.byProvider || []).length > 0);
const herRow = (reports.json?.byProvider || []).find((r) => r.provider_id === nurseId);
ok('her visit is in the revenue report', !!herRow, JSON.stringify(reports.json?.byProvider || []).slice(0, 130));
if (herRow) note(`${herRow.name}: ${herRow.bookings} booking(s), INR ${herRow.revenue}`);
ok('every revenue row has a provider name', (reports.json?.byProvider || []).every((r) => !!r.name));
// This run's booking, specifically -- older rows in the database may predate
// the fix that records an address, and the report is right to show those
// separately rather than pretend.
ok('this booking is filed under a real city',
   (reports.json?.byCity || []).some((c) => c.city === 'Ahmedabad'),
   JSON.stringify(reports.json?.byCity || []).slice(0, 140));
ok('the city bucket is never the raw word "unknown"',
   !(reports.json?.byCity || []).some((c) => c.city === 'unknown'));

const tracking = await office.call('GET', '/admin/tracking/providers');
const herPin = (tracking.json?.providers || []).find((p) => p.provider_id === nurseId);
ok('live tracking has her position', !!herPin?.current_latitude);

// =====================================================================
scene('STEP 8  Admin actions actually do something');

const blockRes = await office.call('POST', `/admin/providers/${nurseId}/block`, { note: 'practical run' });
ok('blocking her returns success', blockRes.ok);
let row = (await office.call('GET', '/admin/providers?status=all')).json.providers.find((p) => p.provider_id === nurseId);
ok('and she is actually blocked', row?.status === 'blocked', `status=${row?.status}`);
ok('blocking did not silently approve instead', row?.approval_status === 'approved');

const blockedLogin = await device('someone-elses-phone').call('POST', '/auth/provider/login', {
  mobile: nurseMobile, pin: nursePin,
});
ok('a blocked provider cannot sign in', !blockedLogin.ok, `${blockedLogin.status}`);

ok('unblocking her returns success', (await office.call('POST', `/admin/providers/${nurseId}/unblock`, {})).ok);
row = (await office.call('GET', '/admin/providers?status=all')).json.providers.find((p) => p.provider_id === nurseId);
ok('and she is active again', row?.status === 'active');

const custRow = (await office.call('GET', '/admin/customers')).json.customers.find(
  (c) => c.mobile_number === familyMobile
);
ok('the family is in the customer directory', !!custRow);
ok('blocking the family works', (await office.call('POST', `/admin/customers/${custRow.customer_id}/block`, {})).ok);
const blockedOtp = await device('family-again').call('POST', '/auth/customer/register', {
  name: 'Rohan Saxena (QA)', mobile: familyMobile,
});
ok('a blocked customer cannot request an OTP', !blockedOtp.ok, `${blockedOtp.status}`);
ok('unblocking the family works', (await office.call('POST', `/admin/customers/${custRow.customer_id}/unblock`, {})).ok);

const partners = await office.call('GET', '/admin/business-agents');
ok('business partners are listed', (partners.json?.businessAgents || []).length >= 3);
// A seeded partner by name, not whichever row happens to come first: an
// earlier test run can leave its own partner at the top of the list, with a
// different password, and the sign-in below would fail for the wrong reason.
const partner = (partners.json.businessAgents || []).find((p) => p.display_id === 'BP-000001')
  ?? partners.json.businessAgents[0];
note(`${partner.entity_name}  ${partner.display_id}  ${partner.contact_number_1}  ${partner.referral_code}`);
for (const identifier of [partner.display_id, partner.contact_number_1, partner.referral_code]) {
  const login = await device('partner-laptop').call('POST', '/auth/business-agent/login', {
    identifier, password: 'Partner@123',
  });
  ok(`a partner can sign in with ${identifier}`, login.ok, `${login.status}`);
}

// =====================================================================
console.log(`\n${'='.repeat(68)}`);
console.log(`  ${passed}/${passed + failed} passed`);
if (failures.length) {
  console.log('  failed:');
  for (const f of failures) console.log(`    - ${f}`);
}
console.log('='.repeat(68));
if (failed) process.exitCode = 1;
