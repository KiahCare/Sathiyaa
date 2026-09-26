/**
 * Four things that looked finished and were not.
 *
 * 1. THE SERVICE AREA. Sathiyaa launches in Ahmedabad and nothing said so.
 *    Anybody anywhere could register, search, find nobody, and reasonably
 *    conclude the app was broken -- and the fact that they had tried was
 *    lost, which is the single most useful number a business opening one
 *    city at a time can have.
 *
 * 2. THE FEE AT ZERO. The annual fee is set in the admin console. Setting it
 *    to 0 sent a zero-rupee order to the gateway, which refuses anything
 *    under a rupee -- so free was the one price the product could not charge.
 *
 * 3. THE REFERENCE CODE. The app checked the code was at least four
 *    characters long, showed a green "verified" tick, and kept it in memory.
 *    A typo passed, the partner's name could not be shown, and closing the
 *    app threw the code away -- so the booking weeks later carried no code
 *    and the partner who introduced the customer earned nothing.
 *
 * 4. A CARER AN ORGANISATION ADDS. Approved outright as soon as two document
 *    URLs were non-empty. Nobody at Sathiyaa had looked at them, and
 *    "verified" is what a family is shown.
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

// Every account below is named 'Test ...' on purpose: cleanup-test-rows.mjs
// matches ^Test and sweeps them, so running this against the live server
// does not leave the directory full of rows somebody has to recognise and
// delete by hand.
const mobile = () => `96${Date.now().toString().slice(-6)}${Math.floor(Math.random() * 90 + 10)}`;
const ymd = (d) => d.toISOString().slice(0, 10);

// Ahmedabad, and two places that are not.
const AHMEDABAD = { latitude: 23.0225, longitude: 72.5714, city: 'Ahmedabad', state: 'Gujarat' };
const GANDHINAGAR = { latitude: 23.2156, longitude: 72.6369, city: 'Gandhinagar', state: 'Gujarat' };
const RAJKOT = { latitude: 22.3039, longitude: 70.8022, city: 'Rajkot', state: 'Gujarat' };

// ---------------------------------------------------------------- 1. area
console.log('\nWhere Sathiyaa says it operates:');

const area = await call('GET', '/public/service-area');
mark(area.status === 200, `the apps can read it without signing in -> ${area.status}`);
mark(!!area.json?.city, `it names a city -> ${area.json?.city}`);
mark(Number(area.json?.radiusKm) > 0, `and a radius -> ${area.json?.radiusKm} km`);

const registerCustomer = async (name) => {
  const m = mobile();
  const reg = await call('POST', '/auth/customer/register', { body: { name, mobile: m } });
  const otp = reg.json?.otp ?? reg.json?.devOtp;
  const v = await call('POST', '/auth/customer/verify-otp', { body: { mobile: m, otp } });
  return { mobile: m, token: v.json?.token, id: v.json?.customerId };
};

console.log('\nA family registering from each of three places:');

const inside = await registerCustomer('Test Area Inside');
mark(!!inside.token, 'somebody in Ahmedabad can register at all');
const insideVerdict = await call('PUT', '/customers/me/signup-place', {
  token: inside.token, body: AHMEDABAD,
});
mark(insideVerdict.json?.inServiceArea === true, 'Ahmedabad is inside');

const near = await registerCustomer('Test Area Near');
const nearVerdict = await call('PUT', '/customers/me/signup-place', {
  token: near.token, body: GANDHINAGAR,
});
mark(nearVerdict.json?.inServiceArea === true,
  'Gandhinagar is inside too -- 30 km out, and a carer drives it');

const far = await registerCustomer('Test Area Far');
const farVerdict = await call('PUT', '/customers/me/signup-place', {
  token: far.token, body: RAJKOT,
});
mark(farVerdict.json?.inServiceArea === false, 'Rajkot is outside');
mark(farVerdict.json?.serviceArea?.city === area.json?.city,
  'and the reply names the city we ARE in, so the app can say so');

const farMe = await call('GET', '/customers/me', { token: far.token });
mark(farMe.json?.signupInServiceArea === false,
  'the verdict is on their row, so the app does not re-ask on every launch');
mark(farMe.json?.signupCity === 'Rajkot', 'along with where they were');

// A phone that refuses location tells us nothing -- and must not be locked
// out for it. Being turned away because a permission dialog was dismissed is
// a customer lost for good; being let in and finding nobody is a bad evening.
const silent = await registerCustomer('Test Area Silent');
const silentVerdict = await call('PUT', '/customers/me/signup-place', {
  token: silent.token, body: {},
});
mark(silentVerdict.json?.inServiceArea === true,
  'no location at all fails open rather than locking somebody out');

// ---------------------------------------------------------- 2. the fee at 0
console.log('\nThe annual fee, set to zero in the console:');

const admin = await call('POST', '/auth/admin/login', {
  body: { email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD },
});
const adminToken = admin.json?.token;
mark(!!adminToken, 'an admin can sign in');

const configBefore = await call('GET', '/admin/config', { token: adminToken });
const feeBefore = Number(
  (configBefore.json?.config ?? []).find((r) => r.config_key === 'customer_annual_fee_new')?.config_value ?? 499
);

const toZero = await call('PUT', '/admin/config', {
  token: adminToken, body: { config: { customer_annual_fee_new: 0 } },
});
mark(toZero.status === 200, `the console accepts 0 as a fee -> ${toZero.status}`);

const freeCustomer = await registerCustomer('Test Fee Waived');
const meFree = await call('GET', '/customers/me', { token: freeCustomer.token });
mark(Number(meFree.json?.registrationFeeAmount) === 0,
  'the app is told the fee is 0, so it shows no payment screen');

const pay = await call('POST', '/customers/me/registration-payment', { token: freeCustomer.token, body: {} });
mark(pay.status === 200, `paying nothing succeeds -> ${pay.status}`);
mark(pay.json?.waived === true, 'and is recorded as waived rather than charged');
mark(Number(pay.json?.amount) === 0, 'for zero rupees');

const meAfter = await call('GET', '/customers/me', { token: freeCustomer.token });
mark(meAfter.json?.registrationFeePaid === true, 'the account is active');
mark(meAfter.json?.status === 'active', 'and out of pending_payment');

// Put it back, whatever it was, so the rest of the suite sees the same world.
await call('PUT', '/admin/config', {
  token: adminToken, body: { config: { customer_annual_fee_new: feeBefore } },
});
const restored = await call('GET', '/admin/config', { token: adminToken });
mark(
  Number((restored.json?.config ?? []).find((r) => r.config_key === 'customer_annual_fee_new')?.config_value) === feeBefore,
  `the fee is back at ${feeBefore}`
);

// Saving a fee must not disturb the service area. Both live in the same
// table, and the console used to send every key it had read back through
// Number() -- which would have written "NaN" over the city.
const areaAfterFeeSave = await call('GET', '/public/service-area');
mark(areaAfterFeeSave.json?.city === area.json?.city,
  'saving a fee left the service area alone');

// --------------------------------------------------------- 3. the referral
console.log('\nThe business partner reference code:');

const partnerName = `Test Partner ${Date.now().toString().slice(-5)}`;
const partner = await call('POST', '/admin/business-agents', {
  token: adminToken,
  body: {
    entityName: partnerName,
    partnerName: 'Test Contact',
    contactNumber1: mobile(),
    password: 'Partner@123',
  },
});
const code = partner.json?.referralCode;
mark(!!code, `a partner has a code -> ${code}`);

const referred = await registerCustomer('Test Referral Customer');

const bad = await call('POST', '/customers/me/referral', {
  token: referred.token, body: { code: 'NOTACODE' },
});
mark(bad.status === 400, `a made-up code is refused -> ${bad.status}`);
mark(/not one of ours/i.test(bad.json?.error?.message ?? ''),
  'with a sentence somebody can act on');

const good = await call('POST', '/customers/me/referral', {
  token: referred.token, body: { code } });
mark(good.status === 200, `a real code is accepted -> ${good.status}`);
mark(good.json?.partnerName === partnerName,
  "and comes back with the partner's own name, which proves it was checked");

const referredMe = await call('GET', '/customers/me', { token: referred.token });
mark(referredMe.json?.referralCode === code,
  'it is on the customer row, so closing the app does not throw it away');

// Lower case, because nobody types a code in capitals.
const cleared = await call('DELETE', '/customers/me/referral', { token: referred.token });
mark(cleared.status === 200, 'it can be removed again');
const lower = await call('POST', '/customers/me/referral', {
  token: referred.token, body: { code: String(code).toLowerCase() },
});
mark(lower.status === 200, 'and typing it in lower case still works');

// ------------------------------------------------- 4. an organisation's carer
console.log("\nA carer an organisation adds:");

const orgMobile = mobile();
const org = await call('POST', '/auth/provider/register', {
  body: {
    providerKind: 'organization',
    name: 'Test Area Agency',
    mobile: orgMobile,
    pin: '482915',
    // Registration takes an ARRAY -- a singular `address` is silently
    // ignored, which leaves the provider with no coordinates and outside
    // every radius search there is.
    addresses: [{ addressType: 'home', line1: 'Navrangpura, Ahmedabad', city: 'Ahmedabad', latitude: 23.0376, longitude: 72.5601 }],
    expertise: [{ serviceType: 'companion' }],
    hourlyRate: 260,
  },
});
const orgToken = org.json?.token;
mark(!!orgToken, 'an organisation can register');

// Approve the organisation itself, which is the condition that used to make
// its carers approved as well.
const orgId = org.json?.provider?.providerId ?? org.json?.providerId;
const approveOrg = await call('POST', `/admin/providers/${orgId}/approve`, {
  token: adminToken, body: { notes: 'test' },
});
mark(approveOrg.status === 200, 'and be approved');

const inDate = ymd(new Date(Date.now() + 365 * 24 * 3600 * 1000));
const carer = await call('POST', '/providers/employees', {
  token: orgToken,
  body: {
    name: 'Test Area Carer',
    mobile: mobile(),
    gender: 'female',
    address: { line1: 'Maninagar, Ahmedabad', latitude: 22.9967, longitude: 72.6047 },
    languages: ['English', 'Gujarati'],
    expertise: [{ serviceType: 'companion' }],
    workHours: [
      { dayOfWeek: 'mon', startTime: '09:00', endTime: '18:00' },
      { dayOfWeek: 'tue', startTime: '10:00', endTime: '16:00' },
    ],
    aadharDocUrl: '/uploads/aadhar/test.jpg',
    policeVerificationUrl: '/uploads/police-verification/test.jpg',
    policeVerificationValidFrom: ymd(new Date(Date.now() - 30 * 24 * 3600 * 1000)),
    policeVerificationValidTo: inDate,
  },
});
mark(carer.status === 201, `the carer is created -> ${carer.status}`);
mark(carer.json?.approvalStatus === 'pending',
  'and is PENDING, not approved -- every document present is not the same as '
  + 'somebody at Sathiyaa having looked at them');

const staff = await call('GET', '/providers/employees', { token: orgToken });
const listed = (staff.json?.employees ?? []).find((e) => e.name === 'Test Area Carer');
mark(!!listed, 'they are on the staff list');
mark(listed?.approvalStatus === 'pending', 'still pending on the list the org reads');
mark(listed?.documentsComplete === true,
  'with documentsComplete separate, so the org knows the wait is ours not theirs');
mark(Array.isArray(listed?.workHours) && listed.workHours.length === 2,
  'and their days and hours come back -- the app sent these and never got them '
  + 'back, so editing a carer wrote an empty week over them');
const mon = (listed?.workHours ?? []).find((w) => w.dayOfWeek === 'mon');
mark(mon?.startTime === '09:00' && mon?.endTime === '18:00', 'with the times as entered');

// Uploading documents must not promote them either.
const edited = await call('PUT', `/providers/employees/${listed?.providerId}`, {
  token: orgToken, body: { languages: ['English', 'Gujarati', 'Hindi'] },
});
mark(edited.status === 200, `editing them succeeds -> ${edited.status}`);
mark(edited.json?.approvalStatus === 'pending',
  'and still does not approve them behind an administrator');

// The console is where it happens.
const approveCarer = await call('POST', `/admin/providers/${listed?.providerId}/approve`, {
  token: adminToken, body: { notes: 'checked' },
});
mark(approveCarer.status === 200, 'an admin can approve them');
const afterApproval = await call('GET', '/providers/employees', { token: orgToken });
const nowVerified = (afterApproval.json?.employees ?? []).find((e) => e.providerId === listed?.providerId);
mark(nowVerified?.approvalStatus === 'approved', 'and only then are they verified');

// An organisation that named no days must still be findable.
//
// An agency is surfaced on the strength of the carers it can send, and the
// work-hours the search looks at are each CARER's -- so the organisation's
// own blank answer must not matter. This registers one with no days at all,
// gives it a verified carer, and then looks for it the way a family would.
const noDaysMobile = mobile();
const noDays = await call('POST', '/auth/provider/register', {
  body: {
    providerKind: 'organization',
    name: 'Test Area Agency No Days',
    mobile: noDaysMobile,
    pin: '553311',
    addresses: [{ addressType: 'home', line1: 'Paldi, Ahmedabad', city: 'Ahmedabad', latitude: 23.0126, longitude: 72.5600 }],
    expertise: [{ serviceType: 'companion' }],
    hourlyRate: 240,
    // No workHours at all, which is what the form now allows.
  },
});
mark(noDays.status === 201, `an organisation can register with no days -> ${noDays.status}`);
const noDaysId = noDays.json?.provider?.providerId ?? noDays.json?.providerId;
await call('POST', `/admin/providers/${noDaysId}/approve`, { token: adminToken, body: {} });
await call('PUT', '/providers/me', { token: noDays.json?.token, body: { allocateViaOrg: true } });

// A carer, because an agency with nobody to send is not bookable and should
// not be -- especially now that carers start pending until Sathiyaa checks
// them.
const noDaysCarer = await call('POST', '/providers/employees', {
  token: noDays.json?.token,
  body: {
    name: 'Test Area Carer Two',
    mobile: mobile(),
    gender: 'female',
    address: { line1: 'Paldi, Ahmedabad', latitude: 23.0126, longitude: 72.5600 },
    expertise: [{ serviceType: 'companion' }],
    workHours: ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']
      .map((day) => ({ dayOfWeek: day, startTime: '00:00', endTime: '23:59' })),
    aadharDocUrl: '/uploads/aadhar/test.jpg',
    policeVerificationUrl: '/uploads/police-verification/test.jpg',
    policeVerificationValidTo: inDate,
  },
});
await call('POST', `/admin/providers/${noDaysCarer.json?.providerId}/approve`, {
  token: adminToken, body: {},
});
// A weekday, because the seeded roster works weekdays and a Sunday would
// legitimately match nobody.
const nextWeekday = (() => {
  const d = new Date(Date.now() + 3 * 24 * 3600 * 1000);
  while (d.getDay() === 0 || d.getDay() === 6) d.setDate(d.getDate() + 1);
  return ymd(d);
})();
const searchable = await call('GET',
  `/providers/search?service_type=companion&date_from=${nextWeekday}`
  + '&time_from=10:00:00&time_to=12:00:00&lat=23.0225&lng=72.5714&radius_km=25',
  { token: inside.token });
const found = (searchable.json?.providers ?? []).some(
  (p) => Number(p.providerId ?? p.provider_id) === Number(noDaysId));
mark(found, "and is still findable -- what the search reads is its carers' hours, not its own");

// And exactly once. An organisation used to come back from both halves of
// the matching query, and the booking then wrote two booking_requests rows
// with the same (booking_id, provider_id) -- a unique key -- so every booking
// in range of that agency failed with "Record already exists".
const timesListed = (searchable.json?.providers ?? []).filter(
  (p) => Number(p.providerId ?? p.provider_id) === Number(noDaysId)).length;
mark(timesListed === 1, `and listed exactly once   got ${timesListed}`);

const bookable = await call('POST', '/bookings', {
  token: inside.token,
  body: {
    serviceType: 'companion', startDate: nextWeekday, endDate: nextWeekday,
    timeFrom: '10:00:00', timeTo: '12:00:00', latitude: 23.0225, longitude: 72.5714,
  },
});
mark(bookable.status === 201,
  `and a booking that reaches it succeeds -> ${bookable.status} `
  + `${bookable.status === 201 ? '' : JSON.stringify(bookable.json)}`);

// ------------------------------------------------- 5. the demand report
console.log('\nWhat the console can see about demand:');

const places = await call('GET', '/admin/reports/signup-places', { token: adminToken });
mark(places.status === 200, `the report loads -> ${places.status}`);
const rajkot = (places.json?.places ?? []).find((p) => p.city === 'Rajkot');
mark(!!rajkot, 'Rajkot is in it, although Sathiyaa does not serve Rajkot');
mark((rajkot?.customers ?? 0) >= 1, 'counted as a family who asked');
mark(rajkot?.customersInside === 0, 'and marked as outside the area');
const ahmedabad = (places.json?.places ?? []).find((p) => p.city === 'Ahmedabad');
mark((ahmedabad?.customersInside ?? 0) >= 1, 'Ahmedabad is counted as served');

console.log(`\n${failures === 0 ? 'All checks passed.' : `${failures} check(s) failed.`}`);
process.exit(failures === 0 ? 0 : 1);
