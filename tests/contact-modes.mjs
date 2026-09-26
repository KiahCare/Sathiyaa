const BASE = process.env.SATHIYAA_API ?? process.env.API_BASE ?? 'http://localhost:4000/api/v1';
const mobile = `97${Math.floor(Math.random() * 90000000) + 10000000}`;
const reg = await (await fetch(BASE + '/auth/customer/register', {
  method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Device-Id': 'cm' },
  body: JSON.stringify({ name: 'Contact Mode Tester', mobile }),
})).json();
const ver = await (await fetch(BASE + '/auth/customer/verify-otp', {
  method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Device-Id': 'cm' },
  body: JSON.stringify({ mobile, otp: reg.devOtp }),
})).json();
const T = ver.token;

// expectOk = false means a 422 is the pass condition: the last case sends a
// mode that does not exist and the server must refuse it. Reporting that as
// FAIL made a working guard look like a broken endpoint.
const put = async (mode, expectOk = true) => {
  const r = await fetch(BASE + '/customers/me', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${T}`, 'X-Device-Id': 'cm' },
    body: JSON.stringify({ preferredCommMode: mode, preferredCommTimeframe: '09:00-18:00' }),
  });
  const t = await r.text();
  let j; try { j = JSON.parse(t); } catch { j = t; }
  const back = j.preferredCommMode ?? JSON.stringify(j).slice(0, 90);
  const pass = expectOk ? r.ok : (r.status === 422);
  console.log(`${pass ? 'OK  ' : 'FAIL'} ${String(r.status).padEnd(4)} sent "${String(mode).padEnd(18)}"  ${expectOk ? 'stored' : 'refused'}: ${back}`);
  return pass;
};

// put() has always returned its verdict; nothing ever read it, so a printed
// FAIL still left the exit code at zero.
let bad = 0;
for (const m of ['call', 'email', 'sms', 'email,call', 'call,sms', 'email,call,sms', '']) {
  if (!(await put(m))) bad += 1;
}
console.log('\nan unknown mode must be refused, not stored:');
if (!(await put('email,carrier-pigeon', false))) bad += 1;

console.log(bad
  ? `\n${bad} contact-mode case(s) failed`
  : '\nall 8 contact-mode cases passed');
if (bad || !T) process.exitCode = 1;
