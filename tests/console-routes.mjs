/**
 * Can the console actually reach the routes it calls?
 *
 * contract-drift.mjs checks the *shape* of what comes back. This checks
 * something earlier: that the endpoint exists at all, and that the role using
 * it is allowed through the door. TypeScript cannot see either -- a path is a
 * string, and the role guard lives on the server.
 *
 * Two bugs made this worth having, both invisible until someone clicked:
 *
 *   - The admin console's "View partner" panel called the partner's own
 *     /business-agents/me/referrals with a business_partner_id parameter. That
 *     route is behind the business_agent role, so an admin token got 403, and
 *     the handler scopes by the id in the token anyway, so the parameter was
 *     never read. Both tabs spun forever.
 *
 *   - Fixing it by pointing the shared function at the admin route then broke
 *     the partner portal, which calls the same function for its own pages.
 *
 * Only GET routes are probed. A POST or PUT would either create rows or need a
 * valid body, and a DELETE would remove something the rest of the suite is
 * still using.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const BASE = process.env.SATHIYAA_API ?? process.env.API_BASE ?? 'http://localhost:4000/api/v1';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? 'Admin@123';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SERVICES = path.resolve(
  HERE, '..', 'sathiyaa-full-project - Flutter Web version', 'admin-portal', 'src', 'api', 'services.ts'
);

if (!fs.existsSync(SERVICES)) {
  console.log(`SKIP services.ts not found at ${SERVICES}`);
  process.exit(0);
}

const src = fs.readFileSync(SERVICES, 'utf8');

// An interpolation becomes a real id: "does this route exist" is the question,
// and /admin/business-agents/${id}/referrals and /admin/business-agents/1/referrals
// are the same route as far as the router is concerned.
const real = (p) => p.replace(/\$\{[^}]+\}/g, '1');

const found = new Set();

// The easy case: the path is written at the call.
for (const m of src.matchAll(/apiClient\.get\(\s*[`'"]([^`'"]+)[`'"]/g)) found.add(real(m[1]));

// The other case, which this test missed on its first run and which is worth
// the extra work: a helper takes the path as a parameter --
//
//     async function fetchReferrals(path, id) { ... apiClient.get(path) ... }
//     listMyReferrals   -> fetchReferrals('/business-agents/me/referrals', id)
//     listReferralsForAgent -> fetchReferrals(`/admin/business-agents/${id}/referrals`, id)
//
// Nothing at the apiClient call is a literal, so the regex above sees nothing
// and the two routes this whole file exists for would go unchecked. So: find
// helpers that GET a variable, then collect the literals handed to them.
// The `(?::[^{]*)?` is the TypeScript return type -- these are declared
// `): Promise<Thing[]> {`, not `) {`, and without it nothing matches at all.
for (const m of src.matchAll(/(?:export\s+)?(?:async\s+)?function\s+(\w+)\s*\(\s*(\w+)[^)]*\)\s*(?::[^{]*)?\{/g)) {
  const [, fnName, firstParam] = m;
  const body = src.slice(m.index, src.indexOf('\n}', m.index));
  if (!new RegExp(`apiClient\\.get\\(\\s*${firstParam}\\b`).test(body)) continue;

  for (const c of src.matchAll(new RegExp(`\\b${fnName}\\(\\s*[\`'"]([^\`'"]+)[\`'"]`, 'g'))) {
    found.add(real(c[1]));
  }
}

const paths = [...found].filter((p) => p.startsWith('/')).sort();

const login = async (path, body) => {
  const r = await fetch(BASE + path, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  });
  return r.ok ? (await r.json()).token : null;
};

const adminToken = await login('/auth/admin/login', { email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD });
const partnerToken = await login('/auth/business-agent/login', { identifier: 'BP-000001', password: 'Partner@123' });

if (!adminToken) { console.log('FAIL could not sign in as admin'); process.exit(1); }
if (!partnerToken) { console.log('FAIL could not sign in as the seeded partner'); process.exit(1); }

const probe = async (p, token) => {
  const r = await fetch(BASE + p, { headers: { Authorization: `Bearer ${token}` } });
  return r.status;
};

let failures = 0;

// Reachability alone is not enough, and proving that took reintroducing the
// bug: with the admin console pointed back at the partner's /me/ route, every
// referenced route was still reachable -- by the partner -- and the check
// passed. "Some role can reach this" cannot see a page calling the route
// belonging to the other role.
//
// So the pairs that exist precisely because two roles read the same data are
// named here. If one stops being referenced, something has been pointed at the
// other role's route, which is the bug this file was written for.
const REQUIRED = [
  ['/admin/business-agents/1/referrals', 'the admin console\'s "View partner" panel'],
  ['/admin/business-agents/1/revenue', 'the same panel\'s Revenue tab'],
  ['/business-agents/me/referrals', "the partner portal's own My Referrals"],
  ['/business-agents/me/revenue', "the partner portal's own My Revenue"],
];

console.log('routes that must each still be referenced by somebody:');
for (const [p, why] of REQUIRED) {
  const present = found.has(p);
  if (!present) failures += 1;
  console.log(`${present ? 'OK  ' : 'FAIL'} ${p.padEnd(38)} ${why}`);
}

console.log(`\n${paths.length} GET routes referenced by the console:\n`);

for (const p of paths) {
  const asAdmin = await probe(p, adminToken);
  const asPartner = await probe(p, partnerToken);

  // 404 from both roles means the route is not mounted at all. 403/401 from
  // both means it exists but nobody the console signs in as can use it --
  // which is what the "View partner" panel did for months.
  //
  // A 400 or a 422 counts as reached, and the distinction matters. This probe
  // sends no query string, so an endpoint with a required parameter --
  // /admin/geocode?q= is the first of them -- answers "you did not say what to
  // look up". That means the role got past authentication AND the handler ran,
  // which is the opposite of what this test is looking for. Treating it as
  // unreachable reported a working endpoint as broken.
  const DENIED = new Set([401, 403, 404]);
  const reachable = [asAdmin, asPartner].some((s) => !DENIED.has(s));
  const missing = asAdmin === 404 && asPartner === 404;

  let verdict;
  if (missing) { verdict = 'NO SUCH ROUTE'; failures += 1; }
  else if (!reachable) { verdict = 'EXISTS BUT NO ROLE CAN REACH IT'; failures += 1; }
  else verdict = `ok (admin ${asAdmin}, partner ${asPartner})`;

  console.log(`${verdict === 'ok' ? 'OK  ' : (failures ? '    ' : 'OK  ')}${String(asAdmin).padEnd(4)}${String(asPartner).padEnd(5)}${p.padEnd(48)}${verdict}`);
}

console.log('\n' + (failures === 0
  ? `all ${paths.length} routes are reachable by at least one console role`
  : `${failures} unreachable route(s)`));
process.exit(failures === 0 ? 0 : 1);
