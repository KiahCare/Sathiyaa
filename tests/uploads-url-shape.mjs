/**
 * What shape does an upload URL come back in, and can it be fetched?
 *
 * Two bugs, both of which only showed up once the thing was behind a CDN:
 *
 *   - The endpoint returned `${req.protocol}://${req.get('host')}${path}`.
 *     CloudFront forwards every header except Host, so that resolved to the
 *     origin's own name over plain http, with the port missing, on an instance
 *     whose only open port is closed to everyone but CloudFront. Customer
 *     photos uploaded through the deployed app were stored with an address
 *     that nothing could ever load.
 *
 *   - Clients decided "is this already a server URL?" with `startsWith('/')`.
 *     Android hands back `/data/user/0/<pkg>/cache/scaled_1234.jpg`, which
 *     starts with a slash, so every provider document was judged already
 *     uploaded, the upload was skipped, and the phone's own path went into the
 *     database.
 *
 * So: the URL must be relative, must start with /uploads/, and must actually
 * serve the bytes back.
 */
const BASE = process.env.SATHIYAA_API ?? process.env.API_BASE ?? 'http://localhost:4000/api/v1';
const ROOT = BASE.replace(/\/api\/v\d+\/?$/, '');

let failures = 0;
const mark = (pass, line) => {
  if (!pass) failures++;
  console.log(`${pass ? 'OK  ' : 'FAIL'} ${line}`);
};

// A one-pixel PNG, built here so the test needs no fixture file on disk.
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  'base64'
);

const mobile = `98${Date.now().toString().slice(-8)}`;
let reg = await fetch(BASE + '/auth/customer/register', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ name: 'Upload Shape Test', mobile, gender: 'female' }),
});
let body = await reg.json();
if (!reg.ok) {
  console.log(`FAIL could not register a test customer: ${reg.status} ${JSON.stringify(body)}`);
  process.exit(1);
}
const verify = await fetch(BASE + '/auth/customer/verify-otp', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ mobile, otp: body.devOtp }),
});
const token = (await verify.json()).token;
mark(!!token, 'signed in as a throwaway customer');

const form = new FormData();
form.append('file', new Blob([PNG], { type: 'image/png' }), 'dot.png');
const up = await fetch(BASE + '/uploads?category=photo', {
  method: 'POST',
  headers: { Authorization: `Bearer ${token}` },
  body: form,
});
const j = await up.json();
mark(up.status === 201, `upload -> ${up.status}`);

const url = j.url;
mark(typeof url === 'string' && url.startsWith('/uploads/'),
  `url is a relative /uploads/ path   got: ${url}`);
mark(!/^https?:\/\//.test(url ?? ''),
  'url is NOT absolute (an absolute one bakes in whichever host answered)');
mark(j.path === url, 'path and url agree');

// The bytes have to come back, from the API host, without a token.
const fetched = await fetch(ROOT + url);
const bytes = Buffer.from(await fetched.arrayBuffer());
mark(fetched.ok, `the file is served back -> ${fetched.status}`);
mark((fetched.headers.get('content-type') ?? '').startsWith('image/'),
  `served as an image, not a page   got: ${fetched.headers.get('content-type')}`);
mark(bytes.length === PNG.length && bytes.equals(PNG),
  `the bytes match what went up   ${bytes.length} vs ${PNG.length}`);

// And the shape check clients use must reject a phone path.
const androidPath = '/data/user/0/in.sathiyaa.provider/cache/scaled_1234.jpg';
const isServerRef = (r) =>
  !!r && (r.startsWith('http://') || r.startsWith('https://') || r.startsWith('/uploads/'));
mark(!isServerRef(androidPath), 'an Android cache path is not mistaken for a server path');
mark(isServerRef(url), 'a real upload path is recognised as a server path');

console.log('\n' + (failures === 0 ? 'all checks passed' : `${failures} FAILURES`));
process.exit(failures === 0 ? 0 : 1);
