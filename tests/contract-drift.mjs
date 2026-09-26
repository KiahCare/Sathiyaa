/**
 * Does the server send what the console expects?
 *
 * The admin portal hands most API responses straight to the pages, typed as
 * whatever the interface claims. TypeScript cannot check that: the response is
 * `any` at the boundary, so a field the server never sends type-checks fine and
 * then throws at runtime. That has now happened three times -- a blank column
 * of provider names, a whole console blanked by a missing recipient_count, and
 * a customer list with no city.
 *
 * This reads the interfaces out of the portal's own types file, calls each
 * endpoint, and reports any required field the server does not actually send.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const BASE = process.env.SATHIYAA_API ?? process.env.API_BASE ?? 'http://localhost:4000/api/v1';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? 'Admin@123';
// Resolved relative to this file, so the folder can be moved or copied without
// the check quietly pointing at nothing.
const HERE = path.dirname(fileURLToPath(import.meta.url));
const TYPES = path.resolve(
  HERE,
  '..',
  'sathiyaa-full-project - Flutter Web version',
  'admin-portal',
  'src',
  'types',
  'index.ts'
);

// ------------------------------------------------------------ parse types --
const src = fs.readFileSync(TYPES, 'utf8');

/** Required (non-`?`) property names of one exported interface. */
function requiredFields(name) {
  const m = new RegExp(`export interface ${name}\\s*\\{([\\s\\S]*?)\\n\\}`).exec(src);
  if (!m) return null;
  return m[1]
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('//') && !l.startsWith('*') && !l.startsWith('/*'))
    .map((l) => /^([A-Za-z_][A-Za-z0-9_]*)(\?)?\s*:/.exec(l))
    .filter(Boolean)
    .filter((m2) => !m2[2]) // drop optional ones
    .map((m2) => m2[1]);
}

// --------------------------------------------------------------- fetching --
const login = await fetch(`${BASE}/auth/admin/login`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD }),
});
const token = (await login.json()).token;
const get = async (p) => {
  const r = await fetch(BASE + p, { headers: { Authorization: `Bearer ${token}` } });
  const t = await r.text();
  try { return JSON.parse(t); } catch { return t; }
};

/** Endpoint, the key holding the list, and the interface it is claimed to be. */
const CHECKS = [
  ['/admin/providers?status=all', 'providers', 'ServiceProvider'],
  ['/admin/customers', 'customers', 'Customer'],
  ['/admin/business-agents', 'businessAgents', 'BusinessAgent'],
  ['/admin/broadcast', 'broadcasts', 'BroadcastMessage'],
  ['/admin/tracking/providers', 'providers', 'ProviderTrackingEntry'],
  ['/admin/audit-log', 'auditLog', 'AuditLogEntry'],
  ['/admin/revenue-sharing', 'revenueSharing', 'RevenueSharingConfig'],
  ['/admin/time-bank-config', 'timeBankConfig', 'TimeBankConfig'],
];

// The partner portal is a separate sign-in, so it needs its own token. Its two
// pages had drifted the furthest of anything -- one of them blanked the whole
// portal -- precisely because nothing was checking them.
const partnerLogin = await fetch(`${BASE}/auth/business-agent/login`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ identifier: 'BP-000001', password: 'Partner@123' }),
});
const partnerToken = (await partnerLogin.json()).token;
const getAsPartner = async (p) => {
  const r = await fetch(BASE + p, { headers: { Authorization: `Bearer ${partnerToken}` } });
  const t = await r.text();
  try { return JSON.parse(t); } catch { return t; }
};

const PARTNER_CHECKS = [
  ['/business-agents/me/referrals', 'referrals', 'BusinessAgentReferral'],
];

let problems = 0;
let checked = 0;

console.log(`Comparing the server's responses with the console's own types.\n`);

for (const [endpoint, key, iface] of CHECKS) {
  const want = requiredFields(iface);
  if (!want) {
    console.log(`  ????  ${iface.padEnd(24)} interface not found in types/index.ts`);
    continue;
  }

  const body = await get(endpoint);
  const rows = body?.[key] ?? body;
  if (!Array.isArray(rows) || rows.length === 0) {
    console.log(`  ----  ${iface.padEnd(24)} ${endpoint}  (no rows to inspect)`);
    continue;
  }

  checked++;
  const row = rows[0];
  const missing = want.filter((f) => !(f in row));

  if (missing.length === 0) {
    console.log(`  OK    ${iface.padEnd(24)} ${want.length} required field(s) all present`);
  } else {
    problems++;
    console.log(`  DRIFT ${iface.padEnd(24)} ${endpoint}`);
    console.log(`        the console requires but the server omits: ${missing.join(', ')}`);
    console.log(`        server actually sends: ${Object.keys(row).slice(0, 14).join(', ')}`);
  }
}

for (const [endpoint, key, iface] of PARTNER_CHECKS) {
  const want = requiredFields(iface);
  if (!want) {
    console.log(`  ????  ${iface.padEnd(24)} interface not found`);
    continue;
  }
  const body = await getAsPartner(endpoint);
  const rows = body?.[key] ?? body;
  if (!Array.isArray(rows) || rows.length === 0) {
    console.log(`  ----  ${iface.padEnd(24)} ${endpoint}  (no rows to inspect)`);
    continue;
  }
  checked++;
  const missing = want.filter((f) => !(f in rows[0]));
  if (missing.length === 0) {
    console.log(`  OK    ${iface.padEnd(24)} ${want.length} required field(s) all present`);
  } else {
    problems++;
    console.log(`  DRIFT ${iface.padEnd(24)} ${endpoint}`);
    console.log(`        the console requires but the server omits: ${missing.join(', ')}`);
    console.log(`        server actually sends: ${Object.keys(rows[0]).slice(0, 14).join(', ')}`);
  }
}

console.log(`\n${'='.repeat(70)}`);
console.log(problems === 0
  ? `  no drift across ${checked} list endpoint(s)`
  : `  ${problems} endpoint(s) drifted from the console's types`);
console.log('='.repeat(70));
if (problems) process.exitCode = 1;
