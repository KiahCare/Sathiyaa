/**
 * The AWS configuration, proved on this machine before it is proved in anger.
 *
 * Every other script here runs against a laptop backend: no access key, no CORS
 * list, no rate limiting, a placeholder JWT secret. None of that is how the
 * server will be configured once it is on the internet, so none of those
 * scripts say anything about whether the deployed configuration works.
 *
 * This one runs against a backend started exactly the way the deployed one will
 * be — PUBLIC_DEPLOYMENT on, a real key, a real secret, an origin allow-list,
 * a rotated admin password — and checks the things that only go wrong in that
 * configuration. Run it with:
 *
 *     _tests\run-all.ps1 -Public
 *
 * which starts that server for it and throws it away afterwards.
 */
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const BASE = process.env.SATHIYAA_API ?? 'http://localhost:4010/api/v1';
const ROOT = BASE.replace(/\/api\/v1\/?$/, '');
const KEY = process.env.SATHIYAA_PUBLIC_KEY ?? '';
const ORIGIN = process.env.SATHIYAA_CORS_ORIGIN ?? '';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? '';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const BACKEND = path.resolve(
  HERE, '..', 'sathiyaa-full-project - Flutter Web version', 'backend'
);

let pass = 0;
const failures = [];
function ok(label, condition, detail = '') {
  if (condition) {
    pass += 1;
    console.log(`PASS  ${label}`);
  } else {
    failures.push(label);
    console.log(`FAIL  ${label}`);
    if (detail) console.log(`        ${detail}`);
  }
}

if (!KEY || !ORIGIN || !ADMIN_PASSWORD) {
  console.log('This script needs SATHIYAA_PUBLIC_KEY, SATHIYAA_CORS_ORIGIN and');
  console.log('ADMIN_PASSWORD, and a backend started with that configuration.');
  console.log('Run it through:  _tests\\run-all.ps1 -Public');
  process.exit(1);
}

// Built by hand rather than through the wrapped fetch in lib/preamble.mjs,
// because half of what is being checked here is what happens when the key is
// wrong or missing.
async function call(pathname, { key, origin, method = 'GET', body } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (key !== undefined) headers['X-Sathiyaa-Key'] = key;
  if (origin) headers.Origin = origin;
  const res = await fetch(pathname.startsWith('http') ? pathname : BASE + pathname, {
    method,
    headers,
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = text; }
  return { status: res.status, headers: res.headers, json };
}

const message = (r) => r.json?.error?.message ?? JSON.stringify(r.json).slice(0, 120);

// ===================================================== 1. the door is on
console.log('\n--- the shared key ---');

const health = await call(`${ROOT}/health`);
ok('a load balancer can check health with no key at all', health.status === 200,
  `got ${health.status}`);

const noKey = await call('/auth/admin/login', {
  method: 'POST', body: { email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD },
});
ok('no key is refused', noKey.status === 401, `got ${noKey.status}`);
ok('...and says which of the two things is wrong',
  /access key/i.test(message(noKey)), message(noKey));

const wrongSameLength = await call('/auth/admin/login', {
  key: 'x'.repeat(KEY.length),
  method: 'POST', body: { email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD },
});
ok('a wrong key of the right length is refused', wrongSameLength.status === 401,
  `got ${wrongSameLength.status}`);

// The constant-time compare needs equal lengths; a short key must be rejected
// rather than throw, which is the difference between a 401 and a 500.
const wrongShort = await call('/auth/admin/login', {
  key: 'short',
  method: 'POST', body: { email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD },
});
ok('a wrong key of the wrong length is refused, not a 500', wrongShort.status === 401,
  `got ${wrongShort.status}`);

const unknownPath = await call('/this-endpoint-does-not-exist', { key: KEY });
ok('the right key gets past the door (unknown path is a 404, not a 401)',
  unknownPath.status === 404, `got ${unknownPath.status}`);

// ===================================================== 2. the admin password
console.log('\n--- the admin password ---');

const good = await call('/auth/admin/login', {
  key: KEY, method: 'POST',
  body: { email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD },
});
ok('the rotated admin password works', good.status === 200 && !!good.json?.token,
  `${good.status} ${message(good)}`);

const old = await call('/auth/admin/login', {
  key: KEY, method: 'POST',
  body: { email: 'admin@sathiyaa.com', password: 'Admin@123' },
});
ok('the password printed in the repository does not', old.status === 401,
  `got ${old.status} - the rotation did not take`);

// ================================================ who has an account here
console.log('\n--- what a stranger can find out ---');

const startUnknown = Date.now();
const unknown = await call('/auth/admin/login', {
  key: KEY, method: 'POST',
  body: { email: 'nobody-by-this-name@sathiyaa.com', password: 'Admin@123' },
});
const unknownMs = Date.now() - startUnknown;

ok('an address with no account gets the same status as a wrong password',
  unknown.status === old.status, `${unknown.status} vs ${old.status}`);
ok('...and the same sentence, so neither one confirms the other exists',
  message(unknown) === message(old),
  `"${message(unknown)}" vs "${message(old)}"`);
// A bcrypt compare at cost 10 takes tens of milliseconds; a lookup that misses
// and returns takes one or two. If this is fast, the clock is answering the
// question the status code no longer does.
ok(`...and takes about as long (${unknownMs}ms, so the hash was really compared)`,
  unknownMs >= 15, `${unknownMs}ms is too quick for a bcrypt compare`);

const partnerWrong = await call('/auth/business-agent/login', {
  key: KEY, method: 'POST', body: { identifier: 'BP-000001', password: 'not-the-password' },
});
const partnerUnknown = await call('/auth/business-agent/login', {
  key: KEY, method: 'POST', body: { identifier: 'BP-999999', password: 'not-the-password' },
});
ok('a partner ID that is not one gets the same answer as a wrong password',
  partnerUnknown.status === partnerWrong.status
    && message(partnerUnknown) === message(partnerWrong),
  `${partnerUnknown.status} "${message(partnerUnknown)}" vs ${partnerWrong.status} "${message(partnerWrong)}"`);

const otpReal = await call('/auth/business-agent/reset-otp', {
  key: KEY, method: 'POST', body: { identifier: 'BP-000001' },
});
const otpFake = await call('/auth/business-agent/reset-otp', {
  key: KEY, method: 'POST', body: { identifier: 'BP-999999' },
});
ok('asking for a code says the same thing either way',
  otpReal.status === otpFake.status && otpReal.json?.message === otpFake.json?.message,
  `${otpReal.status} "${otpReal.json?.message}" vs ${otpFake.status} "${otpFake.json?.message}"`);

// ===================================================== 3. CORS
console.log('\n--- who is allowed to call this from a browser ---');

const allowed = await call('/auth/admin/login', {
  key: KEY, origin: ORIGIN, method: 'POST',
  body: { email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD },
});
ok('the console origin is allowed',
  allowed.headers.get('access-control-allow-origin') === ORIGIN,
  `allow-origin: ${allowed.headers.get('access-control-allow-origin')}`);

const stranger = await call('/auth/admin/login', {
  key: KEY, origin: 'https://not-your-console.example', method: 'POST',
  body: { email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD },
});
ok('another site is not',
  stranger.headers.get('access-control-allow-origin') === null,
  `allow-origin: ${stranger.headers.get('access-control-allow-origin')}`);

// ===================================================== 4. security headers
console.log('\n--- headers ---');

ok('uploads and responses are marked nosniff',
  good.headers.get('x-content-type-options') === 'nosniff',
  `got ${good.headers.get('x-content-type-options')}`);
ok('the rate limit is advertised to callers',
  !!(good.headers.get('ratelimit') || good.headers.get('ratelimit-policy')
     || good.headers.get('ratelimit-limit')),
  'no RateLimit header on the response');

// ===================================================== 5. the limiter bites
console.log('\n--- brute force ---');

// authLimiter allows 20 attempts per IP per fifteen minutes. Several have been
// spent above, so a 429 is due well inside this loop.
let limited = null;
let attempts = 0;
for (let i = 0; i < 30; i += 1) {
  attempts += 1;
  const r = await call('/auth/admin/login', {
    key: KEY, method: 'POST',
    body: { email: 'admin@sathiyaa.com', password: `guess-${i}` },
  });
  if (r.status === 429) { limited = r; break; }
}
ok(`repeated wrong passwords get cut off (after ${attempts} tries)`, limited !== null,
  'thirty wrong passwords in a row and the server was still answering');
if (limited) {
  ok('...with the standard error envelope, not a bare 429',
    limited.json?.error?.code === 'RATE_LIMITED',
    JSON.stringify(limited.json).slice(0, 140));
}

// The health check is mounted before the limiter for exactly this reason: an
// attacker hammering the login endpoint must not make the load balancer think
// the instance is dead and take it out of service.
const healthAfter = await call(`${ROOT}/health`);
ok('health still answers while the limiter is holding the door shut',
  healthAfter.status === 200, `got ${healthAfter.status}`);

// ===================================================== 6. preflight refuses
console.log('\n--- the server refuses to start unsafely ---');

function startWith(overrides) {
  const childEnv = { ...process.env, PUBLIC_DEPLOYMENT: 'true' };
  // Whatever the runner set for this process must not leak into the child, or
  // the configuration under test is not the one being described.
  delete childEnv.API_ACCESS_KEY;
  delete childEnv.CORS_ORIGINS;
  delete childEnv.PORT;
  Object.assign(childEnv, overrides);
  const r = spawnSync(process.execPath, ['src/server.js'], {
    cwd: BACKEND, env: childEnv, encoding: 'utf8', timeout: 25000,
  });
  return { code: r.status, out: `${r.stdout || ''}${r.stderr || ''}` };
}

const unsafe = startWith({ JWT_SECRET: 'dev-secret' });
ok('a placeholder secret, no key and no CORS list stops the boot',
  unsafe.code === 1, `exit ${unsafe.code}`);
ok('...and it names the JWT secret', /JWT_SECRET is still the placeholder/.test(unsafe.out),
  unsafe.out.slice(0, 200));
ok('...and the access key', /API_ACCESS_KEY is empty/.test(unsafe.out));
ok('...and CORS', /CORS_ORIGINS is empty/.test(unsafe.out));

const shortKey = startWith({
  JWT_SECRET: 'a'.repeat(48),
  API_ACCESS_KEY: 'too-short',
  CORS_ORIGINS: ORIGIN,
});
ok('a key that is too short stops the boot on its own', shortKey.code === 1,
  `exit ${shortKey.code}`);
ok('...and says how short it is', /API_ACCESS_KEY is 9 characters/.test(shortKey.out),
  shortKey.out.slice(0, 200));

// =====================================================================
console.log(`\n${'='.repeat(68)}`);
console.log(`  ${pass}/${pass + failures.length} passed`);
if (failures.length) {
  console.log('  failed:');
  for (const f of failures) console.log(`    - ${f}`);
}
console.log('='.repeat(68));
process.exit(failures.length === 0 ? 0 : 1);
