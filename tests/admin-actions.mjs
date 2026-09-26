const BASE = process.env.SATHIYAA_API ?? process.env.API_BASE ?? 'http://localhost:4000/api/v1';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? 'Admin@123';
let T;
const call = async (m, p, body) => {
  const r = await fetch(BASE + p, {
    method: m,
    headers: { 'Content-Type': 'application/json', 'X-Device-Id': 'admin-probe', ...(T ? { Authorization: `Bearer ${T}` } : {}) },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
  });
  const t = await r.text();
  let j; try { j = JSON.parse(t); } catch { j = t; }
  return { status: r.status, ok: r.ok, json: j };
};
// Every call below is one an administrator makes in the course of a normal
// day, so every one of them is expected to succeed.
let failed = 0;
const line = (name, r, extra = '') => {
  if (!r.ok) failed += 1;
  console.log(`${r.ok ? 'OK  ' : 'FAIL'} ${String(r.status).padEnd(4)} ${name.padEnd(42)} ${extra || (r.ok ? '' : JSON.stringify(r.json).slice(0, 110))}`);
};

T = (await call('POST', '/auth/admin/login', { email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD })).json.token;
console.log('--- providers ---');
const provs = await call('GET', '/admin/providers?status=all');
const p = provs.json.providers.find((x) => x.status === 'active' && x.approval_status === 'approved');
console.log(`   target: ${p.name} (${p.display_id}) status=${p.status}`);
line('POST /admin/providers/:id/block', await call('POST', `/admin/providers/${p.provider_id}/block`, {}));
let after = (await call('GET', '/admin/providers?status=all')).json.providers.find((x) => x.provider_id === p.provider_id);
console.log(`   -> status is now: ${after.status}`);
line('POST /admin/providers/:id/unblock', await call('POST', `/admin/providers/${p.provider_id}/unblock`, {}));
after = (await call('GET', '/admin/providers?status=all')).json.providers.find((x) => x.provider_id === p.provider_id);
console.log(`   -> status is now: ${after.status}`);
line('POST /admin/providers/:id/hold', await call('POST', `/admin/providers/${p.provider_id}/hold`, {}));
line('POST /admin/providers/:id/reject', await call('POST', `/admin/providers/${p.provider_id}/reject`, { reason: 'probe' }));
line('POST /admin/providers/:id/approve', await call('POST', `/admin/providers/${p.provider_id}/approve`, {}));
line('POST /admin/providers/:id/reset-device', await call('POST', `/admin/providers/${p.provider_id}/reset-device`, {}));

console.log('--- customers ---');
const cust = (await call('GET', '/admin/customers')).json.customers.find((c) => c.status === 'active');
console.log(`   target: ${cust.name} (${cust.display_id}) status=${cust.status}`);
line('POST /admin/customers/:id/block', await call('POST', `/admin/customers/${cust.customer_id}/block`, {}));
line('POST /admin/customers/:id/unblock', await call('POST', `/admin/customers/${cust.customer_id}/unblock`, {}));

console.log('--- business partners ---');
const agents = await call('GET', '/admin/business-agents');
line('GET  /admin/business-agents', agents, `${agents.json.businessAgents?.length} rows`);
const a = agents.json.businessAgents.find((x) => x.referral_code === 'APOL1001')
      ?? agents.json.businessAgents[0];
console.log(`   target: ${a.entity_name ?? a.name} (${a.display_id}) code=${a.referral_code}`);
line('PUT  /admin/business-agents/:id', await call('PUT', `/admin/business-agents/${a.business_partner_id}`, { status: 'active' }));
line('POST /admin/business-agents (create)', await call('POST', '/admin/business-agents', {
  entityName: 'ZZ Test Partner (automated)', partnerName: 'Automated Probe', contactNumber1: '9812345678',
  email: 'probe@example.com', password: 'Probe@1234', address: '1 Probe Rd',
}));

console.log('--- partner login ---');
line('POST /auth/business-agent/login (by code)', await call('POST', '/auth/business-agent/login', { identifier: a.referral_code, password: 'Partner@123' }));
line('POST /auth/business-agent/login (by mobile)', await call('POST', '/auth/business-agent/login', { identifier: a.contact_number_1, password: 'Partner@123' }));
line('POST /auth/business-agent/login (by email)', await call('POST', '/auth/business-agent/login', { identifier: a.email, password: 'Partner@123' }));

console.log('--- config writes ---');
line('PUT  /admin/config', await call('PUT', '/admin/config', { customer_booking_amount: 99 }));
line('PUT  /admin/revenue-sharing', await call('PUT', '/admin/revenue-sharing', { serviceType: 'nurse', customerRatePerHour: 450, providerRatePerHour: 340, businessPartnerFlatPerHour: 45 }));
line('PUT  /admin/time-bank-config', await call('PUT', '/admin/time-bank-config', { serviceType: 'nurse', pointsPerHour: 10, applicationYear: new Date().getFullYear() }));
line('POST /admin/broadcast', await call('POST', '/admin/broadcast', { title: 'Probe', message: 'probe message', audience: 'both' }));

console.log(failed
  ? `\n${failed} admin action(s) failed`
  : '\nevery admin action succeeded');
if (failed) process.exitCode = 1;
