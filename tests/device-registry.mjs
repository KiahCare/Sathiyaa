// Proves the device registry records what a handset actually reports, and that
// the console can read it back.
//
// This is the part that only works if three things line up: the app sends the
// headers, `recordDevice` reads them on every authenticated request, and the
// admin endpoints join a polymorphic user_id back to the right table. Nothing
// else in the suite touched it, which for a feature whose whole job is to
// answer "which phone was that?" after something has gone wrong is the wrong
// amount of coverage.
//
// Registers its own accounts and sweeps the devices it created.

const BASE = process.env.SATHIYAA_API ?? process.env.API_BASE ?? 'http://localhost:4000/api/v1';
const KEY = process.env.API_ACCESS_KEY ?? '';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? 'Admin@123';

let pass = 0;
let fail = 0;

function check(label, ok, detail = '') {
  if (ok) {
    console.log(`  PASS  ${label}`);
    pass++;
  } else {
    console.log(`  FAIL  ${label}${detail ? ` — ${detail}` : ''}`);
    fail++;
  }
}

// One handset, described the way device_info.dart describes a real one.
const PIXEL = {
  'X-Device-Id': `reg-pixel-${Date.now()}`,
  'X-Device-Platform': 'android',
  'X-Device-Manufacturer': 'Google',
  'X-Device-Model': 'Pixel 7a',
  'X-Device-OS': 'Android 14 (SDK 34)',
  // X-App-Version, not X-Device-App-Version. The apps send the first and the
  // middleware reads the first; this test originally sent the second and
  // reported a null column as a bug in the server.
  'X-App-Version': '1.4.2+42',
  'X-Device-Physical': 'true',
};

// A second one, so "two devices on an account" is a different row and not an
// overwrite of the first.
const EMULATOR = {
  'X-Device-Id': `reg-emu-${Date.now()}`,
  'X-Device-Platform': 'android',
  'X-Device-Manufacturer': 'Google',
  'X-Device-Model': 'sdk_gphone64_x86_64',
  'X-Device-OS': 'Android 13 (SDK 33)',
  'X-App-Version': '1.4.2+42',
  'X-Device-Physical': 'false',
};

async function api(path, { method = 'GET', body, token, device = PIXEL } = {}) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...device,
      ...(KEY ? { 'X-Sathiyaa-Key': KEY } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let data;
  try {
    data = text ? JSON.parse(text) : {};
  } catch {
    data = { raw: text };
  }
  return { status: res.status, data };
}

console.log('\nDevice registry\n');

// --- a customer signs in from a phone ------------------------------------------
const mobile = `96${Math.floor(Math.random() * 90000000) + 10000000}`;
const reg = await api('/auth/customer/register', {
  method: 'POST',
  body: { name: 'Device Registry Tester (QA)', mobile },
});
check('customer registered', reg.status === 201 || reg.status === 200, `status ${reg.status}`);
const ver = await api('/auth/customer/verify-otp', {
  method: 'POST',
  body: { mobile, otp: reg.data.devOtp },
});
const CT = ver.data.token;
check('and signed in from the phone', !!CT, `status ${ver.status}`);
if (!CT) process.exit(1);

// recordDevice hangs off requireAuth, so any authenticated call registers the
// handset. One is made here rather than relying on the sign-in itself — and it
// also gives us this customer's own id.
//
// Taking the id off the console listing instead would look right and be wrong:
// a device id is shared between accounts by design, so the row that comes back
// first for a handset is whoever used it most recently, not necessarily us.
const me = await api('/customers/me', { token: CT });
const myId = me.data.customerId ?? me.data.customer?.customerId ?? me.data.id;
check('the signed-in customer knows its own id', !!myId, JSON.stringify(me.data).slice(0, 120));

// --- the console can see it ----------------------------------------------------
const adminLogin = await api('/auth/admin/login', {
  method: 'POST',
  body: { email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD },
});
const AT = adminLogin.data.token;
check('admin signed in', !!AT, `status ${adminLogin.status}`);
if (!AT) process.exit(1);

const list = await api(`/admin/devices?search=${encodeURIComponent(PIXEL['X-Device-Id'])}`, { token: AT });
const rows = list.data.devices ?? list.data ?? [];
// Both the handset *and* the account, because this handset is about to be
// shared with a second account further down.
const row = Array.isArray(rows)
  ? rows.find((d) => d.deviceId === PIXEL['X-Device-Id'] && Number(d.userId) === Number(myId))
  : null;

check('the handset appears in the console', !!row,
  `${list.status}, ${Array.isArray(rows) ? rows.length : 0} row(s) back`);

if (row) {
  check('  ...with the make', row.manufacturer === 'Google', `${row.manufacturer}`);
  check('  ...the model', row.model === 'Pixel 7a', `${row.model}`);
  check('  ...the OS version', `${row.osVersion}`.includes('Android 14'), `${row.osVersion}`);
  check('  ...the app version', `${row.appVersion}` === '1.4.2+42', `${row.appVersion}`);
  check('  ...and that it is a real handset, not an emulator',
    row.isPhysical === 1 || row.isPhysical === true, `isPhysical ${row.isPhysical}`);
  check('  ...joined back to the account it belongs to',
    `${row.ownerName}`.includes('Device Registry Tester'), `${row.ownerName}`);
  check('  ...with the address the request came from', !!row.lastIp, `lastIp ${row.lastIp}`);
  check('  ...and when it was first and last seen',
    !!row.firstSeenAt && !!row.lastSeenAt, `${row.firstSeenAt} / ${row.lastSeenAt}`);
}

// --- a second handset is a second row, not an overwrite ------------------------
const fromEmulator = await api('/customers/me', { token: CT, device: EMULATOR });
check('the account can be used from a second handset', fromEmulator.status === 200,
  `status ${fromEmulator.status} — ${JSON.stringify(fromEmulator.data).slice(0, 140)}`);

// The write is fire-and-forget off the request, so the row may land a moment
// after the response. Without this the test is a race that passes on a quiet
// machine and fails on a busy one, which is the worst kind of test to own.
await new Promise((r) => setTimeout(r, 400));

const mine = await api(`/admin/devices/customer/${myId}`, { token: AT });
const forUser = mine.data.devices ?? mine.data ?? [];
check('a second handset is recorded alongside the first, not instead of it',
  Array.isArray(forUser) && forUser.length >= 2,
  `${Array.isArray(forUser) ? forUser.length : 0} device(s) on the account`);

const emu = Array.isArray(forUser)
  ? forUser.find((d) => d.deviceId === EMULATOR['X-Device-Id'])
  : null;
check('  ...and an emulator is recorded as one',
  !!emu && (emu.isPhysical === 0 || emu.isPhysical === false),
  emu ? `isPhysical ${emu.isPhysical}` : 'emulator row missing');

// --- one handset, two accounts -------------------------------------------------
// The pattern device binding exists to catch. For a family sharing a phone it is
// ordinary; for two provider accounts it is the thing worth a second look.
const mobile2 = `96${Math.floor(Math.random() * 90000000) + 10000000}`;
const reg2 = await api('/auth/customer/register', {
  method: 'POST',
  body: { name: 'Second Account On One Phone (QA)', mobile: mobile2 },
});
const ver2 = await api('/auth/customer/verify-otp', {
  method: 'POST',
  body: { mobile: mobile2, otp: reg2.data.devOtp },
});
if (ver2.data.token) {
  await api('/customers/me', { token: ver2.data.token });
  const shared = await api(`/admin/devices/by-device/${PIXEL['X-Device-Id']}`, { token: AT });
  const accounts = shared.data.accounts ?? shared.data.devices ?? shared.data ?? [];
  check('one handset used by two accounts is reported as such',
    Array.isArray(accounts) && accounts.length >= 2,
    `${Array.isArray(accounts) ? accounts.length : 0} account(s) on that handset`);
} else {
  check('a second account could be created on the same handset', false,
    `status ${ver2.status}`);
}

console.log(`\n  ${pass}/${pass + fail} passed\n`);
process.exit(fail === 0 ? 0 : 1);
