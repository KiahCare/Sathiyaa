/**
 * Checks the admin console's real-backend contract, field by field.
 *
 * The console reads specific keys off each response. Where a key is missing
 * the screen either renders blank, shows "Invalid Date", or crashes on
 * `undefined.map` — all of which happened. This asserts the fields the screens
 * actually read, so a future change to a query is caught here rather than by
 * someone staring at an empty page.
 */
const BASE = process.env.SATHIYAA_API ?? process.env.API_BASE ?? 'http://localhost:4000/api/v1';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? 'Admin@123';

let pass = 0;
let fail = 0;
function check(label, ok, detail = '') {
  if (ok) { pass += 1; console.log(`  PASS  ${label}`); }
  else { fail += 1; console.log(`  FAIL  ${label}${detail ? ` — ${detail}` : ''}`); }
}

let token = null;
async function get(path) {
  const res = await fetch(BASE + path, {
    headers: { 'X-Device-Id': 'admin-contract', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
  });
  const text = await res.text();
  try { return { status: res.status, json: JSON.parse(text) }; } catch { return { status: res.status, json: text }; }
}

/** Every listed key must be present (not undefined) on the sample row. */
function hasFields(row, keys) {
  if (!row) return { ok: false, missing: ['<no rows returned>'] };
  const missing = keys.filter((k) => row[k] === undefined);
  return { ok: missing.length === 0, missing };
}

const login = await fetch(`${BASE}/auth/admin/login`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD }),
}).then((r) => r.json());
token = login.token;
check('admin login', !!token);

console.log('\nService Providers');
{
  const r = await get('/admin/providers');
  const row = (r.json.providers || [])[0];
  const f = hasFields(row, [
    'provider_id', 'display_id', 'name', 'photo_url', 'gender', 'mobile_number', 'email',
    'hourly_rate', 'approval_status', 'approval_notes', 'status', 'created_at',
    'provider_kind', 'rating_avg', 'rating_count', 'device_id',
    'distance_from_home_pref_km', 'distance_from_office_pref_km',
    'aadhar_doc_url', 'police_verification_url', 'work_certificate_url',
    'expertise', 'addresses', 'work_hours',
  ]);
  check('every field the directory and drawer read is present', f.ok, `missing: ${f.missing.join(', ')}`);
  check('expertise/addresses/work_hours are arrays', row && Array.isArray(row.expertise) && Array.isArray(row.addresses) && Array.isArray(row.work_hours));
  check('no credential hash is exposed', row && row.pin_hash === undefined && row.otp_hash === undefined);

  const all = await get('/admin/providers?status=all');
  const unfiltered = await get('/admin/providers');
  check('the "All" tab returns everything, not nothing',
    (all.json.providers || []).length === (unfiltered.json.providers || []).length,
    `all=${(all.json.providers || []).length} unfiltered=${(unfiltered.json.providers || []).length}`);

  const pending = await get('/admin/providers?status=pending');
  check('a real status still filters', (pending.json.providers || []).every((p) => p.approval_status === 'pending'));
}

console.log('\nCustomers');
{
  const r = await get('/admin/customers');
  const row = (r.json.customers || [])[0];
  const f = hasFields(row, ['customer_id', 'display_id', 'name', 'photo_url', 'gender', 'mobile_number', 'city', 'referred_by_code', 'status', 'created_at']);
  check('every field the directory reads is present', f.ok, `missing: ${f.missing.join(', ')}`);
  check('no credential hash is exposed', row && row.otp_hash === undefined);
}

console.log('\nBusiness Partners');
{
  const r = await get('/admin/business-agents');
  const row = (r.json.businessAgents || [])[0];
  const f = hasFields(row, ['business_partner_id', 'display_id', 'entity_name', 'partner_name', 'contact_number_1', 'contact_number_2', 'referral_code', 'status', 'created_at']);
  check('every field the directory reads is present', f.ok, `missing: ${f.missing.join(', ')}`);
  check('registration date is a real date', row && !Number.isNaN(Date.parse(row.created_at)), `created_at=${row?.created_at}`);
  check('no credential hash is exposed', row && row.password_hash === undefined && row.otp_hash === undefined);
}

console.log('\nLive Tracking');
{
  const r = await get('/admin/tracking/providers');
  const row = (r.json.providers || [])[0];
  const f = hasFields(row, ['provider_id', 'display_id', 'name', 'current_latitude', 'current_longitude', 'location_on', 'service_types']);
  check('every field the map reads is present', f.ok, `missing: ${f.missing.join(', ')}`);
  check('service_types is an array the label can map over', row && Array.isArray(row.service_types));
}

console.log('\nReports');
{
  const r = await get('/admin/reports/dashboard');
  check('grouped revenue is returned', Array.isArray(r.json.byCity) && Array.isArray(r.json.byServiceType) && Array.isArray(r.json.byProvider));
  const city = (r.json.byCity || [])[0];
  check('city rows carry revenue and bookings', !!city && city.revenue !== undefined && city.bookings !== undefined);
  const prov = (r.json.byProvider || [])[0];
  check('provider rows carry a name for the table', !!prov && prov.name !== undefined && prov.display_id !== undefined);

  const g = await get('/admin/reports/growth?period=month');
  check('growth returns both series', Array.isArray(g.json.customers) && Array.isArray(g.json.providers));
  const point = (g.json.customers || [])[0];
  check('growth points carry a bucket and a count', !!point && point.bucket !== undefined && point.count !== undefined);
}

console.log('\nConfiguration');
{
  const r = await get('/admin/config');
  check('config is returned', r.status === 200, JSON.stringify(r.json).slice(0, 120));
  const rev = await get('/admin/revenue-sharing');
  check('revenue sharing is returned', rev.status === 200);
  const tb = await get('/admin/time-bank-config');
  check('time bank config is returned', tb.status === 200);
}

console.log('\nAudit Log & Broadcast');
{
  const a = await get('/admin/audit-log?limit=5');
  check('audit log is returned', a.status === 200, JSON.stringify(a.json).slice(0, 120));
  const b = await get('/admin/broadcast');
  check('broadcast history is returned', b.status === 200 && Array.isArray(b.json.broadcasts));
}

console.log(`\n=== ${pass}/${pass + fail} passed ===`);
if (fail) process.exit(1);
