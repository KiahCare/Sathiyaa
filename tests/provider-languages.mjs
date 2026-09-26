/**
 * Can a family find a carer who speaks their language?
 *
 * All three pieces looked present:
 *
 *   - the database has had a `languages` JSON column on service_providers
 *     since migration 002
 *   - the matching query filters on it:
 *     `AND JSON_CONTAINS(sp.languages, JSON_QUOTE(?))`
 *   - the customer app has a language dropdown, sends it as `language`, and
 *     prints each carer's languages on the result card and the profile
 *
 * and the provider app never asked. It sent `languages: ['English']`,
 * hardcoded, for every carer who ever registered -- the string appeared in
 * exactly one place in that whole app.
 *
 * So the filter worked perfectly and returned nobody, and every carer's card
 * said "English" whatever they actually spoke. For a product whose customers
 * are elderly people in India, being matched with somebody you cannot talk to
 * is not a small thing.
 *
 * This registers a carer who speaks Gujarati and then searches for one.
 */
const BASE = process.env.SATHIYAA_API ?? process.env.API_BASE ?? 'http://localhost:4000/api/v1';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? 'Admin@123';

let failures = 0;
const mark = (pass, line) => {
  if (!pass) failures++;
  console.log(`${pass ? 'OK  ' : 'FAIL'} ${line}`);
};

const call = async (method, path, { token, body } = {}) => {
  const r = await fetch(BASE + path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await r.text();
  let json;
  try { json = JSON.parse(text); } catch { json = text; }
  return { status: r.status, json };
};

const mobile = () => `98${Date.now().toString().slice(-6)}${Math.floor(Math.random() * 90 + 10)}`;
const ymd = (d) => d.toISOString().slice(0, 10);
const soon = ymd(new Date(Date.now() + 5 * 24 * 3600 * 1000));
const from = ymd(new Date(Date.now() - 365 * 24 * 3600 * 1000));
const to = ymd(new Date(Date.now() + 730 * 24 * 3600 * 1000));

// ---- a freelancer who speaks three languages ----------------------------
console.log('A carer registering:');

const carerMobile = mobile();
const reg = await call('POST', '/auth/provider/register', {
  body: {
    providerKind: 'freelancer',
    name: 'Test Polyglot Carer',
    gender: 'female',
    mobile: carerMobile,
    pin: '731946',
    hourlyRate: 250,
    languages: ['English', 'Hindi', 'Gujarati'],
    aadharDocUrl: '/uploads/aadhar/polyglot.png',
    policeVerificationUrl: '/uploads/police-verification/polyglot.png',
    policeVerificationValidFrom: from,
    policeVerificationValidTo: to,
    addresses: [{ addressType: 'home', line1: '9 Test Lane', city: 'Ahmedabad', latitude: 23.0293, longitude: 72.6176 }],
    workHours: ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'].map((d) => ({
      dayOfWeek: d, startTime: '07:00:00', endTime: '21:00:00',
    })),
    expertise: [{ serviceType: 'companion' }],
  },
});
mark(reg.status === 201, `registered -> ${reg.status} ${reg.status !== 201 ? JSON.stringify(reg.json).slice(0, 180) : ''}`);
const PT = reg.json.token;

const me = await call('GET', '/providers/me', { token: PT });
const mine = me.json.languages;
mark(Array.isArray(mine) && mine.length === 3,
  `three languages stored, not a hardcoded ['English']   got ${JSON.stringify(mine)}`);
mark(Array.isArray(mine) && mine.includes('Gujarati'),
  'including Gujarati, which is the one the carer would actually be picked for');

// ---- and can change them later ------------------------------------------
const changed = await call('PUT', '/providers/me', {
  token: PT,
  body: { languages: ['English', 'Hindi', 'Gujarati', 'Marathi'] },
});
mark(changed.status === 200, `editable from the profile -> ${changed.status}`);
const after = (await call('GET', '/providers/me', { token: PT })).json.languages;
mark(Array.isArray(after) && after.includes('Marathi'),
  `a fourth language saves   got ${JSON.stringify(after)}`);

// ---- approve them, so search can see them -------------------------------
const AT = (await call('POST', '/auth/admin/login', {
  body: { email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD },
})).json.token;
mark(!!AT, 'admin signed in');

const listed = (await call('GET', '/admin/providers?status=all', { token: AT })).json;
const row = (listed.providers ?? []).find((p) => `${p.mobile_number ?? p.mobileNumber}` === carerMobile);
mark(!!row, 'the carer is on the admin list');
mark(row && JSON.stringify(row.languages ?? '').includes('Gujarati'),
  `and the console can see the languages   got ${row && JSON.stringify(row.languages)}`);

if (row) {
  const id = row.provider_id ?? row.providerId;
  const ok = await call('POST', `/admin/providers/${id}/approve`, { token: AT });
  mark(ok.status === 200, `approved -> ${ok.status}`);
}

// ---- a family searching in Gujarati -------------------------------------
console.log('\nA family searching for somebody who speaks their language:');

const search = async (language) => {
  const q = new URLSearchParams({
    service_type: 'companion',
    date_from: soon,
    date_to: soon,
    time_from: '09:00',
    time_to: '13:00',
    latitude: '23.0293',
    longitude: '72.6176',
    radius_km: '50',
  });
  if (language) q.set('language', language);
  const r = await call('GET', `/providers/search?${q}`);
  return r.json.providers ?? r.json.results ?? [];
};

const any = await search(null);
mark(any.length > 0, `searching with no language filter finds ${any.length}`);

const gu = await search('Gujarati');
mark(gu.length > 0,
  `searching for Gujarati finds ${gu.length} — this returned 0 before, for every language except English`);
mark(gu.some((p) => `${p.mobileNumber ?? p.mobile_number ?? ''}` === carerMobile
  || `${p.name}` === 'Test Polyglot Carer'),
  'and our carer is among them');

const shown = gu.find((p) => `${p.name}` === 'Test Polyglot Carer');
mark(shown && Array.isArray(shown.languages) && shown.languages.includes('Gujarati'),
  `the search result carries the languages, so the card can print them   got ${shown && JSON.stringify(shown.languages)}`);

// A language nobody speaks still returns nobody -- the filter is doing work,
// not being ignored.
const none = await search('Odia');
mark(!none.some((p) => `${p.name}` === 'Test Polyglot Carer'),
  'a language this carer does not speak does not match them');

// ---- an organisation's carer --------------------------------------------
//
// The same hole, on the other path: addEmployee never wrote the languages
// column and listEmployees never returned it, so an agency's staff were all
// null -- and JSON_CONTAINS against null matches nothing. An agency could
// add a Tamil-speaking carer and no family searching for Tamil would ever be
// shown them.
console.log('\nA carer an organisation adds:');

const orgMobile = mobile();
const org = await call('POST', '/auth/provider/register', {
  body: {
    providerKind: 'organization',
    name: 'Test Language Agency',
    mobile: orgMobile,
    pin: '558214',
    hourlyRate: 350,
    orgRegistrationUrl: '/uploads/org-registration/lang-agency.png',
    contactPerson: 'Asha Rao',
    languages: ['English', 'Tamil'],
    addresses: [{ addressType: 'home', line1: '3 Office Road', city: 'Ahmedabad', latitude: 23.0293, longitude: 72.6176 }],
    workHours: [{ dayOfWeek: 'mon', startTime: '09:00:00', endTime: '18:00:00' }],
    expertise: [{ serviceType: 'companion' }],
  },
});
mark(org.status === 201, `organisation registered -> ${org.status}`);
const ORG = org.json.token;

const staffMobile = mobile();
const added = await call('POST', '/providers/employees', {
  token: ORG,
  body: {
    name: 'Test Tamil Carer',
    gender: 'female',
    mobile: staffMobile,
    address: { line1: 'Koramangala' },
    languages: ['English', 'Tamil', 'Kannada'],
    aadharDocUrl: '/uploads/aadhar/tamil-carer.png',
    policeVerificationUrl: '/uploads/police-verification/tamil-carer.png',
    policeVerificationValidFrom: from,
    policeVerificationValidTo: to,
  },
});
mark(added.status === 201, `staff added -> ${added.status}`);

const staff = ((await call('GET', '/providers/employees', { token: ORG })).json.employees ?? [])
  .find((e) => `${e.mobileNumber}` === staffMobile);
mark(staff && JSON.stringify(staff.languages ?? '').includes('Tamil'),
  `their languages are stored and read back   got ${staff && JSON.stringify(staff.languages)}`);

// And editing them later sticks.
if (staff) {
  const id = staff.providerId ?? staff.provider_id;
  const edited = await call('PUT', `/providers/employees/${id}`, {
    token: ORG,
    body: { languages: ['English', 'Tamil', 'Kannada', 'Telugu'] },
  });
  mark(edited.status === 200, `editing them -> ${edited.status}`);
  const again = ((await call('GET', '/providers/employees', { token: ORG })).json.employees ?? [])
    .find((e) => `${e.mobileNumber}` === staffMobile);
  mark(again && JSON.stringify(again.languages ?? '').includes('Telugu'),
    `the fourth language saved   got ${again && JSON.stringify(again.languages)}`);
}

console.log('\n' + (failures === 0 ? 'all checks passed' : `${failures} FAILURES`));
process.exit(failures === 0 ? 0 : 1);
