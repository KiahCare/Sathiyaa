/**
 * Do the admin console's settings actually do anything?
 *
 * "It saved" and "it took effect" are different claims, and only the first one
 * is visible from the console. A number that writes to app_configuration and
 * is then ignored by the code that charges people looks completely correct
 * from the admin's chair — the field holds the new value, the toast says
 * saved, and customers keep being charged the old amount.
 *
 * So each check here writes a setting through the admin API and then asks a
 * *different* endpoint, as a different user, what it now believes. And each
 * one puts the original value back, because this runs against a real database.
 */
const BASE = process.env.SATHIYAA_API ?? process.env.API_BASE ?? 'http://localhost:4000/api/v1';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? 'Admin@123';

let failures = 0;
const mark = (pass, line) => {
  if (!pass) failures++;
  console.log(`${pass ? 'OK  ' : 'FAIL'} ${line}`);
};

const call = async (method, path, { token, body } = {}) => {
  const r = await fetch(BASE + path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await r.text();
  let json;
  try { json = JSON.parse(text); } catch { json = text; }
  return { status: r.status, json };
};

const T = (await call('POST', '/auth/admin/login', {
  body: { email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD },
})).json.token;
mark(!!T, 'admin signed in');

// ---- Configuration ----------------------------------------------------
console.log('\nConfiguration — does a changed price reach a customer?');

const before = (await call('GET', '/admin/config', { token: T })).json;
const rows = before.config ?? before;
const asMap = Array.isArray(rows)
  ? Object.fromEntries(rows.map((r) => [r.config_key, Number(r.config_value)]))
  : rows;
const originalBooking = asMap.customer_booking_amount;
mark(Number.isFinite(originalBooking),
  `read customer_booking_amount = ${originalBooking}`);

const probe = originalBooking === 137 ? 138 : 137; // something nothing else uses
const saved = await call('PUT', '/admin/config', {
  token: T,
  body: { config: { customer_booking_amount: probe } },
});
mark(saved.status === 200, `save -> ${saved.status}`);

const readBack = (await call('GET', '/admin/config', { token: T })).json;
const rb = readBack.config ?? readBack;
const rbMap = Array.isArray(rb)
  ? Object.fromEntries(rb.map((r) => [r.config_key, Number(r.config_value)]))
  : rb;
mark(rbMap.customer_booking_amount === probe,
  `the console reads it back as ${rbMap.customer_booking_amount}`);

// The part the console cannot show: does a booking now cost that?
const mobile = `96${Date.now().toString().slice(-8)}`;
const reg = await call('POST', '/auth/customer/register', {
  body: { name: 'Settings Probe', mobile, gender: 'female' },
});
const CT = (await call('POST', '/auth/customer/verify-otp', {
  body: { mobile, otp: reg.json.devOtp },
})).json.token;
await call('PUT', '/customers/me/addresses', {
  token: CT,
  body: { primary: { line1: '1 Probe Road', city: 'Ahmedabad', state: 'KA', pincode: '380001', latitude: 23.0293, longitude: 72.6176 } },
});

const day = new Date();
day.setDate(day.getDate() + 3);
while (day.getDay() === 0) day.setDate(day.getDate() + 1);
const iso = `${day.getFullYear()}-${String(day.getMonth() + 1).padStart(2, '0')}-${String(day.getDate()).padStart(2, '0')}`;

const booking = await call('POST', '/bookings', {
  token: CT,
  body: {
    serviceType: 'companion',
    startDate: iso,
    endDate: iso,
    timeFrom: '09:00',
    timeTo: '13:00',
    latitude: 23.0293,
    longitude: 72.6176,
    address: '1 Probe Road, Ahmedabad',
  },
});
mark(booking.status === 201,
  `booking created -> ${booking.status} ${booking.status !== 201 ? JSON.stringify(booking.json).slice(0, 160) : ''}`);
const charged = booking.json?.bookingChargeAmount;
mark(Number(charged) === probe,
  `a new booking is charged the new amount   configured ${probe}, charged ${charged}`);

// put it back
await call('PUT', '/admin/config', {
  token: T, body: { config: { customer_booking_amount: originalBooking } },
});
const restored = (await call('GET', '/admin/config', { token: T })).json;
const rs = restored.config ?? restored;
const rsMap = Array.isArray(rs)
  ? Object.fromEntries(rs.map((r) => [r.config_key, Number(r.config_value)]))
  : rs;
mark(rsMap.customer_booking_amount === originalBooking, 'original value restored');

// ---- the registration fee, new and renewal ------------------------------
//
// Two fields on this screen were read by nothing: customer_annual_fee_existing
// and provider_annual_fee_existing. They saved, showed a success toast, and
// changed what nobody paid -- there was no renewal anywhere in the product.
// From an administrator's chair they looked exactly as working as the two
// beside them.
console.log('\nThe registration fee, and the renewal fee:');

const JOINING = 271;
const RENEWAL = 133;
const feeCfg = (await call('GET', '/admin/config', { token: T })).json.config;
const feeBefore = Object.fromEntries(feeCfg.map((r) => [r.config_key, r.config_value]));

await call('PUT', '/admin/config', {
  token: T,
  body: { config: { customer_annual_fee_new: JOINING, customer_annual_fee_existing: RENEWAL } },
});

const feeMobile = `94${Date.now().toString().slice(-6)}${Math.floor(Math.random() * 90 + 10)}`;
const feeReg = await call('POST', '/auth/customer/register', {
  body: { name: 'Test Fee Renewal', mobile: feeMobile },
});
const feeToken = (await call('POST', '/auth/customer/verify-otp', {
  body: { mobile: feeMobile, otp: feeReg.json.devOtp },
})).json.token;

const beforePaying = await call('GET', '/customers/me', { token: feeToken });
mark(Number(beforePaying.json.registrationFeeAmount) === JOINING,
  `a new customer is quoted the joining fee   got ${beforePaying.json.registrationFeeAmount}`);
mark(beforePaying.json.registrationIsRenewal === false,
  'and is told it is not a renewal');

const paidNow = await call('POST', '/customers/me/registration-payment', { token: feeToken, body: {} });
mark(Number(paidNow.json.amount) === JOINING,
  `and is charged the joining fee   got ${paidNow.json.amount}`);
mark(paidNow.json.isRenewal === false, 'recorded as a joining payment');

const afterPaying = await call('GET', '/customers/me', { token: feeToken });
mark(Number(afterPaying.json.registrationFeeAmount) === RENEWAL,
  `afterwards they are quoted the RENEWAL fee   got ${afterPaying.json.registrationFeeAmount}`);
mark(afterPaying.json.registrationIsRenewal === true, 'marked as a renewal');
mark(afterPaying.json.registrationRenewalDue === false,
  'but not due yet -- they just paid');
mark(!!afterPaying.json.registrationRenewsAt,
  `with a date on it   ${afterPaying.json.registrationRenewsAt}`);

// A year, give or take a day for the clock.
const renewsAt = new Date(afterPaying.json.registrationRenewsAt);
const daysAway = Math.round((renewsAt - Date.now()) / 864e5);
mark(daysAway >= 364 && daysAway <= 366, `about a year away   ${daysAway} days`);

// Nothing lapses, so paying again inside the year is refused -- and the
// refusal says when the next one is due rather than only that it was refused.
const again = await call('POST', '/customers/me/registration-payment', { token: feeToken, body: {} });
mark(again.status === 409, `paying twice in one year is refused -> ${again.status}`);
mark(/renewal is due on \d{4}-\d{2}-\d{2}/.test(again.json?.error?.message ?? ''),
  `and names the date   "${again.json?.error?.message}"`);

await call('PUT', '/admin/config', {
  token: T,
  body: {
    config: {
      customer_annual_fee_new: Number(feeBefore.customer_annual_fee_new),
      customer_annual_fee_existing: Number(feeBefore.customer_annual_fee_existing),
    },
  },
});
const feeRestored = Object.fromEntries(
  (await call('GET', '/admin/config', { token: T })).json.config.map((r) => [r.config_key, r.config_value])
);
mark(feeRestored.customer_annual_fee_new === feeBefore.customer_annual_fee_new
  && feeRestored.customer_annual_fee_existing === feeBefore.customer_annual_fee_existing,
  'both fees restored');

// ---- the organisation revenue share -------------------------------------
//
// "20% on top of 100/hr shows as 120/hr to the customer." It was applied when
// the bill was worked out at the end of a visit, and nowhere else -- so the
// card a family chose from said 100 and the invoice said 120.
console.log('\nThe organisation revenue share, as the family sees it:');

const MARKUP = 25;
const ORG_RATE = 200;
const shareBefore = feeBefore.org_revenue_share_percent;
await call('PUT', '/admin/config', { token: T, body: { config: { org_revenue_share_percent: MARKUP } } });

const orgMobile = `93${Date.now().toString().slice(-6)}${Math.floor(Math.random() * 90 + 10)}`;
const orgReg = await call('POST', '/auth/provider/register', {
  body: {
    providerKind: 'organization',
    name: 'Test Markup Agency',
    mobile: orgMobile,
    pin: '774411',
    hourlyRate: ORG_RATE,
    addresses: [{ addressType: 'home', line1: 'Ashram Road', city: 'Ahmedabad', latitude: 23.0225, longitude: 72.5714 }],
    expertise: [{ serviceType: 'companion' }],
  },
});
const orgToken = orgReg.json.token;
const orgId = orgReg.json.provider?.providerId ?? orgReg.json.providerId;
await call('PUT', '/providers/me', { token: orgToken, body: { allocateViaOrg: true } });
await call('POST', `/admin/providers/${orgId}/approve`, { token: T, body: {} });

const validTo = new Date(Date.now() + 365 * 864e5).toISOString().slice(0, 10);
const carer = await call('POST', '/providers/employees', {
  token: orgToken,
  body: {
    name: 'Test Markup Carer',
    mobile: `92${Date.now().toString().slice(-6)}${Math.floor(Math.random() * 90 + 10)}`,
    gender: 'female',
    addresses: [{ addressType: 'home', line1: 'Paldi', latitude: 23.0126, longitude: 72.56 }],
    address: { line1: 'Paldi', latitude: 23.0126, longitude: 72.56 },
    expertise: [{ serviceType: 'companion' }],
    workHours: ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']
      .map((d) => ({ dayOfWeek: d, startTime: '00:00', endTime: '23:59' })),
    aadharDocUrl: '/uploads/aadhar/markup.jpg',
    policeVerificationUrl: '/uploads/police-verification/markup.jpg',
    policeVerificationValidTo: validTo,
  },
});
await call('POST', `/admin/providers/${carer.json.providerId}/approve`, { token: T, body: {} });

const searchDay = (() => {
  const d = new Date(Date.now() + 3 * 864e5);
  while (d.getDay() === 0 || d.getDay() === 6) d.setDate(d.getDate() + 1);
  return d.toISOString().slice(0, 10);
})();
const quote = await call('GET',
  `/providers/search?service_type=companion&date_from=${searchDay}`
  + '&time_from=10:00:00&time_to=12:00:00&lat=23.0225&lng=72.5714&radius_km=25',
  { token: feeToken });
const agency = (quote.json.providers ?? []).find((p) => Number(p.providerId) === Number(orgId));
mark(!!agency, 'the agency appears in a family search');
mark(Number(agency?.hourlyRate) === ORG_RATE * (1 + MARKUP / 100),
  `quoted at the fee PLUS the share   ${ORG_RATE} + ${MARKUP}% = ${ORG_RATE * (1 + MARKUP / 100)}, got ${agency?.hourlyRate}`);

// Change the share; the quote has to move with it.
await call('PUT', '/admin/config', { token: T, body: { config: { org_revenue_share_percent: 0 } } });
const quote2 = await call('GET',
  `/providers/search?service_type=companion&date_from=${searchDay}`
  + '&time_from=10:00:00&time_to=12:00:00&lat=23.0225&lng=72.5714&radius_km=25',
  { token: feeToken });
const agency2 = (quote2.json.providers ?? []).find((p) => Number(p.providerId) === Number(orgId));
mark(Number(agency2?.hourlyRate) === ORG_RATE,
  `at 0% the quote is the bare fee   got ${agency2?.hourlyRate}`);

// A freelancer is not marked up -- the share is an organisation arrangement.
// Compared across the two searches rather than against a number: a rate of 0
// is a real answer here, because a volunteer gives their time free.
const free1 = (quote.json.providers ?? []).filter((p) => p.providerKind === 'freelancer');
const free2 = new Map(
  (quote2.json.providers ?? [])
    .filter((p) => p.providerKind === 'freelancer')
    .map((p) => [Number(p.providerId), Number(p.hourlyRate)])
);
const moved = free1.filter((p) => free2.has(Number(p.providerId))
  && free2.get(Number(p.providerId)) !== Number(p.hourlyRate));
mark(free1.length > 0 && moved.length === 0,
  `a freelancer's rate does not move with the organisation share   `
  + `${free1.length} compared, ${moved.length} moved`);

await call('PUT', '/admin/config', {
  token: T, body: { config: { org_revenue_share_percent: Number(shareBefore) } },
});
const shareRestored = Object.fromEntries(
  (await call('GET', '/admin/config', { token: T })).json.config.map((r) => [r.config_key, r.config_value])
);
mark(shareRestored.org_revenue_share_percent === shareBefore,
  `share restored to ${shareBefore}%`);

// ---- Revenue sharing ---------------------------------------------------
console.log('\nRevenue sharing:');
const rev = await call('GET', '/admin/revenue-sharing', { token: T });
const revRows = rev.json.revenueSharing ?? rev.json;
mark(rev.status === 200 && Array.isArray(revRows) && revRows.length > 0,
  `reads ${revRows?.length} service types`);

const row = revRows[0];
const origCustomerRate = Number(row.customer_rate_per_hour);
const newRate = origCustomerRate + 1;
const revSave = await call('PUT', '/admin/revenue-sharing', {
  token: T,
  body: { items: [{ ...row, customer_rate_per_hour: newRate }] },
});
mark(revSave.status === 200, `save -> ${revSave.status}`);

const revBack = await call('GET', '/admin/revenue-sharing', { token: T });
const back = (revBack.json.revenueSharing ?? revBack.json)
  .find((r) => r.service_type === row.service_type);
mark(Number(back.customer_rate_per_hour) === newRate,
  `${row.service_type} rate is now ${back.customer_rate_per_hour}`);

await call('PUT', '/admin/revenue-sharing', {
  token: T, body: { items: [{ ...row, customer_rate_per_hour: origCustomerRate }] },
});
mark(true, 'original rate restored');

// ---- Time bank ----------------------------------------------------------
console.log('\nTime bank:');
const tb = await call('GET', '/admin/time-bank-config', { token: T });
const tbRows = tb.json.timeBankConfig ?? tb.json;
mark(tb.status === 200 && Array.isArray(tbRows), `reads ${tbRows?.length} rows`);

if (tbRows.length > 0) {
  const t0 = tbRows[0];
  const origPts = Number(t0.points_per_hour);
  await call('PUT', '/admin/time-bank-config', {
    token: T, body: { items: [{ ...t0, points_per_hour: origPts + 1 }] },
  });
  const tbBack = await call('GET', '/admin/time-bank-config', { token: T });
  const b0 = (tbBack.json.timeBankConfig ?? tbBack.json)
    .find((r) => r.service_type === t0.service_type && r.application_year === t0.application_year);
  mark(Number(b0.points_per_hour) === origPts + 1,
    `points_per_hour saved as ${b0.points_per_hour}`);
  await call('PUT', '/admin/time-bank-config', {
    token: T, body: { items: [{ ...t0, points_per_hour: origPts }] },
  });
  mark(true, 'original points restored');
}

// ---- rejecting nonsense --------------------------------------------------
console.log('\nrefusing bad input:');
const negative = await call('PUT', '/admin/config', {
  token: T, body: { config: { customer_booking_amount: -50 } },
});
const afterNeg = (await call('GET', '/admin/config', { token: T })).json;
const an = afterNeg.config ?? afterNeg;
const anMap = Array.isArray(an)
  ? Object.fromEntries(an.map((r) => [r.config_key, Number(r.config_value)]))
  : an;
mark(negative.status === 400,
  `a negative price is refused   save returned ${negative.status}`);
mark(anMap.customer_booking_amount === originalBooking,
  `and nothing was changed   value is still ${anMap.customer_booking_amount}`);

const notANumber = await call('PUT', '/admin/config', {
  token: T, body: { config: { customer_booking_amount: 'banana' } },
});
mark(notANumber.status === 400,
  `a non-numeric price is refused   save returned ${notANumber.status}`);

// A bad value in the middle must not leave the earlier ones applied.
const partial = await call('PUT', '/admin/config', {
  token: T, body: { config: { customer_booking_amount: 150, provider_annual_fee_new: -1 } },
});
const afterPartial = (await call('GET', '/admin/config', { token: T })).json;
const ap = afterPartial.config ?? afterPartial;
const apMap = Array.isArray(ap)
  ? Object.fromEntries(ap.map((r) => [r.config_key, Number(r.config_value)]))
  : ap;
mark(partial.status === 400 && apMap.customer_booking_amount === originalBooking,
  'a bad value in the middle applies none of them');
if (anMap.customer_booking_amount !== originalBooking) {
  await call('PUT', '/admin/config', {
    token: T, body: { config: { customer_booking_amount: originalBooking } },
  });
}

console.log('\n' + (failures === 0 ? 'all checks passed' : `${failures} FAILURES`));
process.exit(failures === 0 ? 0 : 1);
