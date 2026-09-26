// Deterministic, realistic mock data used by the mock adapter (src/api/mockAdapter.ts)
// when VITE_USE_MOCK=true. Shapes mirror docs/api-contract.md + docs/schema.sql.

import type {
  ServiceProvider, Customer, BusinessAgent, BusinessAgentReferral,
  AppConfiguration, RevenueSharingConfig, TimeBankConfig, BroadcastMessage, AuditLogEntry,
  ServiceType, DayOfWeek, ProviderTrackingEntry, ReportsDashboard, GrowthReport,
  GrowthPeriod, ApprovalStatus,
  UserDevice, DeviceUserType,
} from '../types';
import { avatarDataUri, documentDataUri, bannerDataUri } from '../utils/placeholder';

const CITIES = ['Chennai', 'Coimbatore', 'Madurai', 'Bengaluru', 'Hyderabad', 'Trichy'];
const SERVICE_TYPES: ServiceType[] = ['companion', 'medical_companion', 'nurse', 'physiotherapy'];
const DAYS: DayOfWeek[] = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

function seededRandom(seed: number) {
  let s = seed;
  return () => {
    s = (s * 9301 + 49297) % 233280;
    return s / 233280;
  };
}
const rnd = seededRandom(42);
function pick<T>(arr: T[]): T {
  return arr[Math.floor(rnd() * arr.length)];
}
function randInt(min: number, max: number) {
  return Math.floor(rnd() * (max - min + 1)) + min;
}
function daysAgoISO(n: number) {
  const d = new Date();
  d.setDate(d.getDate() - n);
  return d.toISOString();
}
function dateOnly(iso: string) {
  return iso.slice(0, 10);
}

// ---------------------------------------------------------------------
// Service Providers
// ---------------------------------------------------------------------

const FIRST_NAMES_M = ['Ravi', 'Suresh', 'Karthik', 'Arun', 'Vijay', 'Mohan', 'Prakash', 'Senthil', 'Dinesh', 'Bala'];
const FIRST_NAMES_F = ['Lakshmi', 'Priya', 'Kavitha', 'Meena', 'Divya', 'Anitha', 'Deepa', 'Shanthi', 'Revathi', 'Uma'];
const LAST_NAMES = ['Kumar', 'Raman', 'Murugan', 'Iyer', 'Nair', 'Pillai', 'Rajan', 'Subramaniam', 'Chandran', 'Krishnan'];

function makeProviderName(gender: 'male' | 'female'): string {
  const first = gender === 'male' ? pick(FIRST_NAMES_M) : pick(FIRST_NAMES_F);
  return `${first} ${pick(LAST_NAMES)}`;
}

const APPROVAL_STATUSES: ApprovalStatus[] = ['pending', 'approved', 'approved', 'approved', 'hold', 'rejected', 'approved'];

function buildProvider(id: number): ServiceProvider {
  const gender: 'male' | 'female' = rnd() > 0.45 ? 'female' : 'male';
  const name = makeProviderName(gender);
  const approval_status = APPROVAL_STATUSES[id % APPROVAL_STATUSES.length];
  const status = rnd() > 0.9 && approval_status === 'approved' ? 'blocked' : 'active';
  const city = pick(CITIES);
  const numExpertise = randInt(1, 2);
  const expertiseTypes = [...SERVICE_TYPES].sort(() => rnd() - 0.5).slice(0, numExpertise);
  const workDays = DAYS.filter(() => rnd() > 0.25);
  const createdDaysAgo = randInt(2, 220);
  const lat = 12.9 + rnd() * 0.5 - 0.25 + (CITIES.indexOf(city) * 0.05);
  const lng = 80.1 + rnd() * 0.5 - 0.25 + (CITIES.indexOf(city) * 0.05);
  const locationOn = status === 'active' && approval_status === 'approved' && rnd() > 0.25;

  return {
    provider_id: id,
    display_id: `SP-${String(id).padStart(6, '0')}`,
    provider_kind: rnd() > 0.85 ? 'organization' : 'freelancer',
    organization_id: null,
    name,
    photo_url: avatarDataUri(name, `sp-${id}`),
    gender,
    dob: `19${60 + randInt(0, 35)}-0${randInt(1, 9)}-1${randInt(0, 9)}`,
    mobile_number: `9${randInt(100000000, 999999999)}`,
    email: `${name.toLowerCase().replace(' ', '.')}${id}@example.com`,
    hourly_rate: [140, 160, 180, 200, 220, 250][randInt(0, 5)],
    aadhar_doc_url: documentDataUri('Aadhar Card', id),
    police_verification_url: documentDataUri('Police Verification', id),
    work_certificate_url: documentDataUri('Work Certificate', id),
    approval_status,
    approval_notes: approval_status === 'hold'
      ? 'Police verification document is blurred — please re-upload a clearer scan.'
      : approval_status === 'rejected'
      ? 'Work certificate does not match declared expertise.'
      : null,
    approved_by: approval_status === 'approved' ? 1 : null,
    approved_at: approval_status === 'approved' ? daysAgoISO(createdDaysAgo - 1) : null,
    status,
    registration_fee_paid: approval_status !== 'pending',
    device_id: approval_status === 'approved' ? `DEV-${String(id).padStart(6, '0')}` : null,
    location_on: locationOn,
    current_latitude: locationOn ? Number(lat.toFixed(6)) : null,
    current_longitude: locationOn ? Number(lng.toFixed(6)) : null,
    current_location_at: locationOn ? daysAgoISO(0) : null,
    distance_from_home_pref_km: [5, 8, 10, 15, 20][randInt(0, 4)],
    distance_from_office_pref_km: [5, 8, 10, 15][randInt(0, 3)],
    rating_avg: approval_status === 'approved' ? Number((3.5 + rnd() * 1.5).toFixed(1)) : 0,
    rating_count: approval_status === 'approved' ? randInt(0, 140) : 0,
    created_at: daysAgoISO(createdDaysAgo),
    addresses: [
      {
        address_type: 'home',
        line1: `${randInt(1, 200)}, ${pick(['Anna Nagar', 'T Nagar', 'Adyar', 'Velachery', 'Gandhipuram', 'RS Puram'])}`,
        line2: null,
        city,
        state: 'Tamil Nadu',
        pincode: `6${randInt(0, 99999)}`.padEnd(6, '0').slice(0, 6),
        latitude: lat,
        longitude: lng,
      },
    ],
    work_hours: workDays.map((d) => ({
      day_of_week: d,
      start_time: pick(['07:00', '08:00', '09:00']),
      end_time: pick(['17:00', '18:00', '20:00', '21:00']),
    })),
    expertise: expertiseTypes.map((st) => ({
      service_type: st,
      years_experience: Number((rnd() * 12 + 0.5).toFixed(1)),
      notes: null,
    })),
  };
}

export const MOCK_PROVIDERS: ServiceProvider[] = Array.from({ length: 14 }, (_, i) => buildProvider(i + 1));

// Ensure a clean spread across statuses regardless of RNG luck.
MOCK_PROVIDERS[0].approval_status = 'pending';
MOCK_PROVIDERS[0].registration_fee_paid = false;
MOCK_PROVIDERS[1].approval_status = 'pending';
MOCK_PROVIDERS[2].approval_status = 'hold';
MOCK_PROVIDERS[2].approval_notes = 'Aadhar photo is unreadable — please re-upload.';
MOCK_PROVIDERS[3].approval_status = 'rejected';
MOCK_PROVIDERS[10].approval_status = 'approved';
MOCK_PROVIDERS[10].status = 'blocked';
MOCK_PROVIDERS[10].approval_notes = 'Blocked after repeated no-shows reported by customers.';

// ---------------------------------------------------------------------
// Customers
// ---------------------------------------------------------------------

const CUSTOMER_FIRST = ['Anand', 'Geetha', 'Ramesh', 'Saroja', 'Vignesh', 'Kalpana', 'Muthu', 'Radha', 'Sathish', 'Vasanthi', 'Elango', 'Nirmala', 'Rajesh', 'Padma', 'Gopal'];

function buildCustomer(id: number): Customer {
  const gender: 'male' | 'female' = rnd() > 0.5 ? 'female' : 'male';
  const name = `${pick(CUSTOMER_FIRST)} ${pick(LAST_NAMES)}`;
  const createdDaysAgo = randInt(1, 200);
  const status = rnd() > 0.93 ? 'blocked' : rnd() > 0.1 ? 'active' : 'pending_payment';
  return {
    customer_id: id,
    display_id: `CUST-${String(id).padStart(6, '0')}`,
    name,
    photo_url: avatarDataUri(name, `cust-${id}`),
    dob: `19${40 + randInt(0, 55)}-0${randInt(1, 9)}-1${randInt(0, 9)}`,
    gender,
    blood_group: pick(['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'unknown']),
    email: rnd() > 0.3 ? `${name.toLowerCase().replace(' ', '.')}${id}@example.com` : null,
    mobile_number: `8${randInt(100000000, 999999999)}`,
    city: pick(CITIES),
    registration_fee_paid: status !== 'pending_payment',
    status,
    referred_by_code: rnd() > 0.55 ? pick(['BP-000001', 'BP-000002', 'BP-000003']) : null,
    created_at: daysAgoISO(createdDaysAgo),
  };
}

export const MOCK_CUSTOMERS: Customer[] = Array.from({ length: 26 }, (_, i) => buildCustomer(i + 1));

// ---------------------------------------------------------------------
// Business Agents + Referrals
// ---------------------------------------------------------------------

export const MOCK_BUSINESS_AGENTS: BusinessAgent[] = [
  {
    business_partner_id: 1,
    display_id: 'BP-000001',
    entity_name: 'Sunrise Elder Care Referrals',
    partner_name: 'Meenakshi Sundaram',
    contact_number_1: '9840012345',
    contact_number_2: '9840012346',
    email: 'meenakshi@sunrisecare.example',
    address: '12 Cathedral Rd, Chennai',
    referral_code: 'REF-SUN01',
    status: 'active',
    created_at: daysAgoISO(180),
  },
  {
    business_partner_id: 2,
    display_id: 'BP-000002',
    entity_name: 'CarePlus Wellness Agency',
    partner_name: 'Arjun Balasubramaniam',
    contact_number_1: '9843311122',
    contact_number_2: null,
    email: 'arjun@careplus.example',
    address: '45 RS Puram, Coimbatore',
    referral_code: 'REF-CPW02',
    status: 'active',
    created_at: daysAgoISO(140),
  },
  {
    business_partner_id: 3,
    display_id: 'BP-000003',
    entity_name: 'Golden Years Consultancy',
    partner_name: 'Vijayalakshmi Rangan',
    contact_number_1: '9845567788',
    contact_number_2: '9845567789',
    email: 'vijaya@goldenyears.example',
    address: '3 Race Course Rd, Madurai',
    referral_code: 'REF-GYC03',
    status: 'active',
    created_at: daysAgoISO(95),
  },
  {
    business_partner_id: 4,
    display_id: 'BP-000004',
    entity_name: 'Vetri Health Partners',
    partner_name: 'Karthikeyan Doss',
    contact_number_1: '9847788990',
    contact_number_2: null,
    email: 'karthik@vetrihealth.example',
    address: '78 Anna Salai, Trichy',
    referral_code: 'REF-VHP04',
    status: 'blocked',
    created_at: daysAgoISO(60),
  },
];

let referralIdCounter = 1;
function buildReferral(businessPartnerId: number, daysBack: number): BusinessAgentReferral {
  const service_type = pick(SERVICE_TYPES.filter((s) => s !== 'physiotherapy'));
  const startOffset = randInt(-10, 20);
  const durationDays = randInt(1, 14);
  const status = daysBack > 30 ? pick(['completed', 'completed', 'cancelled'] as const) : pick(['pending', 'booked', 'completed'] as const);
  const hoursUsed = status === 'completed' ? randInt(6, 60) : status === 'booked' ? randInt(0, 20) : 0;
  const id = referralIdCounter++;
  return {
    id,
    business_partner_id: businessPartnerId,
    customer_id: status !== 'pending' ? 100 + id : null,
    customer_name: `${pick(CUSTOMER_FIRST)} ${pick(LAST_NAMES)}`,
    gender: pick(['male', 'female'] as const),
    service_type,
    duration_start: dateOnly(daysAgoISO(-startOffset + daysBack)),
    duration_end: dateOnly(daysAgoISO(-startOffset - durationDays + daysBack)),
    time_from: pick(['08:00', '09:00', '10:00']),
    time_to: pick(['17:00', '18:00', '20:00']),
    mobile_number: `7${randInt(100000000, 999999999)}`,
    address: `${randInt(1, 150)}, ${pick(['Anna Nagar', 'T Nagar', 'Gandhipuram', 'Race Course'])}, ${pick(CITIES)}`,
    status,
    created_at: daysAgoISO(daysBack),
    referral_code: `RC-${String(id).padStart(5, '0')}`,
    hours_used: hoursUsed,
  };
}

export const MOCK_REFERRALS: BusinessAgentReferral[] = [
  ...Array.from({ length: 9 }, () => buildReferral(1, randInt(1, 150))),
  ...Array.from({ length: 6 }, () => buildReferral(2, randInt(1, 130))),
  ...Array.from({ length: 4 }, () => buildReferral(3, randInt(1, 90))),
  ...Array.from({ length: 2 }, () => buildReferral(4, randInt(1, 55))),
];

// ---------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------

export const MOCK_CONFIG: AppConfiguration = {
  customer_booking_amount: 99,
  customer_annual_fee_new: 499,
  customer_annual_fee_existing: 399,
  provider_annual_fee_new: 599,
  provider_annual_fee_existing: 499,
  org_revenue_share_percent: 20,
};

// Kept in step with the backend seed (src/db/seed.js seedRevenueSharing) so
// the demo and the real database quote the same rates. Providers keep 75%;
// a Business Partner earns 10% of the customer rate on hours their referral
// uses, leaving Sathiyaa 15% on a referred booking.
export const MOCK_REVENUE_SHARING: RevenueSharingConfig[] = [
  { service_type: 'companion', customer_rate_per_hour: 200, provider_rate_per_hour: 150, business_partner_flat_per_hour: 20, effective_from: '2026-01-01' },
  { service_type: 'medical_companion', customer_rate_per_hour: 300, provider_rate_per_hour: 225, business_partner_flat_per_hour: 30, effective_from: '2026-01-01' },
  { service_type: 'nurse', customer_rate_per_hour: 450, provider_rate_per_hour: 340, business_partner_flat_per_hour: 45, effective_from: '2026-01-01' },
  { service_type: 'physiotherapy', customer_rate_per_hour: 600, provider_rate_per_hour: 450, business_partner_flat_per_hour: 60, effective_from: '2026-01-01' },
];

// ---------------------------------------------------------------------
// Time Bank config (points per donated hour, by service type + year) —
// mirrors backend seed defaults (src/db/seed.js seedTimeBankConfig).
// ---------------------------------------------------------------------

export const MOCK_TIME_BANK_CONFIG: TimeBankConfig[] = [
  { id: 1, service_type: 'companion', points_per_hour: 250, application_year: 2026, updated_by: null, updated_at: daysAgoISO(40) },
  { id: 2, service_type: 'medical_companion', points_per_hour: 300, application_year: 2026, updated_by: null, updated_at: daysAgoISO(40) },
  { id: 3, service_type: 'nurse', points_per_hour: 400, application_year: 2026, updated_by: null, updated_at: daysAgoISO(40) },
  { id: 4, service_type: 'physiotherapy', points_per_hour: 500, application_year: 2026, updated_by: null, updated_at: daysAgoISO(40) },
];

// ---------------------------------------------------------------------
// Broadcast messages
// ---------------------------------------------------------------------

export const MOCK_BROADCASTS: BroadcastMessage[] = [
  {
    id: 3,
    title: 'Independence Day Offer',
    message_text: 'Get 15% off your annual renewal this week. Renew from the app to claim.',
    image_url: bannerDataUri('Independence Day Offer', 'broadcast3'),
    target_audience: 'customers',
    sent_by: 1,
    sent_by_name: 'Admin',
    sent_at: daysAgoISO(6),
    recipient_count: 812,
  },
  {
    id: 2,
    title: 'New Physiotherapy Category Live',
    message_text: 'You can now register your expertise under Physiotherapy from your profile screen.',
    image_url: null,
    target_audience: 'providers',
    sent_by: 1,
    sent_by_name: 'Admin',
    sent_at: daysAgoISO(19),
    recipient_count: 214,
  },
  {
    id: 1,
    title: 'Platform Maintenance Notice',
    message_text: 'Sathiyaa will be briefly unavailable on Sunday 2am-3am IST for scheduled maintenance.',
    image_url: bannerDataUri('Platform Maintenance Notice', 'broadcast1'),
    target_audience: 'both',
    sent_by: 1,
    sent_by_name: 'Admin',
    sent_at: daysAgoISO(34),
    recipient_count: 1026,
  },
];

// ---------------------------------------------------------------------
// Audit Log
// ---------------------------------------------------------------------

const FORM_NAMES = [
  'Provider Approval', 'Provider Login', 'Customer Registration', 'Booking Payment',
  'Configuration Update', 'Broadcast Message', 'Business Agent Registration',
  'Customer Login', 'Referral Created', 'Provider Block', 'Booking Created', 'Revenue Sharing Update',
];
const ACTIONS = ['create', 'update', 'approve', 'block', 'login', 'hold', 'delete', 'pay'];
const USER_TYPES: AuditLogEntry['user_type'][] = ['admin', 'provider', 'customer', 'business_agent', 'system'];

export const MOCK_AUDIT_LOG: AuditLogEntry[] = Array.from({ length: 90 }, (_, i) => {
  const user_type = pick(USER_TYPES);
  const daysBack = randInt(0, 60);
  return {
    id: i + 1,
    user_type,
    user_id: user_type === 'system' ? null : randInt(1, 30),
    user_name: user_type === 'system' ? null : user_type === 'admin' ? 'Admin User' : user_type === 'provider' ? pick(MOCK_PROVIDERS).name : user_type === 'business_agent' ? pick(MOCK_BUSINESS_AGENTS).partner_name : pick(MOCK_CUSTOMERS).name,
    device_id: user_type === 'system' ? null : `DEV-${randInt(10000, 99999)}`,
    location_id: user_type === 'system' ? null : `${(12.9 + rnd() * 0.4).toFixed(4)},${(80.1 + rnd() * 0.4).toFixed(4)}`,
    form_name: pick(FORM_NAMES),
    action: pick(ACTIONS),
    transaction_date: daysAgoISO(daysBack),
  };
}).sort((a, b) => (a.transaction_date < b.transaction_date ? 1 : -1));

// ---------------------------------------------------------------------
// Tracking
// ---------------------------------------------------------------------

export const MOCK_TRACKING: ProviderTrackingEntry[] = MOCK_PROVIDERS
  .filter((p) => p.status === 'active' && p.approval_status === 'approved')
  .map((p) => ({
    provider_id: p.provider_id,
    display_id: p.display_id,
    name: p.name,
    service_types: p.expertise.map((e) => e.service_type),
    location_on: p.location_on,
    current_latitude: p.current_latitude,
    current_longitude: p.current_longitude,
    current_location_at: p.current_location_at,
    status: p.status,
    approval_status: p.approval_status,
    on_active_booking: p.location_on && rnd() > 0.6,
  }));

// ---------------------------------------------------------------------
// Devices
// ---------------------------------------------------------------------

// Handsets weighted the way the Indian market actually is, so the column does
// not read like a shelf in an Apple shop. Two rows deliberately share one
// device id, because the case worth designing the screen around is the one
// where the same phone turns up under two accounts.
const DEVICE_MODELS: [string, string, string][] = [
  ['Xiaomi', 'Redmi Note 12', 'Android 13 (SDK 33)'],
  ['samsung', 'SM-M146B', 'Android 14 (SDK 34)'],
  ['realme', 'narzo 60', 'Android 13 (SDK 33)'],
  ['vivo', 'V2244', 'Android 13 (SDK 33)'],
  ['motorola', 'moto g54 5G', 'Android 14 (SDK 34)'],
  ['Xiaomi', 'POCO X5 Pro', 'Android 13 (SDK 33)'],
  ['OnePlus', 'CPH2467', 'Android 14 (SDK 34)'],
  ['Apple', 'iPhone14,5', 'iOS 17.4'],
  ['samsung', 'SM-A546E', 'Android 14 (SDK 34)'],
  ['TECNO', 'Spark 10 Pro', 'Android 13 (SDK 33)'],
  ['OPPO', 'CPH2481', 'Android 13 (SDK 33)'],
  ['Nothing', 'A065', 'Android 14 (SDK 34)'],
];

export const MOCK_DEVICES: UserDevice[] = (() => {
  const out: UserDevice[] = [];
  let id = 1;
  const now = Date.now();

  const push = (
    userType: DeviceUserType,
    userId: number,
    ownerName: string,
    ownerDisplayId: string | null,
    ownerMobile: string | null,
    modelIndex: number,
    minutesAgo: number,
    deviceId?: string,
    isCurrent = true,
  ) => {
    const [manufacturer, model, osVersion] = DEVICE_MODELS[modelIndex % DEVICE_MODELS.length];
    const lastSeen = new Date(now - minutesAgo * 60000);
    out.push({
      id: id++,
      userType,
      userId,
      deviceId: deviceId ?? `sathiyaa-${userType}-${1789000000000 + userId * 7331}`,
      platform: manufacturer === 'Apple' ? 'ios' : 'android',
      manufacturer,
      model,
      osVersion,
      appVersion: `1.0.${userId % 4}+${10 + (userId % 6)}`,
      isPhysical: true,
      firstSeenAt: new Date(now - (minutesAgo + 60 * 24 * (3 + (userId % 40))) * 60000).toISOString(),
      lastSeenAt: lastSeen.toISOString(),
      lastIp: `49.36.${(userId * 13) % 255}.${(userId * 29) % 255}`,
      lastUserAgent: 'Dart/3.13 (dart:io)',
      isCurrent,
      ownerName,
      ownerDisplayId,
      ownerMobile,
    });
  };

  MOCK_PROVIDERS.slice(0, 10).forEach((p, i) =>
    push('provider', p.provider_id, p.name, p.display_id, p.mobile_number, i, 4 + i * 37));

  MOCK_CUSTOMERS.slice(0, 8).forEach((c, i) =>
    push('customer', c.customer_id, c.name, c.display_id, c.mobile_number, i + 3, 12 + i * 95));

  // The interesting pair: one handset, two provider accounts.
  const shared = 'sathiyaa-provider-1789551200674';
  if (MOCK_PROVIDERS.length > 11) {
    push('provider', MOCK_PROVIDERS[10].provider_id, MOCK_PROVIDERS[10].name,
      MOCK_PROVIDERS[10].display_id, MOCK_PROVIDERS[10].mobile_number, 2, 55, shared);
    push('provider', MOCK_PROVIDERS[11].provider_id, MOCK_PROVIDERS[11].name,
      MOCK_PROVIDERS[11].display_id, MOCK_PROVIDERS[11].mobile_number, 2, 1440 * 3, shared, false);
  }

  // One emulator, so the column that flags them has something to show.
  if (MOCK_PROVIDERS.length > 12) {
    const p = MOCK_PROVIDERS[12];
    push('provider', p.provider_id, p.name, p.display_id, p.mobile_number, 5, 1440 * 9);
    out[out.length - 1].isPhysical = false;
    out[out.length - 1].manufacturer = 'Google';
    out[out.length - 1].model = 'sdk_gphone64_x86_64';
  }

  push('admin', 1, 'Priya Admin', 'ADM-000001', null, 7, 2, 'sathiyaa-console-web');
  out[out.length - 1].platform = 'web';
  out[out.length - 1].manufacturer = 'Google';
  out[out.length - 1].model = 'Chrome';
  out[out.length - 1].osVersion = 'Windows';
  out[out.length - 1].lastUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)';

  return out.sort((a, b) => (b.lastSeenAt ?? '').localeCompare(a.lastSeenAt ?? ''));
})();

// ---------------------------------------------------------------------
// Reports
// ---------------------------------------------------------------------

export const MOCK_REPORTS_DASHBOARD: ReportsDashboard = (() => {
  const revenue_by_city = CITIES.map((city) => ({
    city,
    revenue: randInt(40000, 320000),
    bookings: randInt(80, 640),
  })).sort((a, b) => b.revenue - a.revenue);

  const revenue_by_service_type = SERVICE_TYPES.map((service_type) => ({
    service_type,
    revenue: randInt(60000, 380000),
    bookings: randInt(100, 700),
  }));

  const revenue_by_provider = MOCK_PROVIDERS
    .filter((p) => p.approval_status === 'approved')
    .map((p) => ({
      provider_id: p.provider_id,
      provider_name: p.name,
      display_id: p.display_id,
      revenue: randInt(8000, 95000),
      bookings: randInt(10, 180),
    }))
    .sort((a, b) => b.revenue - a.revenue);

  return {
    total_revenue: revenue_by_city.reduce((s, c) => s + c.revenue, 0),
    total_bookings: revenue_by_city.reduce((s, c) => s + c.bookings, 0),
    revenue_by_city,
    revenue_by_service_type,
    revenue_by_provider,
  };
})();

function buildGrowth(period: GrowthPeriod): GrowthReport {
  const counts: Record<GrowthPeriod, number> = { day: 30, week: 12, month: 12, quarter: 8, year: 4 };
  const n = counts[period];
  const points = Array.from({ length: n }, (_, i) => {
    let label: string;
    const now = new Date();
    if (period === 'day') {
      const d = new Date(now); d.setDate(d.getDate() - (n - 1 - i));
      label = d.toLocaleDateString('en-IN', { month: 'short', day: 'numeric' });
    } else if (period === 'week') {
      label = `Wk ${i + 1}`;
    } else if (period === 'month') {
      const d = new Date(now); d.setMonth(d.getMonth() - (n - 1 - i));
      label = d.toLocaleDateString('en-IN', { month: 'short', year: '2-digit' });
    } else if (period === 'quarter') {
      label = `Q${(i % 4) + 1} '${25 + Math.floor(i / 4)}`;
    } else {
      label = `${2022 + i}`;
    }
    return {
      period_label: label,
      new_customers: randInt(3, 45),
      new_providers: randInt(1, 12),
    };
  });
  return { period, points };
}

export const MOCK_GROWTH: Record<GrowthPeriod, GrowthReport> = {
  day: buildGrowth('day'),
  week: buildGrowth('week'),
  month: buildGrowth('month'),
  quarter: buildGrowth('quarter'),
  year: buildGrowth('year'),
};
