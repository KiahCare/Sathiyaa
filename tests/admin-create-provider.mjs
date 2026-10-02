/**
 * Can the office create a provider, and can that provider then sign in?
 *
 * Most of Sathiyaa's carers are signed up in person rather than through the
 * app, and until the console could do it the only way was to borrow the
 * provider's handset and drive the app's registration form on it. When that was
 * done on an office phone instead, the account was bound to the office phone
 * and the provider could never sign in from their own.
 *
 * So this checks the whole path end to end, because every one of these steps
 * has a way of failing silently:
 *
 *   1. an administrator uploads the documents (the org-registration category
 *      used to be rejected by the upload endpoint, and registration swallows
 *      upload failures on purpose so nothing said so)
 *   2. a freelance carer is created from the console
 *   3. that carer signs in with the mobile number and PIN the office set, from
 *      a handset that has never been seen before, and the account binds to it
 *   4. a second handset is then refused
 *   5. the carer's own profile shows the documents, the validity dates and the
 *      rate that were entered in the console
 *   6. a family searching for that service, in that city, at those hours, is
 *      actually offered them -- which needs expertise rows, work-hours rows and
 *      coordinates, all three of which the matching query INNER JOINs or
 *      filters on
 *   7. an organisation is created, carries what an organisation has, and does
 *      NOT carry a gender, a date of birth or an Aadhaar card
 *   8. the refusals hold: a weak PIN, no coordinates, an expired police check,
 *      a nurse with no medical certificate, a duplicate mobile number, and
 *      creating an org_employee (which only the organisation itself may do)
 */
const BASE = process.env.SATHIYAA_API ?? process.env.API_BASE ?? 'http://localhost:4000/api/v1';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? 'Admin@123';

let failures = 0;
const mark = (pass, line) => {
  if (!pass) failures++;
  console.log(`${pass ? 'OK  ' : 'FAIL'} ${line}`);
};

const call = async (method, path, { token, body, deviceId } = {}) => {
  const r = await fetch(BASE + path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(deviceId ? { 'X-Device-Id': deviceId } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await r.text();
  let json;
  try { json = JSON.parse(text); } catch { json = text; }
  return { status: r.status, json };
};

/** A unique 10-digit mobile starting 6-9, so reruns never collide. */
const mobile = () => `97${Date.now().toString().slice(-6)}${Math.floor(Math.random() * 90 + 10)}`;
const ymd = (d) => d.toISOString().slice(0, 10);
const daysFromNow = (n) => ymd(new Date(Date.now() + n * 86400000));

// A one-pixel PNG, so the upload endpoint is given a real image of a real type
// rather than something it has to guess about.
const PNG_1PX = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==',
  'base64',
);

const upload = async (token, category) => {
  const form = new FormData();
  form.set('file', new Blob([PNG_1PX], { type: 'image/png' }), `${category}.png`);
  form.set('category', category);
  const r = await fetch(`${BASE}/uploads`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: form,
  });
  const json = await r.json().catch(() => ({}));
  return { status: r.status, url: json.url, json };
};

// ---- sign in as the office ----------------------------------------------
const adminLogin = await call('POST', '/auth/admin/login', {
  body: { email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD },
});
if (adminLogin.status !== 200) {
  console.error(`Could not sign in as admin (${adminLogin.status}).`, adminLogin.json);
  process.exit(1);
}
const ADMIN = adminLogin.json.token;

// ---- 1. the documents go up ---------------------------------------------
console.log('\nAn administrator uploading documents:');

const docs = {};
for (const category of ['aadhar', 'police-verification', 'medical-certificate', 'org-registration', 'photo']) {
  const up = await upload(ADMIN, category);
  docs[category] = up.url;
  mark(
    up.status === 201 && typeof up.url === 'string' && up.url.startsWith(`/uploads/${category}/`),
    `${category} uploads and returns a relative /uploads path (got ${up.status} ${up.url ?? ''})`,
  );
}

// ---- 2. a freelance carer is created ------------------------------------
console.log('\nCreating a freelance carer from the console:');

const carerMobile = mobile();
const CARER_PIN = '418276';
const created = await call('POST', '/admin/providers', {
  token: ADMIN,
  body: {
    providerKind: 'freelancer',
    name: 'Test Console Carer',
    gender: 'female',
    dob: '1990-04-12',
    mobile: carerMobile,
    email: 'test.console.carer@example.com',
    pin: CARER_PIN,
    hourlyRate: 320,
    languages: ['English', 'Gujarati'],
    photoUrl: docs.photo,
    aadharDocUrl: docs.aadhar,
    policeVerificationUrl: docs['police-verification'],
    policeVerificationValidFrom: daysFromNow(-200),
    policeVerificationValidTo: daysFromNow(400),
    address: {
      line1: '14 Shivalik Residency, Satellite',
      city: 'Ahmedabad',
      state: 'Gujarat',
      pincode: '380015',
      latitude: 23.0225,
      longitude: 72.5714,
    },
    workHours: [
      { dayOfWeek: 'mon', startTime: '08:00', endTime: '20:00' },
      { dayOfWeek: 'tue', startTime: '08:00', endTime: '20:00' },
      { dayOfWeek: 'wed', startTime: '08:00', endTime: '20:00' },
      { dayOfWeek: 'thu', startTime: '08:00', endTime: '20:00' },
      { dayOfWeek: 'fri', startTime: '08:00', endTime: '20:00' },
      { dayOfWeek: 'sat', startTime: '08:00', endTime: '20:00' },
      { dayOfWeek: 'sun', startTime: '08:00', endTime: '20:00' },
    ],
    expertise: [{ serviceType: 'companion' }],
    approvalStatus: 'approved',
    registrationFeePaid: true,
  },
});

mark(created.status === 201, `the carer is created (got ${created.status} ${JSON.stringify(created.json).slice(0, 220)})`);
const carer = created.json?.provider ?? {};
mark(/^SP-\d{6}$/.test(carer.display_id ?? ''), `a display id is issued (got ${carer.display_id})`);
mark(carer.approval_status === 'approved', `approved as asked (got ${carer.approval_status})`);
mark(carer.device_id === null, 'no device is bound, so the provider\'s own handset can claim it');
mark(
  Array.isArray(carer.work_hours) && carer.work_hours.length === 7,
  `work hours are stored (got ${carer.work_hours?.length} rows)`,
);
mark(
  Array.isArray(carer.expertise) && carer.expertise.length === 1,
  `expertise is stored (got ${carer.expertise?.length} rows)`,
);
mark(
  Number(carer.addresses?.[0]?.latitude) === 23.0225,
  `the address carries coordinates (got ${carer.addresses?.[0]?.latitude})`,
);
mark(
  carer.pin_hash === undefined,
  'the PIN hash is not in the response the console receives',
);

// ---- 3. that carer signs in, from a handset nobody has seen --------------
console.log('\nThe carer signing in to the provider app:');

const HANDSET = `qa-handset-${Date.now()}`;
const signIn = await call('POST', '/auth/provider/login', {
  deviceId: HANDSET,
  body: { mobile: carerMobile, pin: CARER_PIN, deviceId: HANDSET },
});
mark(signIn.status === 200 && !!signIn.json?.token, `signs in with the PIN the office set (got ${signIn.status})`);
mark(signIn.json?.provider?.approvalStatus === 'approved', 'and is told they are approved');
const CARER = signIn.json?.token;

const wrongPin = await call('POST', '/auth/provider/login', {
  deviceId: HANDSET,
  body: { mobile: carerMobile, pin: '999111', deviceId: HANDSET },
});
mark(wrongPin.status === 422, `a wrong PIN is refused (got ${wrongPin.status})`);

// ---- 4. a second handset is refused -------------------------------------
const otherHandset = await call('POST', '/auth/provider/login', {
  deviceId: `${HANDSET}-other`,
  body: { mobile: carerMobile, pin: CARER_PIN, deviceId: `${HANDSET}-other` },
});
mark(
  otherHandset.status === 403,
  `a second handset is refused now the account is bound (got ${otherHandset.status})`,
);

// ---- 5. the app sees what the console entered ----------------------------
console.log('\nWhat the carer sees on their own profile:');

const me = await call('GET', '/providers/me', { token: CARER, deviceId: HANDSET });
mark(me.status === 200, `the profile loads (got ${me.status})`);
mark(me.json?.name === 'Test Console Carer', `the name is theirs (got ${me.json?.name})`);
mark(Number(me.json?.hourlyRate) === 320, `the rate is the one entered (got ${me.json?.hourlyRate})`);
mark(!!me.json?.aadharDocUrl, 'the Aadhaar document is on the profile');
mark(!!me.json?.policeVerificationUrl, 'the police verification is on the profile');
mark(
  !!me.json?.policeVerificationValidFrom && !!me.json?.policeVerificationValidTo,
  `its validity dates are stored (from ${me.json?.policeVerificationValidFrom} to ${me.json?.policeVerificationValidTo})`,
);
mark(
  Array.isArray(me.json?.languages) && me.json.languages.includes('Gujarati'),
  `the languages are theirs, not a hardcoded default (got ${JSON.stringify(me.json?.languages)})`,
);

// ---- 6. a family is actually offered them -------------------------------
console.log('\nWhether a family searching is offered this carer:');

// The matching query is what decides whether this account is bookable at all,
// so running the real search is the only way to prove the three things that
// make a provider silently invisible -- no expertise row, no work-hours row, no
// coordinates -- are all present.
const found = await call('GET',
  '/providers/search?service_type=companion'
  + `&date_from=${daysFromNow(3)}&date_to=${daysFromNow(3)}`
  + '&time_from=10:00&time_to=14:00'
  + '&lat=23.0225&lng=72.5714&radius_km=25',
  { token: CARER });
const list = found.json?.providers ?? [];
mark(found.status === 200, `the search runs (got ${found.status})`);
mark(
  list.some((p) => p.displayId === carer.display_id),
  `the console-created carer is among the results (${found.json?.count ?? 0} returned)`,
);

// ---- 7. an organisation is created --------------------------------------
console.log('\nCreating an organisation from the console:');

const orgMobile = mobile();
const ORG_PIN = '730514';
const orgCreated = await call('POST', '/admin/providers', {
  token: ADMIN,
  body: {
    providerKind: 'organization',
    name: 'Test Console Agency Services',
    contactPerson: 'Meera Joshi',
    mobile: orgMobile,
    email: 'test.console.agency@example.com',
    pin: ORG_PIN,
    hourlyRate: 450,
    gstNumber: '24ABCDE1234F1Z5',
    orgRegistrationUrl: docs['org-registration'],
    allocateViaOrg: true,
    languages: ['English', 'Hindi'],
    address: {
      line1: '2nd Floor, Titanium City Centre, Prahlad Nagar',
      city: 'Ahmedabad',
      state: 'Gujarat',
      pincode: '380015',
      latitude: 23.0121,
      longitude: 72.5085,
    },
    // Deliberately none: an agency covers whatever hours the carer it sends
    // covers, so the server fills in all seven days rather than leaving the
    // agency unmatched by an INNER JOIN.
    workHours: [],
    expertise: ['companion', 'nurse'],
    approvalStatus: 'approved',
  },
});

mark(orgCreated.status === 201, `the organisation is created (got ${orgCreated.status} ${JSON.stringify(orgCreated.json).slice(0, 220)})`);
const org = orgCreated.json?.provider ?? {};
mark(org.provider_kind === 'organization', `stored as an organisation (got ${org.provider_kind})`);
mark(!!org.org_registration_url, 'the registration certificate is attached');
mark(org.gst_number === '24ABCDE1234F1Z5', `the GST number is stored (got ${org.gst_number})`);
mark(org.contact_person === 'Meera Joshi', `somebody to speak to is stored (got ${org.contact_person})`);
mark(org.gender === null, `no gender on a company (got ${org.gender})`);
mark(org.dob === null, `no date of birth on a company (got ${org.dob})`);
mark(org.aadhar_doc_url === null, 'no Aadhaar card on a company');
mark(
  Array.isArray(org.work_hours) && org.work_hours.length === 7,
  `all seven days are filled in so the agency is matchable (got ${org.work_hours?.length})`,
);
mark(org.allocate_via_org === 1 || org.allocate_via_org === true, 'requests route to the agency, not its carers');

const orgSignIn = await call('POST', '/auth/provider/login', {
  body: { mobile: orgMobile, pin: ORG_PIN, deviceId: `qa-org-${Date.now()}` },
});
mark(orgSignIn.status === 200 && !!orgSignIn.json?.token, `the agency signs in too (got ${orgSignIn.status})`);

// ---- 8. the refusals hold ----------------------------------------------
console.log('\nWhat the console refuses to create:');

const base = () => ({
  providerKind: 'freelancer',
  name: 'Test Console Refused',
  gender: 'male',
  mobile: mobile(),
  pin: '418276',
  hourlyRate: 300,
  aadharDocUrl: docs.aadhar,
  policeVerificationUrl: docs['police-verification'],
  policeVerificationValidFrom: daysFromNow(-100),
  policeVerificationValidTo: daysFromNow(300),
  address: { line1: '9 Test Lane, Vastrapur', latitude: 23.03, longitude: 72.53 },
  workHours: [{ dayOfWeek: 'mon', startTime: '09:00', endTime: '18:00' }],
  expertise: ['companion'],
});

const refusals = [
  ['a PIN of six identical digits', { ...base(), pin: '111111' }, 'pin'],
  ['the PIN 123456', { ...base(), pin: '123456' }, 'pin'],
  ['a five-digit PIN', { ...base(), pin: '41827' }, 'pin'],
  ['an address with no coordinates', { ...base(), address: { line1: '9 Test Lane, Vastrapur' } }, 'location'],
  ['a mobile number that is not one', { ...base(), mobile: '12345' }, 'mobile'],
  ['an hourly rate of 5', { ...base(), hourlyRate: 5 }, 'hourlyRate'],
  ['no working day', { ...base(), workHours: [] }, 'workHours'],
  ['a finish time before the start', {
    ...base(), workHours: [{ dayOfWeek: 'mon', startTime: '18:00', endTime: '09:00' }],
  }, 'workHours'],
  ['no service', { ...base(), expertise: [] }, 'expertise'],
  ['no police verification', { ...base(), policeVerificationUrl: null }, 'policeVerificationUrl'],
  ['an expired police verification', {
    ...base(), policeVerificationValidFrom: daysFromNow(-800), policeVerificationValidTo: daysFromNow(-2),
  }, 'policeVerificationDates'],
  ['a nurse with no medical certificate', { ...base(), expertise: ['nurse'] }, 'medicalCertificateUrl'],
  ['a carer aged 12', { ...base(), dob: daysFromNow(-12 * 365) }, 'dob'],
  ['a GST number that is not one', {
    ...base(), providerKind: 'organization', contactPerson: 'Someone', gstNumber: 'NOPE', gender: undefined,
  }, 'gstNumber'],
];

for (const [what, body, field] of refusals) {
  const r = await call('POST', '/admin/providers', { token: ADMIN, body });
  const named = r.json?.error?.fields && Object.keys(r.json.error.fields).includes(field);
  mark(
    r.status === 422 && named,
    `${what} is refused, naming "${field}" (got ${r.status}, fields ${JSON.stringify(Object.keys(r.json?.error?.fields ?? {}))})`,
  );
}

const asEmployee = await call('POST', '/admin/providers', {
  token: ADMIN,
  body: { ...base(), providerKind: 'org_employee' },
});
mark(
  asEmployee.status === 422,
  `an org_employee cannot be created here -- the organisation adds its own carers (got ${asEmployee.status})`,
);

const duplicate = await call('POST', '/admin/providers', {
  token: ADMIN,
  body: { ...base(), mobile: carerMobile },
});
mark(
  duplicate.status === 422 && !!duplicate.json?.error?.fields?.mobile,
  `a mobile number already registered is refused, naming which account has it (got ${duplicate.status})`,
);

const anonymous = await call('POST', '/admin/providers', { body: base() });
mark(anonymous.status === 401, `an unauthenticated caller is refused outright (got ${anonymous.status})`);

// ---- the geocoder the form leans on ------------------------------------
console.log('\nThe address lookup the form uses:');

const geo = await call('GET', '/admin/geocode?q=Satellite%2C%20Ahmedabad%2C%20Gujarat', { token: ADMIN });
mark(geo.status === 200, `the lookup answers (got ${geo.status})`);
if (geo.json?.geocoder === 'stub') {
  console.log('     (MAPS_PROVIDER is stub, so no coordinates are expected -- the form falls back to the map)');
} else {
  mark(
    Number.isFinite(geo.json?.latitude) && Number.isFinite(geo.json?.longitude),
    `and returns coordinates (got ${geo.json?.latitude}, ${geo.json?.longitude})`,
  );
}
const tooShort = await call('GET', '/admin/geocode?q=a', { token: ADMIN });
mark(tooShort.status === 400, `a one-character search is refused rather than sent on (got ${tooShort.status})`);

// ---- the audit trail ----------------------------------------------------
console.log('\nWhat the audit log recorded:');

const audit = await call('GET', '/admin/audit-log?formName=AdminCreateProvider&limit=20', { token: ADMIN });
const creations = audit.json?.auditLog ?? [];
mark(creations.length >= 2, `both creations are in the audit log (found ${creations.length})`);
const meta = creations[0]?.metadata;
const parsed = typeof meta === 'string' ? JSON.parse(meta) : meta;
mark(parsed?.pinSetByAdmin === true, 'the log records that staff set the PIN');
mark(
  !JSON.stringify(parsed ?? {}).includes(ORG_PIN) && !JSON.stringify(parsed ?? {}).includes(CARER_PIN),
  'and does not record the PIN itself',
);

console.log(`\n${failures === 0 ? 'All checks passed.' : `${failures} check(s) failed.`}`);
process.exit(failures === 0 ? 0 : 1);
