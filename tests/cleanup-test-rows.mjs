// Removes the accounts the test scripts leave behind.
//
// Every script here creates real rows through the real API -- that is the
// point of them -- but the console then fills with "Audit Provider" and
// "Block Probe" next to genuine people. This sweeps them out.
//
// Two safety rails:
//   * it only deletes rows whose name matches a pattern the scripts own, and
//   * the DELETE endpoints themselves refuse any account that has ever taken
//     a booking, so anything with history survives regardless.

const BASE = process.env.SATHIYAA_API ?? process.env.API_BASE ?? 'http://localhost:4000/api/v1';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? 'Admin@123';

const login = await fetch(BASE + '/auth/admin/login', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD }),
});
const T = (await login.json()).token;
const H = { Authorization: `Bearer ${T}` };

// Names the test scripts create. "(QA)" is the tag the scripts that use
// realistic names add, so a real "Anjali Deshpande" is never matched.
const TEST_NAME = new RegExp(
  [
    '\\(QA\\)',                 // tagged by practical.mjs / full-journey.mjs
    '^Audit ',
    '^Smoke ',
    '^Flutter ',
    '^Parity ',
    '^Contact Mode ',
    '^Debug ',
    '^Curious Stranger',
    '^Three-Device ',
    '^ZZ Test ',
    '^Test ',                     // Test Agency Care Services, Test Carer One..Five
    'Probe',                      // Block Probe, Other Probe, Upload Probe, Gender Probe
    'Audit$',                     // Ravi Audit
  ].join('|'),
  'i',
);

let removed = 0;
let kept = 0;

for (const [kind, listPath, listKey, idKey, nameKey] of [
  ['providers', '/admin/providers?status=all', 'providers', 'provider_id', 'name'],
  ['customers', '/admin/customers', 'customers', 'customer_id', 'name'],
]) {
  const rows = (await (await fetch(BASE + listPath, { headers: H })).json())[listKey] || [];
  const targets = rows.filter((r) => TEST_NAME.test(r[nameKey] || ''));
  console.log(`${kind}: ${targets.length} test row(s) found`);

  for (const r of targets) {
    const res = await fetch(`${BASE}/admin/${kind}/${r[idKey]}`, { method: 'DELETE', headers: H });
    const body = await res.json().catch(() => ({}));
    if (res.ok) {
      removed++;
      console.log(`  removed  ${r.display_id}  ${r[nameKey]}`);
    } else {
      kept++;
      // Almost always "has history" -- which is the rail working, not a fault.
      console.log(`  kept     ${r.display_id}  ${r[nameKey]}  (${body.error?.message ?? res.status})`);
    }
  }
}

// Business partners have no delete endpoint -- an account that has referred
// anybody must keep its history -- so they are reported rather than removed.
const agents = (await (await fetch(BASE + '/admin/business-agents', { headers: H })).json())
  .businessAgents || [];
const testAgents = agents.filter((a) => TEST_NAME.test(a.entity_name || ''));
if (testAgents.length) {
  console.log(`\nbusiness partners: ${testAgents.length} test row(s) — no delete endpoint, remove by hand if they bother you:`);
  for (const a of testAgents) console.log(`  ${a.display_id}  ${a.entity_name}`);
}

console.log(`\n${removed} removed, ${kept} kept (anything with booking history is left alone).`);
