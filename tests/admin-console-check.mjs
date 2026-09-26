const BASE = process.env.SATHIYAA_API ?? process.env.API_BASE ?? 'http://localhost:4000/api/v1';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? 'Admin@123';
const call = async (p, token) => {
  const r = await fetch(BASE + p, { headers: token ? { Authorization: `Bearer ${token}` } : {} });
  const t = await r.text();
  try { return { status: r.status, json: JSON.parse(t) }; } catch { return { status: r.status, json: t }; }
};
const login = await fetch(BASE + '/auth/admin/login', {
  method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD }),
});
const T = (await login.json()).token;

const n = (v) => (v === undefined || v === null ? 'MISSING' : v);
// Each of these is a page in the console. Anything but 200 means that page
// opens empty or broken for whoever is looking at it.
let notOk = 0;
const pages = [
  ['Dashboard',        '/admin/reports/dashboard'],
  ['Providers',        '/admin/providers?status=all'],
  ['Customers',        '/admin/customers'],
  ['Business agents',  '/admin/business-agents'],
  ['Growth',           '/admin/reports/growth'],
  ['Revenue sharing',  '/admin/revenue-sharing'],
  ['Time bank',        '/admin/time-bank-config'],
  ['Broadcast',        '/admin/broadcast'],
  ['Tracking',         '/admin/tracking/providers'],
  ['Audit log',        '/admin/audit-log'],
  ['Config',           '/admin/config'],
];
for (const [name, path] of pages) {
  const r = await call(path, T);
  if (r.status !== 200) notOk += 1;
  const j = r.json;
  let shape;
  if (Array.isArray(j)) shape = `array(${j.length})`;
  else if (j && typeof j === 'object') {
    shape = Object.entries(j).map(([k, v]) =>
      Array.isArray(v) ? `${k}:array(${v.length})` : (v && typeof v === 'object' ? `${k}:{}` : `${k}=${n(v)}`)
    ).slice(0, 8).join('  ');
  } else shape = String(j).slice(0, 80);
  console.log(`${String(r.status).padEnd(4)} ${name.padEnd(17)} ${shape}`);
}

console.log(notOk
  ? `\n${notOk} console page(s) did not answer 200`
  : `\nall ${pages.length} console pages answered 200`);

// The "View partner" panel, which is a surface in the console but not a page,
// so the loop above never covered it. It used to call the partner's own
// /business-agents/me/* routes with a business_partner_id parameter: those sit
// behind the business_agent role, so an admin token got 403 — and because the
// modal used a bare .then() with no .catch(), the rejection left its state at
// null, which is what draws the loading skeleton. Both tabs span forever and
// said nothing.
console.log('\nthe "View partner" panel:');
const list = await call('/admin/business-agents', T);
const first = (list.json.businessAgents ?? list.json.agents ?? list.json)[0];
const pid = first?.business_partner_id ?? first?.businessPartnerId;

if (!pid) {
  console.log('SKIP no business partners seeded');
} else {
  for (const [name, path] of [
    ['Referrals tab', `/admin/business-agents/${pid}/referrals`],
    ['Revenue tab',   `/admin/business-agents/${pid}/revenue`],
  ]) {
    const r = await call(path, T);
    if (r.status !== 200) notOk += 1;
    console.log(`${String(r.status).padEnd(4)} ${name.padEnd(17)} ${JSON.stringify(r.json).slice(0, 80)}`);
  }

  // A partner id that does not exist must say so rather than answer with an
  // empty panel that looks like a partner with no referrals.
  const missing = await call('/admin/business-agents/999999/referrals', T);
  if (missing.status !== 404) notOk += 1;
  console.log(`${String(missing.status).padEnd(4)} ${'unknown partner'.padEnd(17)} expected 404`);

  // And the old route must still refuse an admin, so nobody "fixes" this by
  // loosening the role guard instead.
  const old = await call(`/business-agents/me/referrals?business_partner_id=${pid}`, T);
  if (old.status !== 403) notOk += 1;
  console.log(`${String(old.status).padEnd(4)} ${'old /me/ route'.padEnd(17)} expected 403 for an admin token`);
}

if (notOk || !T) process.exitCode = 1;
