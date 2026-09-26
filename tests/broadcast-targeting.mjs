/**
 * Broadcasts: do they reach anybody, and can they be aimed?
 *
 * Before this feature existed the answer to the first question was no. The
 * message was written to broadcast_messages, the recipients were counted, and
 * the list was handed to the push adapter -- a stub that logs a line and
 * returns sent:false. No endpoint existed for a customer or provider to ask
 * what had been sent to them, so every broadcast in the history read
 * delivered_count = 0. Accurately.
 *
 * So the checks below care about two things above all:
 *   - somebody targeted actually receives it, through an endpoint their app
 *     can call
 *   - somebody NOT targeted does not, which is the half that is easy to get
 *     wrong and impossible to notice from the sending side
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

// ---- an admin, and two customers in two different cities --------------
const login = await call('POST', '/auth/admin/login', {
  body: { email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD },
});
const T = login.json.token;
mark(!!T, 'admin signed in');

const makeCustomer = async (name, city, pincode) => {
  const mobile = `97${Date.now().toString().slice(-7)}${Math.floor(Math.random() * 10)}`;
  const reg = await call('POST', '/auth/customer/register', {
    body: { name, mobile, gender: 'female' },
  });
  const v = await call('POST', '/auth/customer/verify-otp', {
    body: { mobile, otp: reg.json.devOtp },
  });
  const token = v.json.token;
  // The endpoint takes { primary, secondary }, not a flat address.
  await call('PUT', '/customers/me/addresses', {
    token,
    body: {
      primary: {
        line1: `1 ${city} Road`,
        city,
        state: 'Test',
        pincode,
        latitude: 23.0209,
        longitude: 72.5668,
      },
    },
  });
  return { name, mobile, token };
};

const CITY_A = `Testville${Date.now().toString().slice(-6)}`;
const CITY_B = `Otherton${Date.now().toString().slice(-6)}`;

const inA = await makeCustomer('Broadcast Target A', CITY_A, '380001');
const inB = await makeCustomer('Broadcast Target B', CITY_B, '411001');
mark(!!inA.token && !!inB.token, `two customers created, one in ${CITY_A}, one in ${CITY_B}`);

// ---- the preview must agree with what sending would do ----------------
console.log('\naiming at one city:');
const preview = await call('POST', '/admin/broadcast/preview', {
  token: T,
  body: { audience: 'customers', cities: [CITY_A] },
});
mark(preview.status === 200, `preview -> ${preview.status}`);
mark(preview.json.total === 1,
  `preview counts exactly the one customer in ${CITY_A}   got ${preview.json.total}`);

// Case should not matter: an admin typing "ahmedabad" means Ahmedabad.
const lower = await call('POST', '/admin/broadcast/preview', {
  token: T,
  body: { audience: 'customers', cities: [CITY_A.toLowerCase()] },
});
mark(lower.json.total === 1, 'city matching ignores case');

// ---- send it ----------------------------------------------------------
const sent = await call('POST', '/admin/broadcast', {
  token: T,
  body: {
    title: 'City test',
    message: `Only ${CITY_A} should see this.`,
    audience: 'customers',
    cities: [CITY_A],
  },
});
mark(sent.status === 201, `send -> ${sent.status}`);
mark(sent.json.recipients === 1, `reported 1 recipient   got ${sent.json.recipients}`);
mark(sent.json.delivered === 1,
  `delivered is no longer always zero   got ${sent.json.delivered}`);

// ---- the half that matters --------------------------------------------
console.log('\nwho actually received it:');
const gotA = await call('GET', '/broadcasts', { token: inA.token });
const gotB = await call('GET', '/broadcasts', { token: inB.token });

mark(gotA.status === 200, `the targeted customer can read their inbox -> ${gotA.status}`);
mark((gotA.json.broadcasts ?? []).some((b) => b.title === 'City test'),
  'the targeted customer HAS the message');
mark(!(gotB.json.broadcasts ?? []).some((b) => b.title === 'City test'),
  'the customer in the other city does NOT have it');

// ---- unread, and marking read -----------------------------------------
console.log('\nread state:');
const unread = await call('GET', '/broadcasts/unread', { token: inA.token });
mark(unread.json.unread >= 1, `unread count is ${unread.json.unread}`);

const bid = gotA.json.broadcasts.find((b) => b.title === 'City test').id;
await call('POST', `/broadcasts/${bid}/read`, { token: inA.token });
const after = await call('GET', '/broadcasts', { token: inA.token });
mark(after.json.broadcasts.find((b) => b.id === bid)?.read === true,
  'marking read sticks');

// Marking somebody else's broadcast read must change nothing of theirs.
const sneaky = await call('POST', `/broadcasts/${bid}/read`, { token: inB.token });
mark(sneaky.status === 200 && sneaky.json.changed === 0,
  'marking a broadcast that was never yours changes nothing');

// ---- hand-picked recipients -------------------------------------------
console.log('\nhand-picked people:');
const customers = await call('GET', '/admin/customers', { token: T });
const list = customers.json.customers ?? customers.json;
const twoIds = list.slice(0, 2).map((c) => c.customer_id);

const picked = await call('POST', '/admin/broadcast/preview', {
  token: T,
  body: { audience: 'customers', customerIds: twoIds },
});
mark(picked.json.total === twoIds.length,
  `picking ${twoIds.length} people by id counts ${picked.json.total}`);

const bothWays = await call('POST', '/admin/broadcast/preview', {
  token: T,
  body: { audience: 'customers', customerIds: twoIds, cities: [CITY_A] },
});
mark(bothWays.status === 400,
  'picking by hand AND by city is refused rather than guessed at');

const wrongRole = await call('POST', '/admin/broadcast/preview', {
  token: T,
  body: { audience: 'customers', providerIds: [1] },
});
mark(wrongRole.status === 400,
  'provider ids with a customers-only audience is refused, not silently empty');

// ---- a target that matches nobody --------------------------------------
console.log('\nnobody matches:');
const empty = await call('POST', '/admin/broadcast', {
  token: T,
  body: {
    title: 'Nowhere',
    message: 'Nobody lives here.',
    audience: 'customers',
    cities: ['CityThatDoesNotExist'],
  },
});
mark(empty.status === 422,
  `sending to nobody is refused rather than reported as sent   got ${empty.status}`);

// ---- the cities picker --------------------------------------------------
console.log('\nthe city picker:');
const cities = await call('GET', '/admin/broadcast/cities', { token: T });
mark(cities.status === 200, `cities -> ${cities.status}`);
const found = (cities.json.cities ?? []).find((c) => c.city === CITY_A);
mark(!!found, `${CITY_A} appears in the picker`);
mark(found?.customers === 1, `and reports 1 customer   got ${found?.customers}`);

// ---- an admin has no inbox ---------------------------------------------
const adminInbox = await call('GET', '/broadcasts', { token: T });
mark(adminInbox.status === 403, `an admin has no broadcast inbox -> ${adminInbox.status}`);

console.log('\n' + (failures === 0 ? 'all checks passed' : `${failures} FAILURES`));
process.exit(failures === 0 ? 0 : 1);
