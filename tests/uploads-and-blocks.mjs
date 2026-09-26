// Verifies the two endpoints added this pass:
//   POST /uploads                       (multipart, any signed-in role)
//   GET  /providers/me/calendar-blocks  (list, with optional from/to)
const BASE = process.env.SATHIYAA_API ?? process.env.API_BASE ?? 'http://localhost:4000/api/v1';
// The file server sits at the origin, not under /api/v1 -- derived from BASE
// so pointing the suite at another deployment moves both together.
const ROOT = BASE.replace(/\/api\/v1\/?$/, '');

let pass = 0;
let fail = 0;
function check(label, ok, detail = '') {
  if (ok) { pass += 1; console.log(`PASS  ${label}`); }
  else { fail += 1; console.log(`FAIL  ${label}${detail ? ` — ${detail}` : ''}`); }
}

async function call(method, path, { token, body, base = BASE } = {}) {
  const res = await fetch(base + path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      'X-Device-Id': 'upload-probe',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const text = await res.text();
  let json; try { json = JSON.parse(text); } catch { json = text; }
  return { status: res.status, json };
}

// --- sign in as a customer -------------------------------------------------
const mobile = '95' + String(Math.floor(Math.random() * 90000000) + 10000000);
const reg = await call('POST', '/auth/customer/register', { body: { name: 'Upload Probe', mobile } });
const ver = await call('POST', '/auth/customer/verify-otp', { body: { mobile, otp: reg.json.devOtp } });
const CT = ver.json.token;
check('customer signed in', !!CT);

// --- a real PNG, built byte by byte ---------------------------------------
// 1x1 transparent PNG.
const pngBytes = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  'base64'
);

async function upload({ token, bytes, filename, type, category }) {
  const form = new FormData();
  form.append('file', new Blob([bytes], { type }), filename);
  if (category) form.append('category', category);
  const res = await fetch(`${BASE}/uploads`, {
    method: 'POST',
    headers: { 'X-Device-Id': 'upload-probe', Authorization: `Bearer ${token}` },
    body: form,
  });
  const text = await res.text();
  let json; try { json = JSON.parse(text); } catch { json = text; }
  return { status: res.status, json };
}

// 1. happy path
const up = await upload({ token: CT, bytes: pngBytes, filename: 'me.png', type: 'image/png', category: 'photo' });
check('uploads a photo', up.status === 201 && !!up.json.url, JSON.stringify(up.json).slice(0, 200));
console.log(`        -> ${up.json.url}`);

// 2. the returned URL actually serves the bytes back
//
// `url` is a path relative to the server root, not an absolute address. It was
// absolute until an absolute one turned out to bake in whichever hostname
// happened to answer the request -- behind CloudFront that is the origin
// instance's own name, on a port closed to everyone but CloudFront, so every
// photo uploaded through the deployed app was stored with an address nothing
// could load. Resolving it here is what every client now does for itself.
if (up.json.url) {
  const ROOT = BASE.replace(/\/api\/v\d+\/?$/, '');
  const fetched = await fetch(ROOT + up.json.url);
  const back = Buffer.from(await fetched.arrayBuffer());
  check('the URL serves the same bytes back', fetched.ok && back.equals(pngBytes),
    `status=${fetched.status} bytes=${back.length}/${pngBytes.length}`);
  check('served with nosniff', fetched.headers.get('x-content-type-options') === 'nosniff');
}

// 3. the URL survives being stored on the profile
const saved = await call('PUT', '/customers/me', { token: CT, body: { name: 'Upload Probe', photoUrl: up.json.url } });
check('photo URL stored on the customer', saved.status === 200 && saved.json.photoUrl === up.json.url,
  `got ${saved.json.photoUrl}`);
const me = await call('GET', '/customers/me', { token: CT });
check('photo URL read back from the profile', me.json.photoUrl === up.json.url);

// 4. a PDF as a provider document
const pdfBytes = Buffer.from('%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF\n', 'utf8');
const doc = await upload({ token: CT, bytes: pdfBytes, filename: 'police.pdf', type: 'application/pdf', category: 'police-verification' });
check('uploads a PDF document', doc.status === 201 && doc.json.path.startsWith('/uploads/police-verification/'),
  JSON.stringify(doc.json).slice(0, 160));

// 5. rejections
const badType = await upload({ token: CT, bytes: Buffer.from('#!/bin/sh\necho hi\n'), filename: 'x.sh', type: 'application/x-sh', category: 'photo' });
check('refuses an unsupported type', badType.status === 422 && badType.json.error?.code === 'UNSUPPORTED_TYPE',
  JSON.stringify(badType.json).slice(0, 160));

const badCategory = await upload({ token: CT, bytes: pngBytes, filename: 'me.png', type: 'image/png', category: 'not-a-category' });
check('refuses an unknown category', badCategory.status === 400, JSON.stringify(badCategory.json).slice(0, 160));

const tooBig = await upload({ token: CT, bytes: Buffer.alloc(9 * 1024 * 1024, 1), filename: 'big.png', type: 'image/png', category: 'photo' });
check('refuses a file over the size limit', tooBig.status === 422 && tooBig.json.error?.code === 'LIMIT_FILE_SIZE',
  JSON.stringify(tooBig.json).slice(0, 160));

const noAuth = await fetch(`${BASE}/uploads`, { method: 'POST', body: new FormData() });
check('refuses an anonymous upload', noAuth.status === 401);

// --- calendar blocks -------------------------------------------------------
const pmobile = '96' + String(Math.floor(Math.random() * 90000000) + 10000000);
const preg = await call('POST', '/auth/provider/register', {
  body: {
    providerKind: 'freelancer', name: 'Block Probe', gender: 'female', mobile: pmobile,
    pin: '135790', hourlyRate: 200, deviceId: 'upload-probe',
    addresses: [{ addressType: 'home', line1: '1 Probe Rd', city: 'Ahmedabad', latitude: 23.0209, longitude: 72.5668 }],
    workHours: [{ dayOfWeek: 'mon', startTime: '09:00:00', endTime: '18:00:00' }],
    expertise: [{ serviceType: 'companion' }],
  },
});
const PT = preg.json.token;
check('provider registered', !!PT, JSON.stringify(preg.json).slice(0, 200));

const empty = await call('GET', '/providers/me/calendar-blocks', { token: PT });
check('lists calendar blocks (empty to start)', empty.status === 200 && Array.isArray(empty.json.calendarBlocks) && empty.json.calendarBlocks.length === 0,
  JSON.stringify(empty.json).slice(0, 160));

const created = await call('POST', '/providers/me/calendar-blocks', {
  token: PT,
  body: { blockStart: '2027-03-01 00:00:00', blockEnd: '2027-03-05 23:59:59', reason: 'Holiday' },
});
check('creates a block and echoes it back', created.status === 201 && !!created.json.id && created.json.reason === 'Holiday',
  JSON.stringify(created.json).slice(0, 160));

const listed = await call('GET', '/providers/me/calendar-blocks', { token: PT });
const block = (listed.json.calendarBlocks || [])[0];
check('the created block is listed', !!block && String(block.id) === String(created.json.id));
check('the listed block carries its dates and reason', !!block && !!block.blockStart && block.reason === 'Holiday',
  JSON.stringify(block).slice(0, 160));

const windowed = await call('GET', '/providers/me/calendar-blocks?from=2027-01-01&to=2027-01-31', { token: PT });
check('a date window excludes blocks outside it', (windowed.json.calendarBlocks || []).length === 0,
  JSON.stringify(windowed.json).slice(0, 160));

const covering = await call('GET', '/providers/me/calendar-blocks?from=2027-02-01&to=2027-04-01', { token: PT });
check('a date window includes blocks inside it', (covering.json.calendarBlocks || []).length === 1);

await call('DELETE', `/providers/me/calendar-blocks/${created.json.id}`, { token: PT });
const afterDelete = await call('GET', '/providers/me/calendar-blocks', { token: PT });
check('a deleted block is gone from the list', (afterDelete.json.calendarBlocks || []).length === 0);

// Another provider must not see it.
const otherMobile = '96' + String(Math.floor(Math.random() * 90000000) + 10000000);
const other = await call('POST', '/auth/provider/register', {
  body: {
    providerKind: 'freelancer', name: 'Other Probe', gender: 'male', mobile: otherMobile,
    pin: '112233', hourlyRate: 200, deviceId: 'upload-probe-2',
    addresses: [{ addressType: 'home', line1: '2 Probe Rd', city: 'Ahmedabad', latitude: 23.0209, longitude: 72.5668 }],
    workHours: [{ dayOfWeek: 'mon', startTime: '09:00:00', endTime: '18:00:00' }],
    expertise: [{ serviceType: 'companion' }],
  },
});
await call('POST', '/providers/me/calendar-blocks', {
  token: PT, body: { blockStart: '2027-05-01 00:00:00', blockEnd: '2027-05-02 23:59:59', reason: 'Mine' },
});
const otherList = await call('GET', '/providers/me/calendar-blocks', { token: other.json.token });
check('blocks are scoped to their own provider', (otherList.json.calendarBlocks || []).length === 0,
  JSON.stringify(otherList.json).slice(0, 160));

console.log(`\n=== ${pass}/${pass + fail} passed ===`);
if (fail) process.exit(1);
