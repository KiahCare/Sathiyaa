// Business-partner sign-in.
//
// A partner is handed four things at sign-up — a partner ID, a referral code,
// a contact number and an email — and remembers whichever they remember, in
// whatever case they happen to type. All four must work, and a wrong password
// must be refused rather than let through.

const BASE = process.env.SATHIYAA_API ?? process.env.API_BASE ?? 'http://localhost:4000/api/v1';

let failures = 0;
const mark = (pass, line) => {
  if (!pass) failures++;
  console.log(`${pass ? 'OK  ' : 'FAIL'} ${line}`);
};

const tryLogin = async (identifier, password, { expectOk = true } = {}) => {
  const r = await fetch(BASE + '/auth/business-agent/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ identifier, password }),
  });
  const t = await r.text();
  let j;
  try { j = JSON.parse(t); } catch { j = t; }

  // When we expect a refusal, 401 is the pass condition — not r.ok. It was 422
  // until an unknown identifier and a wrong password were made one answer: a
  // partner can be looked up by four different things, so two different
  // refusals were four ways to find out who the partners are.
  const pass = expectOk ? r.ok : r.status === 401;
  mark(pass, `${String(r.status).padEnd(4)} identifier=${String(identifier).padEnd(26)} ${
    r.ok ? j.agent.entityName : JSON.stringify(j.error)}`);
  return r.ok ? j.token : null;
};

console.log('every identifier a partner might type:');
for (const id of [
  'BP-000001',               // the partner ID
  '9800000001',              // the contact number
  'APOL1001',                // the referral code
  'vinod.menon@partner.com', // the email on file
  'bp-000001',               // lower case
  'apol1001',
]) {
  await tryLogin(id, 'Partner@123');
}

console.log('\na wrong password must be refused:');
await tryLogin('BP-000001', 'nope', { expectOk: false });

const token = await tryLogin('BP-000001', 'Partner@123');

console.log('\npartner-scoped endpoints:');
for (const path of ['/business-agents/me/referrals', '/business-agents/me/revenue', '/business-agents/me']) {
  const r = await fetch(BASE + path, { headers: { Authorization: `Bearer ${token}` } });
  const t = await r.text();
  mark(r.ok, `${String(r.status).padEnd(4)} ${path.padEnd(34)} ${t.slice(0, 90)}`);
}

// Creating a referral, which is the one thing a partner actually does.
//
// Nothing here ever POSTed one — the checks above only read — and that is
// exactly how the admin console shipped posting snake_case field names at an
// endpoint that reads camelCase. Every field arrived undefined and the form
// answered "customerName is required" with the name plainly filled in. The
// console's mock backend stores the payload object as-is and never minded, so
// the whole thing worked in demo mode and only ever failed against a real API.
console.log('\ncreating a referral:');

const post = async (body) => {
  const r = await fetch(BASE + '/business-agents/me/referrals', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });
  const t = await r.text();
  let j;
  try { j = JSON.parse(t); } catch { j = t; }
  return { status: r.status, ok: r.ok, body: j };
};

// A weekday far enough out that nothing seeded is already booked over it.
const day = new Date();
day.setDate(day.getDate() + 30);
while (day.getDay() === 0) day.setDate(day.getDate() + 1);
const iso = `${day.getFullYear()}-${String(day.getMonth() + 1).padStart(2, '0')}-${String(day.getDate()).padStart(2, '0')}`;

const good = await post({
  customerName: 'Referral Test Customer',
  gender: 'female',
  serviceType: 'companion',
  durationStart: iso,
  durationEnd: iso,
  timeFrom: '09:00',
  timeTo: '17:00',
  mobileNumber: '9352122430',
  address: 'Thaltej, Ahmedabad',
});
mark(good.ok, `${String(good.status).padEnd(4)} camelCase body is accepted   ${
  good.ok ? `referral_code=${good.body.referral_code ?? good.body.referralCode ?? '(none)'}` : JSON.stringify(good.body.error)}`);

// The contract, asserted rather than assumed: requests are camelCase. If this
// ever starts passing, the API has quietly become lenient and the console can
// drift back to sending row-shaped objects without anything noticing.
const bad = await post({
  customer_name: 'Snake Case Customer',
  gender: 'female',
  service_type: 'companion',
  duration_start: iso,
  duration_end: iso,
  time_from: '09:00',
  time_to: '17:00',
  mobile_number: '9352122430',
  address: 'Thaltej, Ahmedabad',
});
mark(bad.status === 400, `${String(bad.status).padEnd(4)} snake_case body is refused   ${
  bad.status === 400 ? JSON.stringify(bad.body.error?.message ?? bad.body.error) : 'expected 400'}`);

console.log('\n' + (failures === 0 ? 'all checks passed' : `${failures} FAILURES`));
process.exit(failures === 0 ? 0 : 1);
process.exit(failures === 0 ? 0 : 1);
