/**
 * Seed script: realistic sample data for local dev / demoing / smoke
 * testing. Idempotent-ish: clears dependent rows first (in FK-safe
 * order) then re-inserts, so it's safe to run repeatedly.
 *
 * Usage: npm run seed
 */
import bcrypt from 'bcryptjs';
import { pool, query, withTransaction } from './pool.js';
import { displayId, bookingDisplayId } from '../utils/ids.js';
import { env } from '../config/env.js';

const SERVICE_TYPES = ['companion', 'medical_companion', 'nurse', 'physiotherapy'];

async function truncateAll() {
  console.log('[seed] clearing existing data...');
  // Anything the seed writes has to be cleared, or a second `npm run seed`
  // fails on a duplicate key. The six tables in the second group arrived with
  // migrations 003-005 and were missed here, which is exactly how that broke.
  //
  // The three in the last group are worse than a duplicate key if they are
  // missed. Foreign key checks are off below, so truncating `bookings` and
  // `customers` while leaving these behind succeeds and leaves rows pointing at
  // ids that no longer exist — and the re-insert starts again at 1, so a stale
  // emergency alert re-attaches itself to whichever customer happens to land on
  // that id. Silent, and wrong in the worst possible place.
  const tables = [
    'audit_log', 'otp_log', 'masked_call_sessions', 'ratings', 'booking_cancellations',
    'booking_service_sessions', 'booking_transfers', 'booking_requests',
    // added by migrations 008-011; before `bookings`, which they point at
    'booking_messages', 'sos_alerts', 'user_devices',
    'bookings',
    'transactions', 'business_agent_referrals', 'business_agents',
    'service_provider_calendar_blocks', 'service_provider_expertise', 'service_provider_work_hours',
    'service_provider_addresses', 'service_providers',
    'customer_family_members', 'customer_insurance', 'customer_allergies', 'customer_surgeries',
    'customer_medications', 'customer_vitals', 'customer_addresses', 'customers',
    'broadcast_messages', 'revenue_sharing_config', 'app_configuration', 'admin_users',
    // added by migrations 003-005
    'customer_ratings', 'customer_provider_links', 'booking_payments',
    'time_bank_ledger', 'time_bank_config', 'organization_service_fees',
  ];
  const conn = await pool.getConnection();
  try {
    await conn.query('SET FOREIGN_KEY_CHECKS = 0');
    for (const t of tables) await conn.query(`TRUNCATE TABLE ${t}`);
    await conn.query('SET FOREIGN_KEY_CHECKS = 1');
  } finally {
    conn.release();
  }
}

async function seedAdmins() {
  console.log('[seed] admins...');
  // From the environment, so a deployment does not ship with the password
  // that is printed in this file and in every copy of the repository.
  const pw = await bcrypt.hash(env.admin.password, 10);
  await query(
    `INSERT INTO admin_users (name, email, password_hash, role) VALUES
      ('Super Admin', 'admin@sathiyaa.com', ?, 'super_admin'),
      ('Ops Admin', 'ops@sathiyaa.com', ?, 'ops_admin'),
      ('Support Admin', 'support@sathiyaa.com', ?, 'support')`,
    [pw, pw, pw]
  );
}

/**
 * Starting business numbers.
 *
 * These are working assumptions for urban India, not decisions — Admin can
 * change every one of them from the Configuration screen without a deploy.
 * The reasoning is written down so they can be argued with:
 *
 *  - **Booking charge, INR 99.** A commitment fee, taken to hold the slot,
 *    and the amount the cancellation tiers refund. Low enough not to deter a
 *    first booking, high enough that no-shows cost something.
 *  - **Customer annual fee, INR 499 new / 399 renewal.** A ~20% loyalty
 *    discount on renewal, which is the usual shape and easy to explain.
 *  - **Provider annual fee, INR 599 new / 499 renewal.** Deliberately lower
 *    than the customer fee, and lower than it was. In a two-sided
 *    marketplace supply is the scarce side; charging a caregiver a large fee
 *    before they have earned anything costs more in lost supply than it
 *    raises in fees.
 *  - **Organization markup, 20%.** Straight from the requirements doc's own
 *    worked example (INR 100/hr becomes INR 120/hr to the customer).
 */
async function seedConfig() {
  console.log('[seed] app_configuration...');
  const rows = [
    ['customer_booking_amount', '99', 'Upfront booking confirmation charge (INR), refundable per the cancellation tiers'],
    ['customer_annual_fee_new', '499', 'Annual registration fee for a new customer (INR)'],
    ['customer_annual_fee_existing', '399', 'Annual renewal fee for an existing customer (INR) — ~20% loyalty discount'],
    ['provider_annual_fee_new', '599', 'Annual registration fee for a new provider (INR) — kept low so the fee does not deter supply'],
    ['provider_annual_fee_existing', '499', 'Annual renewal fee for an existing provider (INR)'],
    ['org_revenue_share_percent', '20', "Sathiyaa's markup on top of an organization's own service fee (e.g. INR 100/hr + 20% shows as INR 120/hr to the customer). Freelancers are unaffected — they use revenue_sharing_config instead."],
  ];
  for (const [k, v, d] of rows) {
    await query('INSERT INTO app_configuration (config_key, config_value, description) VALUES (?, ?, ?)', [k, v, d]);
  }
}

/**
 * Points credited per donated hour to a "No Fees" provider, per service, per
 * year. The Companion and Medical Companion figures are the requirements
 * doc's own worked example; Nurse and Physiotherapy scale with the value of
 * the hour donated, so an hour of skilled care is worth more than an hour of
 * company.
 */
async function seedTimeBankConfig() {
  console.log('[seed] time_bank_config...');
  const year = new Date().getFullYear();
  const rows = [
    ['companion', 250],
    ['medical_companion', 300],
    ['nurse', 400],
    ['physiotherapy', 500],
  ];
  for (const [serviceType, pointsPerHour] of rows) {
    await query(
      'INSERT INTO time_bank_config (service_type, points_per_hour, application_year) VALUES (?, ?, ?)',
      [serviceType, pointsPerHour, year]
    );
  }
}

/**
 * Hourly economics per service type: what the customer pays, what the
 * freelance provider is paid, and the flat amount a Business Partner earns
 * per hour on a customer they referred.
 *
 * | Service           | Customer | Provider | Sathiyaa | Partner | Net w/ partner |
 * |-------------------|---------:|---------:|---------:|--------:|---------------:|
 * | Companion         |      200 |      150 |       50 |      20 |             30 |
 * | Medical Companion |      300 |      225 |       75 |      30 |             45 |
 * | Nurse             |      450 |      340 |      110 |      45 |             65 |
 * | Physiotherapy     |      600 |      450 |      150 |      60 |             90 |
 *
 * Why these:
 *
 *  - **Customer rates** are hourly on-demand rates, which sit above the
 *    per-hour cost of a monthly agency contract — a four-hour visit carries
 *    its own travel and idle time. Companion at INR 200/hr means a typical
 *    four-hour visit costs INR 800.
 *  - **Providers keep 75%.** That is in line with what comparable Indian
 *    services platforms pay, and it matters: at INR 150/hr, six hours a day,
 *    25 days, a companion takes home about INR 22,500 a month — more than
 *    agency-employed attendants earn, which is the reason to join.
 *  - **Business Partners get 10% of the customer rate**, so Sathiyaa still
 *    nets 15% on a referred booking.
 *
 * **This last point was a real problem in the previous numbers.** Companion
 * was 200/160/40: a Sathiyaa margin of 40 and a partner payout of 40, so
 * every partner-referred booking earned Sathiyaa exactly nothing, and the
 * more successful the partner channel became the worse it got. The
 * requirements doc's own example uses INR 20/hr for Companion, which is what
 * these rates now follow.
 */
async function seedRevenueSharing() {
  console.log('[seed] revenue_sharing_config...');
  const rows = [
    // [service, customer/hr, provider/hr, business-partner flat/hr]
    ['companion', 200, 150, 20],
    ['medical_companion', 300, 225, 30],
    ['nurse', 450, 340, 45],
    ['physiotherapy', 600, 450, 60],
  ];
  for (const [serviceType, customerRate, providerRate, bpRate] of rows) {
    await query(
      'INSERT INTO revenue_sharing_config (service_type, customer_rate_per_hour, provider_rate_per_hour, business_partner_flat_per_hour, effective_from) VALUES (?, ?, ?, ?, CURDATE() - INTERVAL 90 DAY)',
      [serviceType, customerRate, providerRate, bpRate]
    );
  }
}

/**
 * An initials avatar as a data URI.
 *
 * The seed used to point photo_url at picsum.photos, which meant every face in
 * the admin console needed the internet and broke without it. These are
 * generated, so the console looks the same offline as online.
 */
const AVATAR_INKS = ['#0f766e', '#7c3aed', '#b45309', '#be123c', '#1d4ed8', '#15803d', '#a21caf', '#0369a1'];

function avatarDataUri(name, index) {
  const initials = name
    .split(/\s+/)
    .slice(0, 2)
    .map((w) => w[0] ?? '')
    .join('')
    .toUpperCase();
  const bg = AVATAR_INKS[index % AVATAR_INKS.length];
  const svg =
    `<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128">` +
    `<rect width="128" height="128" rx="64" fill="${bg}"/>` +
    `<text x="50%" y="50%" dy="0.35em" text-anchor="middle" fill="#ffffff" ` +
    `font-family="Segoe UI,Roboto,sans-serif" font-size="52" font-weight="600">${initials}</text></svg>`;
  return `data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}`;
}

// Sathiyaa launches in Ahmedabad, so the seeded directory is in Ahmedabad.
// A demo database full of carers fifteen hundred kilometres from the app's
// default map pin is a search that finds nobody, which is indistinguishable
// from a broken product. Keep this in step with city_defaults.dart in both
// apps and with migration 015.
const AHMEDABAD = { lat: 23.0225, lng: 72.5714 };
function jitter(base, spreadKm = 8) {
  const deg = spreadKm / 111; // ~111km per degree
  return base + (Math.random() * 2 - 1) * deg;
}
// Ahmedabad first: CITIES[i % CITIES.length] is what scatters the tail of the
// directory, and the launch city should get the largest share of it.
const CITIES = ['Ahmedabad', 'Bengaluru', 'Chennai', 'Hyderabad', 'Pune'];

// Real city centres, so a pin dropped in the app lands on the right city and
// the distance shown beside a provider is a believable number rather than
// every provider being scattered around one city whatever their address says.
const CITY_PINS = {
  Bengaluru: { lat: 12.9716, lng: 77.5946 },
  Chennai: { lat: 13.0827, lng: 80.2707 },
  Hyderabad: { lat: 17.3850, lng: 78.4867 },
  Pune: { lat: 18.5204, lng: 73.8567 },
  Ahmedabad: { lat: 23.0225, lng: 72.5714 },
};

const STREETS = [
  'Ashram Road', 'CG Road', 'Paldi Cross Roads',
  'Navrangpura Circle', 'Vastrapur Lake Road', 'Satellite Road',
  'Bopal Main Road', 'Ellis Bridge', 'Naranpura Main Road',
  'Maninagar East',
];

async function seedCustomers() {
  console.log('[seed] customers...');
  // A directory worth looking at: the console's list, filters and search all
  // need enough rows to behave like they will in use.
  const names = [
    'Anita Rao', 'Suresh Kumar', 'Priya Nair', 'Ramesh Iyer', 'Lakshmi Menon',
    'Vikram Shah', 'Deepa Pillai', 'Arjun Reddy', 'Kavita Desai', 'Mohan Das',
    'Sarita Bhatt', 'Nitin Kulkarni', 'Rukmini Gowda', 'Farhan Qureshi', 'Ilaben Patel',
    'Joseph Mathew', 'Sneha Bansal', 'Devendra Rathore', 'Gayatri Subramanian', 'Anwar Ali',
  ];
  const genders = names.map((_, i) => (i % 2 === 0 ? 'female' : 'male'));
  const bloodGroups = ['A+', 'B+', 'O+', 'AB+', 'A-', 'O-', 'B-', 'AB-', 'unknown', 'O+',
                       'A+', 'O+', 'B+', 'AB+', 'O-', 'A-', 'B+', 'O+', 'AB-', 'A+'];
  const ids = [];

  for (let i = 0; i < names.length; i++) {
    const mobile = `9${(700000000 + i * 111).toString().padStart(9, '0')}`;
    const result = await query(
      `INSERT INTO customers (display_id, name, photo_url, dob, gender, blood_group, email, mobile_number,
         preferred_languages, height_cm, weight_kg, preferred_comm_mode, preferred_comm_timeframe,
         registration_fee_paid, status)
       VALUES ('PENDING', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, TRUE, 'active')`,
      [
        names[i], avatarDataUri(names[i], i), `19${40 + i}-0${(i % 9) + 1}-1${i % 9}`, genders[i], bloodGroups[i],
        `${names[i].toLowerCase().replace(' ', '.')}@example.com`, mobile,
        JSON.stringify(['en', i % 2 === 0 ? 'hi' : 'ta']), 150 + i, 55 + i,
        ['email', 'call', 'sms'][i % 3], '9am-12pm',
      ]
    );
    const id = result.insertId;
    await query('UPDATE customers SET display_id = ? WHERE customer_id = ?', [displayId('CUST', id), id]);
    // Not everyone is a happy active account — the directory's status tabs
    // need blocked and unpaid rows to be worth filtering.
    if (i === 8) await query("UPDATE customers SET status = 'blocked' WHERE customer_id = ?", [id]);
    if (i % 7 === 3) await query('UPDATE customers SET registration_fee_paid = FALSE WHERE customer_id = ?', [id]);
    ids.push(id);

    const city = CITIES[i % CITIES.length];
    await query(
      `INSERT INTO customer_addresses (customer_id, address_type, line1, city, state, pincode, latitude, longitude)
       VALUES (?, 'primary', ?, ?, 'Karnataka', '560001', ?, ?)`,
      [id, `${100 + i} Ashram Road`, city, jitter(AHMEDABAD.lat), jitter(AHMEDABAD.lng)]
    );

    await query('INSERT INTO customer_vitals (customer_id, vital_type, value_primary, value_secondary, recorded_at) VALUES (?, "bp", ?, ?, NOW() - INTERVAL 2 DAY)', [id, 120 + i, 80]);
    await query('INSERT INTO customer_vitals (customer_id, vital_type, value_primary, recorded_at) VALUES (?, "spo2", 97, NOW() - INTERVAL 1 DAY)', [id]);
    await query('INSERT INTO customer_vitals (customer_id, vital_type, value_primary, recorded_at) VALUES (?, "pulse", 72, NOW())', [id]);

    if (i % 3 === 0) {
      await query('INSERT INTO customer_medications (customer_id, medicine_name, frequency) VALUES (?, "Metformin", "twice daily")', [id]);
      await query('INSERT INTO customer_allergies (customer_id, allergy_name, status) VALUES (?, "Penicillin", "active")', [id]);
      await query('INSERT INTO customer_insurance (customer_id, insured_with, policy_number, start_date, end_date) VALUES (?, "Star Health", ?, CURDATE() - INTERVAL 1 YEAR, CURDATE() + INTERVAL 1 YEAR)', [id, `POL-${1000 + id}`]);
    }
    await query('INSERT INTO customer_family_members (customer_id, name, relationship, contact_number) VALUES (?, ?, "Spouse", ?)', [id, `Family of ${names[i]}`, `9${(800000000 + i).toString().padStart(9, '0')}`]);
  }
  return ids;
}

async function seedProviders() {
  console.log('[seed] service providers...');
  const providerIds = { freelancers: [], orgs: [], employees: [] };

  // Rates sit around the configured customer rate for each service (see
  // seedRevenueSharing). A spread of approval states gives the approval queue,
  // the Hold tab and the blocked filter something real to show.
  // A directory that looks like a real city rather than a test fixture: 30
  // freelancers, most of them in Ahmedabad so a search from the default pin
  // returns a full screen the way the reference build does, with the rest
  // spread over four other cities so the city filter has something to filter.
  //
  // rating and years are fixed per person rather than random, so the same
  // provider reads the same on every reseed and anything written down in a
  // demo script stays true the next day.
  // The roster. THE FIRST TWELVE ENTRIES ARE ORDER-SENSITIVE: each provider's
  // mobile number is derived from their index (9600000000 + i * 137), and
  // those numbers appear in THE-PRACTICAL.md and in the test scripts. Append
  // new people at the end; never insert or reorder above the marker.
  //
  // rating and years are fixed per person rather than random, so the same
  // provider reads the same on every reseed and anything written down during
  // a demo is still true the next day.
  const freelancerData = [
    // --- ORDER-SENSITIVE: do not reorder ---------------------------------
    { name: 'Meena Krishnan', gender: 'female', kind: 'freelancer', service: 'companion', rate: 200, years: 6, rating: 4.7, city: 'Ahmedabad' },          // 9600000000
    { name: 'Rajesh Verma', gender: 'male', kind: 'freelancer', service: 'medical_companion', rate: 300, years: 8, rating: 4.6, city: 'Ahmedabad' },      // 9600000137
    { name: 'Sunita Joshi', gender: 'female', kind: 'freelancer', service: 'nurse', rate: 450, years: 11, rating: 4.8, city: 'Ahmedabad' },               // 9600000274
    { name: 'Karthik Subramaniam', gender: 'male', kind: 'freelancer', service: 'physiotherapy', rate: 600, years: 9, rating: 4.5, city: 'Ahmedabad' },
    { name: 'Fatima Sheikh', gender: 'female', kind: 'freelancer', service: 'companion', rate: 190, years: 4, rating: 4.4, city: 'Ahmedabad' },
    { name: 'Ganesh Pillai', gender: 'male', kind: 'freelancer', service: 'nurse', rate: 430, years: 7, rating: 4.6, city: 'Ahmedabad' },
    { name: 'Rekha Sharma', gender: 'female', kind: 'freelancer', service: 'medical_companion', rate: 310, years: 10, rating: 4.8, city: 'Ahmedabad' },   // blocked, for the unblock action
    { name: 'Imran Khan', gender: 'male', kind: 'freelancer', service: 'physiotherapy', rate: 580, years: 6, rating: 4.3, city: 'Ahmedabad' },
    { name: 'Shalini Iyer', gender: 'female', kind: 'freelancer', service: 'companion', rate: 210, years: 5, rating: 4.7, city: 'Ahmedabad' },
    { name: 'Prakash Rane', gender: 'male', kind: 'freelancer', service: 'nurse', rate: 470, years: 13, rating: 4.9, city: 'Ahmedabad' },
    { name: 'Ayesha Begum', gender: 'female', kind: 'freelancer', service: 'companion', rate: 0, noFees: true, years: 3, rating: 4.8, city: 'Ahmedabad' },
    { name: 'Devraj Naidu', gender: 'male', kind: 'freelancer', service: 'medical_companion', rate: 295, years: 7, rating: 4.5, city: 'Ahmedabad' },
    // --- end order-sensitive block; append below --------------------------

    { name: 'Anjali Deshpande', gender: 'female', kind: 'freelancer', service: 'nurse', rate: 460, years: 12, rating: 4.9, city: 'Ahmedabad' },
    { name: 'Lakshmi Bhat', gender: 'female', kind: 'freelancer', service: 'nurse', rate: 440, years: 9, rating: 4.7, city: 'Ahmedabad' },
    { name: 'Sanjay Gowda', gender: 'male', kind: 'freelancer', service: 'companion', rate: 205, years: 3, rating: 4.2, city: 'Ahmedabad' },
    { name: 'Nirmala Shetty', gender: 'female', kind: 'freelancer', service: 'physiotherapy', rate: 620, years: 14, rating: 4.9, city: 'Ahmedabad' },
    { name: 'Vinod Kamath', gender: 'male', kind: 'freelancer', service: 'medical_companion', rate: 305, years: 8, rating: 4.6, city: 'Ahmedabad' },
    { name: 'Asha Menon', gender: 'female', kind: 'freelancer', service: 'companion', rate: 195, years: 5, rating: 4.5, city: 'Ahmedabad' },
    { name: 'Harish Nayak', gender: 'male', kind: 'freelancer', service: 'nurse', rate: 455, years: 10, rating: 4.7, city: 'Ahmedabad' },
    { name: 'Pooja Hegde', gender: 'female', kind: 'freelancer', service: 'physiotherapy', rate: 590, years: 7, rating: 4.6, city: 'Ahmedabad' },
    { name: 'Mahesh Acharya', gender: 'male', kind: 'freelancer', service: 'companion', rate: 215, years: 6, rating: 4.4, city: 'Ahmedabad' },
    { name: 'Savitri Rao', gender: 'female', kind: 'freelancer', service: 'medical_companion', rate: 298, years: 9, rating: 4.6, city: 'Ahmedabad' },
    { name: 'Arun Chandra', gender: 'male', kind: 'freelancer', service: 'nurse', rate: 465, years: 11, rating: 4.8, city: 'Ahmedabad' },
    { name: 'Geetha Prasad', gender: 'female', kind: 'freelancer', service: 'companion', rate: 198, years: 4, rating: 4.3, city: 'Ahmedabad' },

    // --- volunteers: no fee, hours credited to the Time Bank --------------
    { name: 'Rohit Malhotra', gender: 'male', kind: 'freelancer', service: 'companion', rate: 0, noFees: true, years: 2, rating: 4.6, city: 'Ahmedabad' },
    { name: 'Sneha Kulkarni', gender: 'female', kind: 'freelancer', service: 'medical_companion', rate: 0, noFees: true, years: 4, rating: 4.9, city: 'Ahmedabad' },
    { name: 'Aditya Rangan', gender: 'male', kind: 'freelancer', service: 'physiotherapy', rate: 0, noFees: true, years: 5, rating: 4.7, city: 'Ahmedabad' },

    // --- other cities, and the tail the approval queue draws from ---------
    { name: 'Padma Raghavan', gender: 'female', kind: 'freelancer', service: 'nurse', rate: 425, years: 11, rating: 4.8, city: 'Chennai' },
    { name: 'Suresh Balan', gender: 'male', kind: 'freelancer', service: 'companion', rate: 185, years: 4, rating: 4.3, city: 'Chennai' },
    { name: 'Kavya Reddy', gender: 'female', kind: 'freelancer', service: 'medical_companion', rate: 290, years: 6, rating: 4.5, city: 'Hyderabad' },
    { name: 'Farhan Ali', gender: 'male', kind: 'freelancer', service: 'nurse', rate: 410, years: 8, rating: 4.4, city: 'Hyderabad' },
    { name: 'Manisha Patil', gender: 'female', kind: 'freelancer', service: 'physiotherapy', rate: 560, years: 9, rating: 4.7, city: 'Pune' },
    { name: 'Jayesh Trivedi', gender: 'male', kind: 'freelancer', service: 'companion', rate: 180, years: 3, rating: 4.1, city: 'Ahmedabad' },
  ];

  for (let i = 0; i < freelancerData.length; i++) {
    const f = freelancerData[i];
    const mobile = `9${(600000000 + i * 137).toString().padStart(9, '0')}`;
    const pinHash = await bcrypt.hash('123456', 10);
    // Most approved, a couple awaiting review, one on hold, one rejected — so
    // every tab in the approval queue has rows.
    const approvalStatus =
      i === freelancerData.length - 1 ? 'pending'
      : i === freelancerData.length - 2 ? 'pending'
      : i === freelancerData.length - 3 ? 'hold'
      : i === freelancerData.length - 4 ? 'rejected'
      : 'approved';
    const result = await query(
      `INSERT INTO service_providers
        (display_id, provider_kind, name, photo_url, gender, dob, mobile_number, email, pin_hash, hourly_rate,
         languages, approval_status, approved_by, approved_at, status, registration_fee_paid, location_on,
         current_latitude, current_longitude, current_location_at, rating_avg, rating_count)
       VALUES ('PENDING', ?, ?, ?, ?, '1985-05-15', ?, ?, ?, ?, ?, ?, ?, ?, 'active', TRUE, TRUE, ?, ?, NOW(), ?, ?)`,
      [
        f.kind, f.name, avatarDataUri(f.name, i + 3), f.gender, mobile,
        `${f.name.toLowerCase().replace(' ', '.')}@example.com`, pinHash, f.rate,
        // The display names the apps use, not ISO codes. The matching query runs
        // JSON_CONTAINS(languages, JSON_QUOTE('Gujarati')) against this, so 'en'
        // and 'hi' matched no search anybody could actually run.
        JSON.stringify(['English', 'Hindi', 'Gujarati']), approvalStatus, approvalStatus === 'approved' ? 1 : null,
        approvalStatus === 'approved' ? new Date() : null,
        jitter(CITY_PINS[f.city].lat, 6), jitter(CITY_PINS[f.city].lng, 6), f.rating, 8 + ((i * 17) % 130),
      ]
    );
    const id = result.insertId;
    await query('UPDATE service_providers SET display_id = ? WHERE provider_id = ?', [displayId('SP', id), id]);
    if (f.noFees) await query('UPDATE service_providers SET no_fees = TRUE WHERE provider_id = ?', [id]);
    // A couple of blocked accounts, so the block/unblock action has a subject.
    if (i === 6) await query("UPDATE service_providers SET status = 'blocked' WHERE provider_id = ?", [id]);
    await query('INSERT INTO service_provider_expertise (provider_id, service_type, years_experience) VALUES (?, ?, ?)', [id, f.service, f.years]);
    // Several providers cover a second service, which is what makes the
    // expertise filter meaningful.
    if (i % 3 === 0) {
      const second = SERVICE_TYPES[(SERVICE_TYPES.indexOf(f.service) + 1) % SERVICE_TYPES.length];
      await query('INSERT IGNORE INTO service_provider_expertise (provider_id, service_type, years_experience) VALUES (?, ?, ?)', [id, second, 2]);
    }
    await query(
      `INSERT INTO service_provider_addresses (provider_id, address_type, line1, city, state, pincode, latitude, longitude)
       VALUES (?, 'home', ?, ?, 'Karnataka', '560001', ?, ?)`,
      [id, `${200 + i} ${STREETS[i % STREETS.length]}`, f.city, jitter(CITY_PINS[f.city].lat, 6), jitter(CITY_PINS[f.city].lng, 6)]
    );
    for (const dow of ['mon', 'tue', 'wed', 'thu', 'fri', 'sat']) {
      await query('INSERT INTO service_provider_work_hours (provider_id, day_of_week, start_time, end_time) VALUES (?, ?, "08:00:00", "20:00:00")', [id, dow]);
    }
    providerIds.freelancers.push({ id, ...f, approvalStatus });
  }

  // One organization + two employees under it
  const orgPinHash = await bcrypt.hash('123456', 10);
  const orgResult = await query(
    `INSERT INTO service_providers
      (display_id, provider_kind, name, gender, mobile_number, pin_hash, hourly_rate, approval_status, approved_by, approved_at, status, registration_fee_paid, location_on)
     VALUES ('PENDING', 'organization', 'CareWell Health Services', NULL, '9611122233', ?, 0, 'approved', 1, NOW(), 'active', TRUE, FALSE)`,
    [orgPinHash]
  );
  const orgId = orgResult.insertId;
  await query('UPDATE service_providers SET display_id = ? WHERE provider_id = ?', [displayId('SP', orgId), orgId]);
  providerIds.orgs.push(orgId);

  const employeeData = [
    { name: 'Divya Prakash', gender: 'female', service: 'nurse', rate: 400 },
    { name: 'Naveen Kumar', gender: 'male', service: 'companion', rate: 220 },
  ];
  for (let i = 0; i < employeeData.length; i++) {
    const e = employeeData[i];
    const mobile = `9${(500000000 + i * 191).toString().padStart(9, '0')}`;
    const pinHash = await bcrypt.hash('654321', 10);
    const result = await query(
      `INSERT INTO service_providers
        (display_id, provider_kind, organization_id, name, gender, mobile_number, pin_hash, hourly_rate,
         approval_status, approved_by, approved_at, status, registration_fee_paid, location_on, current_latitude, current_longitude, current_location_at)
       VALUES ('PENDING', 'org_employee', ?, ?, ?, ?, ?, ?, 'approved', 1, NOW(), 'active', TRUE, TRUE, ?, ?, NOW())`,
      [orgId, e.name, e.gender, mobile, pinHash, e.rate, jitter(AHMEDABAD.lat, 5), jitter(AHMEDABAD.lng, 5)]
    );
    const id = result.insertId;
    await query('UPDATE service_providers SET display_id = ? WHERE provider_id = ?', [displayId('SP', id), id]);
    await query('INSERT INTO service_provider_expertise (provider_id, service_type, years_experience) VALUES (?, ?, ?)', [id, e.service, 2 + i]);
    await query(
      `INSERT INTO service_provider_addresses (provider_id, address_type, line1, city, state, pincode, latitude, longitude)
       VALUES (?, 'home', ?, ?, 'Karnataka', '560001', ?, ?)`,
      [id, `${300 + i} SG Highway`, CITIES[i % CITIES.length], jitter(AHMEDABAD.lat, 5), jitter(AHMEDABAD.lng, 5)]
    );
    for (const dow of ['mon', 'tue', 'wed', 'thu', 'fri']) {
      await query('INSERT INTO service_provider_work_hours (provider_id, day_of_week, start_time, end_time) VALUES (?, ?, "09:00:00", "18:00:00")', [id, dow]);
    }
    providerIds.employees.push({ id, ...e });
  }

  return providerIds;
}

async function seedBusinessAgents() {
  console.log('[seed] business agents...');
  // Referral codes are fixed here rather than generated.
  //
  // A partner created through the admin console gets a random code, which is
  // right -- codes have to be unique and not guessable from the name. But the
  // seeded three are credentials somebody writes down, and a fresh code on
  // every reseed silently invalidates whatever was noted last week. Signing in
  // then fails with "no account found", which reads like a broken login rather
  // than a stale code.
  const agents = [
    { entity: 'Apollo Diagnostics', partner: 'Vinod Menon', contact: '9800000001', code: 'APOL1001' },
    { entity: 'Fortis Referral Desk', partner: 'Shalini Rao', contact: '9800000002', code: 'FORT1002' },
    { entity: 'Manipal Care Partners', partner: 'Arvind Nair', contact: '9800000003', code: 'MANI1003' },
  ];
  const ids = [];
  for (const a of agents) {
    const pw = await bcrypt.hash('Partner@123', 10);
    const code = a.code;
    const result = await query(
      `INSERT INTO business_agents (display_id, entity_name, partner_name, contact_number_1, email, password_hash, referral_code, status)
       VALUES ('PENDING', ?, ?, ?, ?, ?, ?, 'active')`,
      [a.entity, a.partner, a.contact, `${a.partner.toLowerCase().replace(' ', '.')}@partner.com`, pw, code]
    );
    const id = result.insertId;
    await query('UPDATE business_agents SET display_id = ? WHERE business_partner_id = ?', [displayId('BP', id), id]);
    ids.push({ id, code, entity: a.entity, displayId: displayId('BP', id), contact: a.contact });
  }
  return ids;
}

async function seedBookings(customerIds, providers, agents) {
  console.log('[seed] bookings across statuses...');
  const freelancers = providers.freelancers.filter((p) => p.approvalStatus === 'approved');
  const today = new Date();
  // Local calendar dates, so seeded bookings land on the days their
  // labels claim rather than slipping back one overnight.
  const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  const addDays = (n) => { const d = new Date(today); d.setDate(d.getDate() + n); return d; };

  // 1) COMPLETED booking (past), rated
  await createFullBooking({
    customerId: customerIds[0], provider: freelancers[0], serviceType: freelancers[0].service,
    startDate: iso(addDays(-5)), endDate: iso(addDays(-5)), timeFrom: '09:00:00', timeTo: '13:00:00',
    finalStatus: 'completed', rate: true,
  });

  // 2) COMPLETED multi-day booking (amounts accumulate across 2 days)
  await createFullBooking({
    customerId: customerIds[1], provider: freelancers[2], serviceType: freelancers[2].service,
    startDate: iso(addDays(-3)), endDate: iso(addDays(-2)), timeFrom: '08:00:00', timeTo: '12:00:00',
    finalStatus: 'completed', rate: true, multiDay: true,
  });

  // 3) CANCELLED booking (>=36h before start -> full refund tier, for historical record)
  await createFullBooking({
    customerId: customerIds[2], provider: freelancers[1], serviceType: freelancers[1].service,
    startDate: iso(addDays(10)), endDate: iso(addDays(10)), timeFrom: '10:00:00', timeTo: '14:00:00',
    finalStatus: 'cancelled',
  });

  // 4) CONFIRMED, upcoming (future, paid, not started)
  await createFullBooking({
    customerId: customerIds[3], provider: freelancers[3], serviceType: freelancers[3].service,
    startDate: iso(addDays(3)), endDate: iso(addDays(3)), timeFrom: '15:00:00', timeTo: '18:00:00',
    finalStatus: 'confirmed',
  });

  // 5) IN_PROGRESS (started today, not ended)
  await createFullBooking({
    customerId: customerIds[4], provider: freelancers[0], serviceType: freelancers[0].service,
    startDate: iso(today), endDate: iso(today), timeFrom: '07:00:00', timeTo: '11:00:00',
    finalStatus: 'in_progress',
  });

  // 6) SEARCHING (just created, request fan-out sent, nobody accepted yet)
  await createFullBooking({
    customerId: customerIds[5], provider: freelancers[1], serviceType: freelancers[1].service,
    startDate: iso(addDays(7)), endDate: iso(addDays(7)), timeFrom: '09:00:00', timeTo: '12:00:00',
    finalStatus: 'searching',
  });

  // 7) PENDING_PAYMENT (provider accepted, 15-min window open)
  await createFullBooking({
    customerId: customerIds[6], provider: freelancers[2], serviceType: freelancers[2].service,
    startDate: iso(addDays(4)), endDate: iso(addDays(4)), timeFrom: '13:00:00', timeTo: '17:00:00',
    finalStatus: 'pending_payment',
  });

  // 8) EXPIRED (payment window lapsed)
  await createFullBooking({
    customerId: customerIds[7], provider: freelancers[3], serviceType: freelancers[3].service,
    startDate: iso(addDays(2)), endDate: iso(addDays(2)), timeFrom: '09:00:00', timeTo: '11:00:00',
    finalStatus: 'expired',
  });

  // 9) Booking tied to a business-agent referral code, completed (so /revenue has data)
  await createFullBooking({
    customerId: customerIds[8], provider: freelancers[2], serviceType: freelancers[2].service,
    startDate: iso(addDays(-1)), endDate: iso(addDays(-1)), timeFrom: '08:00:00', timeTo: '12:00:00',
    finalStatus: 'completed', rate: true, referralCode: agents[0].code,
  });
  await query(
    `INSERT INTO business_agent_referrals (business_partner_id, customer_id, customer_name, gender, service_type, duration_start, duration_end, time_from, time_to, mobile_number, address, status)
     VALUES (?, ?, 'Kavita Desai', 'female', 'nurse', ?, ?, '08:00:00', '12:00:00', '9700000811', '108 Ashram Road, Ahmedabad', 'booked')`,
    [agents[0].id, customerIds[8], iso(addDays(-1)), iso(addDays(-1))]
  );
  await query(
    `INSERT INTO business_agent_referrals (business_partner_id, customer_name, gender, service_type, duration_start, duration_end, time_from, time_to, mobile_number, address, status)
     VALUES (?, 'Walk-in Prospect', 'male', 'companion', ?, ?, '09:00:00', '13:00:00', '9800099001', 'CG Road, Ahmedabad', 'pending')`,
    [agents[1].id, iso(addDays(5)), iso(addDays(5))]
  );
}

async function createFullBooking({ customerId, provider, serviceType, startDate, endDate, timeFrom, timeTo, finalStatus, rate = false, multiDay = false, referralCode = null }) {
  return withTransaction(async (conn) => {
    const [addrRows] = await conn.query('SELECT * FROM customer_addresses WHERE customer_id = ? AND address_type = "primary"', [customerId]);
    const addr = addrRows[0];
    const bookingChargeAmount = 99;

    const wantsRequestOnly = finalStatus === 'searching';
    const status = wantsRequestOnly ? 'searching' : finalStatus === 'expired' ? 'pending_payment' : finalStatus === 'pending_payment' ? 'pending_payment' : finalStatus;
    const confirmedProviderId = wantsRequestOnly ? null : provider.id;
    const chargePaid = !['searching', 'pending_payment', 'expired'].includes(finalStatus);
    const paymentDeadline = finalStatus === 'pending_payment' ? new Date(Date.now() + 15 * 60 * 1000) : finalStatus === 'expired' ? new Date(Date.now() - 5 * 60 * 1000) : null;

    const [result] = await conn.query(
      `INSERT INTO bookings (display_id, customer_id, service_type, address_id, latitude, longitude, start_date, end_date, time_from, time_to,
         gender_preference, referral_code, status, confirmed_provider_id, booking_charge_amount, booking_charge_paid, payment_deadline_at)
       VALUES ('PENDING', ?, ?, ?, ?, ?, ?, ?, ?, ?, 'any', ?, ?, ?, ?, ?, ?)`,
      [customerId, serviceType, addr?.id || null, addr?.latitude || null, addr?.longitude || null, startDate, endDate, timeFrom, timeTo, referralCode, status, confirmedProviderId, bookingChargeAmount, chargePaid, paymentDeadline]
    );
    const bookingId = result.insertId;
    await conn.query('UPDATE bookings SET display_id = ? WHERE booking_id = ?', [bookingDisplayId(bookingId), bookingId]);

    // fan out a request to the chosen provider (+ accepted/paid txn where relevant)
    const reqStatus = wantsRequestOnly ? 'pending' : finalStatus === 'expired' ? 'invalidated' : 'accepted';
    await conn.query('INSERT INTO booking_requests (booking_id, provider_id, status, responded_at) VALUES (?, ?, ?, ?)', [
      bookingId, provider.id, reqStatus, wantsRequestOnly ? null : new Date(),
    ]);

    if (chargePaid) {
      const [txnResult] = await conn.query(
        `INSERT INTO transactions (transaction_type, reference_type, reference_id, amount, gateway, gateway_ref_id, status)
         VALUES ('booking_charge', 'booking', ?, ?, 'mock_gateway', ?, 'success')`,
        [bookingId, bookingChargeAmount, `seed_pay_${bookingId}`]
      );
      await conn.query('UPDATE bookings SET booking_charge_txn_id = ? WHERE booking_id = ?', [txnResult.insertId, bookingId]);
    }

    if (['completed', 'in_progress'].includes(finalStatus)) {
      const days = multiDay ? [startDate, endDate] : [startDate];
      for (const day of days) {
        const isOpenSession = finalStatus === 'in_progress' && day === days[days.length - 1];
        const startActual = new Date(`${day}T${timeFrom}`);
        const endActual = new Date(`${day}T${timeTo}`);
        const hours = isOpenSession ? null : Math.round(((endActual - startActual) / 3600000) * 100) / 100;
        const rsc = await conn.query('SELECT provider_rate_per_hour FROM revenue_sharing_config WHERE service_type = ? ORDER BY effective_from DESC LIMIT 1', [serviceType]);
        const rate_ = rsc[0][0]?.provider_rate_per_hour || 0;
        const amount = hours ? Math.round(hours * rate_ * 100) / 100 : null;

        await conn.query(
          `INSERT INTO booking_service_sessions (booking_id, provider_id, session_date, otp_code, otp_verified_at, facial_recognition_verified, start_time_actual, end_time_actual, total_hours, amount)
           VALUES (?, ?, ?, '000000', ?, TRUE, ?, ?, ?, ?)`,
          [bookingId, provider.id, day, isOpenSession ? null : startActual, isOpenSession ? new Date() : startActual, isOpenSession ? null : endActual, hours, amount]
        );
      }
    }

    if (finalStatus === 'cancelled') {
      await conn.query(
        `INSERT INTO booking_cancellations (booking_id, cancelled_by_type, cancelled_by_id, reason, hours_before_start, cancellation_fee_amount, refund_amount)
         VALUES (?, 'customer', ?, 'Change of plans', 240, 0, ?)`,
        [bookingId, customerId, bookingChargeAmount]
      );
      await conn.query('UPDATE booking_requests SET status = "invalidated" WHERE booking_id = ? AND status != "accepted"', [bookingId]);
    }

    if (rate) {
      await conn.query('INSERT INTO ratings (booking_id, customer_id, provider_id, rating, comments) VALUES (?, ?, ?, ?, ?)', [
        bookingId, customerId, provider.id, 4 + (bookingId % 2), 'Great service, very professional and on time.',
      ]);
      const [[agg]] = await conn.query('SELECT AVG(rating) AS a, COUNT(*) AS c FROM ratings WHERE provider_id = ?', [provider.id]);
      await conn.query('UPDATE service_providers SET rating_avg = ?, rating_count = ? WHERE provider_id = ?', [Math.round(agg.a * 100) / 100, agg.c, provider.id]);
    }

    return bookingId;
  });
}

async function run() {
  await truncateAll();
  await seedAdmins();
  await seedConfig();
  await seedRevenueSharing();
  await seedTimeBankConfig();
  const customerIds = await seedCustomers();
  const providers = await seedProviders();
  const agents = await seedBusinessAgents();
  await seedBookings(customerIds, providers, agents);

  console.log('[seed] done.');
  console.log('[seed] --- credentials for smoke testing ---');
  console.log(`[seed] admin login:        ${env.admin.email} / ` +
    (process.env.ADMIN_PASSWORD ? '(from ADMIN_PASSWORD)' : 'Admin@123  <-- change this before deploying'));
  console.log(`[seed] customer mobile:    9700000000 (name: Anita Rao) — OTP flow, use devOtp in response`);
  console.log(`[seed] provider login:     mobile 9600000000 (Meena Krishnan), PIN 123456`);
  console.log(`[seed] org head login:     mobile 9611122233 (CareWell Health Services), PIN 123456`);
  console.log('[seed] business partners:   password Partner@123 for all three; sign in with any of these');
  for (const a of agents) {
    console.log(`[seed]                      ${a.entity.padEnd(24)} ${a.displayId}  ${a.contact}  ${a.code}`);
  }
  await pool.end();
}

run().catch((err) => {
  console.error('[seed] failed:', err);
  process.exit(1);
});
