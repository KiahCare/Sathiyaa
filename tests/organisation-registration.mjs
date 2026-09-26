/**
 * Does an organisation register as an organisation?
 *
 * It did not. One registration form served both paths, so an agency was
 * stored as a person: a gender, a date of birth, an Aadhaar card and a police
 * verification belonging to whichever director filled the form in. That last
 * one is not a cosmetic problem. An admin approving the agency was approving
 * one person's police check, and every carer the agency added afterwards
 * inherited that approval without ever having been checked -- while the app
 * went on telling families that every carer is verified by Sathiyaa.
 *
 * So this checks the two halves of the fix:
 *
 *   1. an organisation carries what an organisation has -- a registration
 *      certificate, a GST number, somebody to speak to -- and does NOT carry
 *      a gender or a date of birth
 *
 *   2. a carer an organisation adds carries their OWN documents, and starts
 *      pending regardless of the organisation's status
 */
const BASE = process.env.SATHIYAA_API ?? process.env.API_BASE ?? 'http://localhost:4000/api/v1';

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

const mobile = () => `97${Date.now().toString().slice(-6)}${Math.floor(Math.random() * 90 + 10)}`;
const ymd = (d) => d.toISOString().slice(0, 10);

// ---- an organisation registers ------------------------------------------
console.log('An organisation registering:');

const orgMobile = mobile();
const reg = await call('POST', '/auth/provider/register', {
  body: {
    providerKind: 'organization',
    name: 'Test Agency Care Services',
    mobile: orgMobile,
    pin: '451236',
    hourlyRate: 400,
    // What an organisation actually has.
    orgRegistrationUrl: '/uploads/org-registration/test-cert.png',
    gstNumber: '29ABCDE1234F1Z5',
    contactPerson: 'Meera Nair',
    // And what it does NOT: no gender, no dob, no Aadhaar, no police check.
    addresses: [{ addressType: 'home', line1: '4th Floor, Ashram Road', city: 'Ahmedabad', latitude: 23.0209, longitude: 72.5668 }],
    workHours: [
      { dayOfWeek: 'mon', startTime: '08:00:00', endTime: '20:00:00' },
      { dayOfWeek: 'sat', startTime: '09:00:00', endTime: '13:00:00' },
    ],
    expertise: [{ serviceType: 'companion' }],
  },
});
mark(reg.status === 201, `registered -> ${reg.status} ${reg.status !== 201 ? JSON.stringify(reg.json).slice(0, 200) : ''}`);
const ORG = reg.json.token;
mark(!!ORG, 'and is signed in');

const me = await call('GET', '/providers/me', { token: ORG });
mark(me.json.providerKind === 'organization', `stored as ${me.json.providerKind}`);
mark(me.json.orgRegistrationUrl === '/uploads/org-registration/test-cert.png',
  'the registration certificate is on the record');
mark(me.json.gstNumber === '29ABCDE1234F1Z5', 'the GST number is on the record');
mark(me.json.contactPerson === 'Meera Nair', 'and the person to speak to');

// The part that used to be wrong.
mark(me.json.gender === null || me.json.gender === undefined,
  `no gender was invented   got ${JSON.stringify(me.json.gender)}`);
mark(me.json.dob === null || me.json.dob === undefined,
  `no date of birth was invented   got ${JSON.stringify(me.json.dob)}`);
mark(!me.json.policeVerificationUrl,
  'and no police verification is claimed for the company');

// ---- the hours it actually entered ---------------------------------------
console.log('\nWork hours, per day:');
const hours = me.json.workHours ?? [];
const mon = hours.find((h) => h.day_of_week === 'mon' || h.dayOfWeek === 'mon');
const sat = hours.find((h) => h.day_of_week === 'sat' || h.dayOfWeek === 'sat');
mark(!!mon && !!sat, `both days stored   ${hours.length} rows`);
mark(mon && `${mon.start_time ?? mon.startTime}`.startsWith('08:00'),
  `Monday starts 08:00   got ${mon && (mon.start_time ?? mon.startTime)}`);
mark(sat && `${sat.start_time ?? sat.startTime}`.startsWith('09:00'),
  `Saturday starts 09:00, not Monday's hours copied over   got ${sat && (sat.start_time ?? sat.startTime)}`);
mark(sat && `${sat.end_time ?? sat.endTime}`.startsWith('13:00'),
  `and finishes 13:00   got ${sat && (sat.end_time ?? sat.endTime)}`);

// ---- a carer the organisation adds ---------------------------------------
console.log('\nA carer the organisation adds:');

const year = new Date();
const validFrom = ymd(new Date(year.getFullYear() - 1, 0, 1));
const validTo = ymd(new Date(year.getFullYear() + 2, 0, 1));

const carerMobile = mobile();
const add = await call('POST', '/providers/employees', {
  token: ORG,
  body: {
    name: 'Test Carer One',
    gender: 'female',
    mobile: carerMobile,
    dob: '1990-05-12',
    address: { line1: '12th Lane, Paldi', city: 'Ahmedabad' },
    aadharDocUrl: '/uploads/aadhar/carer-one.png',
    policeVerificationUrl: '/uploads/police-verification/carer-one.png',
    policeVerificationValidFrom: validFrom,
    policeVerificationValidTo: validTo,
    expertise: [{ serviceType: 'companion' }],
    workHours: [{ dayOfWeek: 'mon', startTime: '09:00:00', endTime: '17:00:00' }],
  },
});
mark(add.status === 201, `added -> ${add.status} ${add.status !== 201 ? JSON.stringify(add.json).slice(0, 200) : ''}`);

const list = await call('GET', '/providers/employees', { token: ORG });
const carer = (list.json.employees ?? []).find((e) => `${e.mobileNumber}` === carerMobile);
mark(!!carer, 'and appears on the staff list');
mark(carer && carer.aadharDocUrl === '/uploads/aadhar/carer-one.png',
  `their OWN Aadhaar is stored   got ${carer && JSON.stringify(carer.aadharDocUrl)}`);
mark(carer && carer.policeVerificationUrl === '/uploads/police-verification/carer-one.png',
  `their OWN police verification is stored   got ${carer && JSON.stringify(carer.policeVerificationUrl)}`);
mark(carer && !!carer.policeVerificationValidTo,
  'with the dates it is valid between');
mark(carer && carer.dob != null, 'and their date of birth');

// This organisation has not been approved itself yet, so nobody it adds can
// be allocated regardless of their papers.
mark(carer && carer.approvalStatus === 'pending',
  `a carer of an unapproved organisation is pending   got ${carer && carer.approvalStatus}`);

// ---- a carer added with nothing ------------------------------------------
console.log('\nA carer added with no documents:');
const bareMobile = mobile();
const bare = await call('POST', '/providers/employees', {
  token: ORG,
  body: { name: 'Test Carer Two', gender: 'male', mobile: bareMobile, address: { line1: 'Somewhere' } },
});
mark(bare.status === 201, `is still created -> ${bare.status}`);
const list2 = await call('GET', '/providers/employees', { token: ORG });
const bareCarer = (list2.json.employees ?? []).find((e) => `${e.mobileNumber}` === bareMobile);
mark(bareCarer && !bareCarer.aadharDocUrl && !bareCarer.policeVerificationUrl,
  'but with no documents on the record, which the app reads to mark them unallocatable');
mark(bareCarer && bareCarer.approvalStatus === 'pending', 'and pending, like any other');

// ---- the gate is the documents, not a person -----------------------------
//
// Once the organisation itself is approved, a carer WITH papers can be
// allocated the same day and a carer WITHOUT them still cannot. Making every
// carer wait for an administrator instead would put a human in the middle of
// every hire at an agency that has already been checked -- and it broke
// allocate/reallocate in the audit suite, which is how this came up.
console.log('\nOnce the organisation is approved:');

const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? 'Admin@123';
const AT = (await call('POST', '/auth/admin/login', {
  body: { email: 'admin@sathiyaa.com', password: ADMIN_PASSWORD },
})).json.token;
mark(!!AT, 'admin signed in');

const orgRow = (await call('GET', '/admin/providers?status=all', { token: AT })).json;
const orgRecord = (orgRow.providers ?? orgRow ?? []).find(
  (p) => `${p.mobileNumber ?? p.mobile_number}` === orgMobile);
mark(!!orgRecord, 'the organisation is on the admin list');

if (orgRecord) {
  const approve = await call('POST',
    `/admin/providers/${orgRecord.providerId ?? orgRecord.provider_id}/approve`,
    { token: AT });
  mark(approve.status === 200, `approved -> ${approve.status} ${approve.status !== 200 ? JSON.stringify(approve.json).slice(0, 160) : ''}`);

  const withPapers = mobile();
  await call('POST', '/providers/employees', {
    token: ORG,
    body: {
      name: 'Test Carer Three',
      gender: 'female',
      mobile: withPapers,
      address: { line1: 'Indiranagar' },
      aadharDocUrl: '/uploads/aadhar/carer-three.png',
      policeVerificationUrl: '/uploads/police-verification/carer-three.png',
      policeVerificationValidFrom: validFrom,
      policeVerificationValidTo: validTo,
    },
  });
  const withoutPapers = mobile();
  await call('POST', '/providers/employees', {
    token: ORG,
    body: { name: 'Test Carer Four', gender: 'male', mobile: withoutPapers, address: { line1: 'Indiranagar' } },
  });

  const list3 = (await call('GET', '/providers/employees', { token: ORG })).json.employees ?? [];
  const ok = list3.find((e) => `${e.mobileNumber}` === withPapers);
  const notOk = list3.find((e) => `${e.mobileNumber}` === withoutPapers);

  // Both pending, and for different reasons -- which is the point of
  // reporting documentsComplete separately. One of these waits is the
  // organisation's to fix and the other is ours.
  mark(ok && ok.approvalStatus === 'pending',
    `a carer WITH documents waits for Sathiyaa to check them   got ${ok && ok.approvalStatus}`);
  mark(ok && ok.documentsComplete === true,
    `and the org is told the wait is ours, not theirs   got ${ok && ok.documentsComplete}`);
  mark(notOk && notOk.approvalStatus === 'pending',
    `a carer WITHOUT documents also waits   got ${notOk && notOk.approvalStatus}`);
  mark(notOk && notOk.documentsComplete === false,
    `and that one IS theirs to fix   got ${notOk && notOk.documentsComplete}`);

  // And adding the missing papers later is enough on its own.
  const promote = await call('PUT', `/providers/employees/${notOk.providerId ?? notOk.provider_id}`, {
    token: ORG,
    body: {
      aadharDocUrl: '/uploads/aadhar/carer-four.png',
      policeVerificationUrl: '/uploads/police-verification/carer-four.png',
      policeVerificationValidFrom: validFrom,
      policeVerificationValidTo: validTo,
    },
  });
  mark(promote.status === 200, `documents added later -> ${promote.status}`);
  const list4 = (await call('GET', '/providers/employees', { token: ORG })).json.employees ?? [];
  const promoted = list4.find((e) => `${e.mobileNumber}` === withoutPapers);
  mark(promoted && promoted.approvalStatus === 'pending',
    `and uploading them does NOT approve anybody   got ${promoted && promoted.approvalStatus}`);
  mark(promoted && promoted.documentsComplete === true,
    `it only means Sathiyaa now has something to look at   got ${promoted && promoted.documentsComplete}`);

  // The approval that works is an administrator's.
  const approved = await call('POST', `/admin/providers/${promoted.providerId ?? promoted.provider_id}/approve`, {
    token: AT, body: { notes: 'checked' },
  });
  mark(approved.status === 200, `an admin approves the carer -> ${approved.status}`);
  const list4b = (await call('GET', '/providers/employees', { token: ORG })).json.employees ?? [];
  const verified = list4b.find((e) => `${e.mobileNumber}` === withoutPapers);
  mark(verified && verified.approvalStatus === 'approved',
    `and only then are they verified   got ${verified && verified.approvalStatus}`);

  // An expired police verification is not a police verification.
  const expiredMobile = mobile();
  await call('POST', '/providers/employees', {
    token: ORG,
    body: {
      name: 'Test Carer Five',
      gender: 'female',
      mobile: expiredMobile,
      address: { line1: 'Indiranagar' },
      aadharDocUrl: '/uploads/aadhar/carer-five.png',
      policeVerificationUrl: '/uploads/police-verification/carer-five.png',
      policeVerificationValidFrom: ymd(new Date(year.getFullYear() - 3, 0, 1)),
      policeVerificationValidTo: ymd(new Date(year.getFullYear() - 1, 0, 1)),
    },
  });
  const list5 = (await call('GET', '/providers/employees', { token: ORG })).json.employees ?? [];
  const expired = list5.find((e) => `${e.mobileNumber}` === expiredMobile);
  mark(expired && expired.approvalStatus === 'pending',
    `an expired police check does not count as one   got ${expired && expired.approvalStatus}`);
}

// ---- a customer registering leaves no invented data ----------------------
console.log('\nA new customer, before they have filled anything in:');
const custMobile = `96${Date.now().toString().slice(-8)}`;
const creg = await call('POST', '/auth/customer/register', {
  body: { name: 'Sentinel Probe', mobile: custMobile },
});
mark(creg.status === 200 || creg.status === 201, `registered -> ${creg.status}`);
const CT = (await call('POST', '/auth/customer/verify-otp', {
  body: { mobile: custMobile, otp: creg.json.devOtp },
})).json.token;
const cme = await call('GET', '/customers/me', { token: CT });
// Registration used to fill the NOT NULL columns with '1970-01-01', 'other'
// and '', and the app read them straight back into the profile form -- so
// every new customer's date of birth was pre-filled as 1 Jan 1970.
mark(cme.json.dob == null, `date of birth is empty, not 1970-01-01   got ${JSON.stringify(cme.json.dob)}`);
mark(cme.json.gender == null, `gender is empty, not "other"   got ${JSON.stringify(cme.json.gender)}`);
mark(cme.json.photoUrl == null,
  `photo is null, not an empty string   got ${JSON.stringify(cme.json.photoUrl)}`);

console.log('\n' + (failures === 0 ? 'all checks passed' : `${failures} FAILURES`));
process.exit(failures === 0 ? 0 : 1);
