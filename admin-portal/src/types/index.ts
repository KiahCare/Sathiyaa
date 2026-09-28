// Types mirror docs/schema.sql field names/types and docs/api-contract.md shapes.

export type ServiceType = 'companion' | 'medical_companion' | 'nurse' | 'physiotherapy';

export type Gender = 'male' | 'female' | 'other';

export type DayOfWeek = 'sun' | 'mon' | 'tue' | 'wed' | 'thu' | 'fri' | 'sat';

export const SERVICE_TYPE_LABELS: Record<ServiceType, string> = {
  companion: 'Companion',
  medical_companion: 'Medical Companion',
  nurse: 'Nurse',
  physiotherapy: 'Physiotherapy',
};

export const DAY_LABELS: Record<DayOfWeek, string> = {
  sun: 'Sun', mon: 'Mon', tue: 'Tue', wed: 'Wed', thu: 'Thu', fri: 'Fri', sat: 'Sat',
};

// ---------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------

export type Role = 'admin' | 'business_agent';

export interface AuthUser {
  role: Role;
  id: number;
  displayId: string;
  name: string;
  email?: string | null;
  adminRole?: 'super_admin' | 'ops_admin' | 'support';
}

export interface LoginResponse {
  token: string;
  user: AuthUser;
}

// ---------------------------------------------------------------------
// Service Providers
// ---------------------------------------------------------------------

export type ApprovalStatus = 'pending' | 'approved' | 'hold' | 'rejected';
export type ProviderStatus = 'active' | 'blocked';
export type ProviderKind = 'freelancer' | 'organization' | 'org_employee';

export interface ProviderWorkHour {
  day_of_week: DayOfWeek;
  start_time: string; // HH:MM
  end_time: string;
}

export interface ProviderExpertise {
  service_type: ServiceType;
  years_experience: number | null;
  notes?: string | null;
}

export interface ProviderAddress {
  address_type: 'home' | 'office';
  line1: string;
  line2?: string | null;
  city?: string | null;
  state?: string | null;
  pincode?: string | null;
  latitude?: number | null;
  longitude?: number | null;
}

export interface ServiceProvider {
  provider_id: number;
  display_id: string;
  provider_kind: ProviderKind;
  // The agency a carer belongs to, for provider_kind 'org_employee'. Approving
  // one means approving somebody an organisation put forward, and the console
  // had no way to say which organisation.
  organization_id: number | null;
  organization_name?: string | null;
  name: string;
  photo_url: string | null;
  gender: Gender | null;
  dob: string | null;
  mobile_number: string;
  email: string | null;
  hourly_rate: number;
  aadhar_doc_url: string | null;
  police_verification_url: string | null;
  /** JSON column: an array, or the string MySQL handed back unparsed. */
  languages?: string[] | string | null;
  /** Organisations only; null for a freelancer. */
  org_registration_url?: string | null;
  gst_number?: string | null;
  contact_person?: string | null;
  work_certificate_url: string | null;
  approval_status: ApprovalStatus;
  approval_notes: string | null;
  approved_by: number | null;
  approved_at: string | null;
  status: ProviderStatus;
  registration_fee_paid: boolean;
  /// The handset this account is bound to; null once an admin releases it.
  device_id: string | null;
  location_on: boolean;
  current_latitude: number | null;
  current_longitude: number | null;
  current_location_at: string | null;
  distance_from_home_pref_km: number | null;
  distance_from_office_pref_km: number | null;
  rating_avg: number;
  rating_count: number;
  created_at: string;
  addresses: ProviderAddress[];
  work_hours: ProviderWorkHour[];
  expertise: ProviderExpertise[];
}

// ---------------------------------------------------------------------
// Customers
// ---------------------------------------------------------------------

export type CustomerStatus = 'pending_payment' | 'active' | 'blocked';

export interface Customer {
  customer_id: number;
  display_id: string;
  name: string;
  photo_url: string | null;
  dob: string;
  gender: Gender;
  blood_group: string;
  email: string | null;
  mobile_number: string;
  city?: string | null;
  registration_fee_paid: boolean;
  status: CustomerStatus;
  referred_by_code: string | null;
  created_at: string;
}

// ---------------------------------------------------------------------
// Business Agents
// ---------------------------------------------------------------------

export type BusinessAgentStatus = 'active' | 'blocked';

export interface BusinessAgent {
  business_partner_id: number;
  display_id: string;
  entity_name: string;
  partner_name: string;
  contact_number_1: string;
  contact_number_2: string | null;
  email: string | null;
  address: string | null;
  referral_code: string;
  status: BusinessAgentStatus;
  created_at: string;
}

export type ReferralStatus = 'pending' | 'booked' | 'completed' | 'cancelled';

export interface BusinessAgentReferral {
  id: number;
  business_partner_id: number;
  customer_id: number | null;
  customer_name: string;
  gender: Gender | null;
  service_type: ServiceType;
  duration_start: string;
  duration_end: string;
  time_from: string;
  time_to: string;
  mobile_number: string;
  address: string | null;
  status: ReferralStatus;
  created_at: string;
  referral_code: string;
  hours_used?: number;
  revenue_earned?: number;
  /** The carer allocated to this referral. Null until an admin allocates it. */
  allocated_provider_id?: number | null;
  allocated_provider_name?: string | null;
  allocated_provider_display_id?: string | null;
  allocated_provider_mobile?: string | null;
  allocated_at?: string | null;
}

export interface BusinessAgentRevenueSummary {
  total_earned: number;
  total_hours_used: number;
  total_referrals: number;
  by_referral: {
    referral_id: number;
    customer_name: string;
    service_type: ServiceType;
    hours_used: number;
    flat_rate_per_hour: number;
    revenue: number;
  }[];
  by_month: { month: string; revenue: number }[];
}

// ---------------------------------------------------------------------
// Bookings (lightly used by reports/directories)
// ---------------------------------------------------------------------

export type BookingStatus =
  | 'searching' | 'pending_payment' | 'confirmed' | 'in_progress'
  | 'completed' | 'cancelled' | 'expired';

// ---------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------

export interface AppConfiguration {
  customer_booking_amount: number;
  customer_annual_fee_new: number;
  customer_annual_fee_existing: number;
  provider_annual_fee_new: number;
  provider_annual_fee_existing: number;
  // Sathiyaa's markup on top of an organization's own per-service fee (e.g.
  // org charges 100/hr + 20% -> customer sees 120/hr). Freelancers use
  // RevenueSharingConfig below instead and are unaffected by this value.
  org_revenue_share_percent: number;
}

/**
 * Where Sathiyaa currently operates.
 *
 * Kept in app_configuration next to the fees so opening a new city is a value
 * typed into this console rather than a new APK in Play Store review. The
 * apps read it from an unauthenticated /public/service-area, and the server
 * -- not the app -- decides whether a given sign-up is inside it.
 */
export interface ServiceAreaConfig {
  enabled: boolean;
  city: string;
  state: string;
  lat: number;
  lng: number;
  radius_km: number;
}

/** One place people have registered from, and how many. */
export interface SignupPlace {
  city: string;
  state: string;
  customers: number;
  customersInside: number;
  providers: number;
  providersInside: number;
  latest: string | null;
}

export interface SignupPlacesReport {
  serviceArea: { city: string; state: string; radiusKm: number; enabled: boolean };
  places: SignupPlace[];
  notReported: { customers: number; providers: number };
}

export interface RevenueSharingConfig {
  service_type: ServiceType;
  customer_rate_per_hour: number;
  provider_rate_per_hour: number;
  business_partner_flat_per_hour: number;
  effective_from: string;
}

// Points a No-Fees (volunteer) provider earns per donated hour of a given
// service, for a given application year. Unique per (service_type,
// application_year) — mirrors time_bank_config in docs/schema.sql.
export interface TimeBankConfig {
  id: number;
  service_type: ServiceType;
  points_per_hour: number;
  application_year: number;
  updated_by: number | null;
  updated_at: string;
}

// ---------------------------------------------------------------------
// Broadcast
// ---------------------------------------------------------------------

export type BroadcastAudience = 'customers' | 'providers' | 'both';

export interface BroadcastMessage {
  id: number;
  title: string;
  message_text: string;
  image_url: string | null;
  target_audience: BroadcastAudience;
  sent_by: number;
  sent_by_name: string;
  sent_at: string;
  recipient_count: number;
}

// ---------------------------------------------------------------------
// Audit Log
// ---------------------------------------------------------------------

export type AuditUserType = 'customer' | 'provider' | 'business_agent' | 'admin' | 'system';

export type DeviceUserType = 'customer' | 'provider' | 'business_agent' | 'admin';

/**
 * One handset, as the registry knows it.
 *
 * Field names are camelCase because this one comes straight from the API that
 * way — the device endpoints alias their columns in SQL rather than leaving
 * snake_case for the console to translate.
 */
export interface UserDevice {
  id: number;
  userType: DeviceUserType;
  userId: number;
  deviceId: string;
  platform: string | null;
  manufacturer: string | null;
  model: string | null;
  osVersion: string | null;
  appVersion: string | null;
  isPhysical: boolean | null;
  firstSeenAt: string | null;
  lastSeenAt: string | null;
  lastIp: string | null;
  lastUserAgent: string | null;
  isCurrent: boolean;
  ownerName: string | null;
  ownerDisplayId: string | null;
  ownerMobile: string | null;
}

export interface AuditLogEntry {
  id: number;
  user_type: AuditUserType;
  user_id: number | null;
  user_name: string | null;
  device_id: string | null;
  location_id: string | null;
  form_name: string;
  action: string;
  transaction_date: string;

  /// What the action actually did — the booking id, how many carers were asked,
  /// which of them the customer chose. The server has always written this and
  /// the console has never shown it, so every row read "CreateBooking" and
  /// nothing else. MySQL hands a JSON column back already parsed; the string
  /// case is here because a driver or a proxy that does not is a thing that
  /// happens and should degrade to showing the raw text.
  metadata?: Record<string, unknown> | string | null;
}

// ---------------------------------------------------------------------
// Reports
// ---------------------------------------------------------------------

export interface RevenueByCity {
  city: string;
  revenue: number;
  bookings: number;
}

export interface RevenueByServiceType {
  service_type: ServiceType;
  revenue: number;
  bookings: number;
}

export interface RevenueByProvider {
  provider_id: number;
  provider_name: string;
  display_id: string;
  revenue: number;
  bookings: number;
}

export interface ReportsDashboard {
  total_revenue: number;
  total_bookings: number;
  revenue_by_city: RevenueByCity[];
  revenue_by_service_type: RevenueByServiceType[];
  revenue_by_provider: RevenueByProvider[];
}

export type GrowthPeriod = 'day' | 'week' | 'month' | 'quarter' | 'year';

export interface GrowthPoint {
  period_label: string;
  new_customers: number;
  new_providers: number;
}

export interface GrowthReport {
  period: GrowthPeriod;
  points: GrowthPoint[];
}

// ---------------------------------------------------------------------
// Tracking
// ---------------------------------------------------------------------

export interface ProviderTrackingEntry {
  provider_id: number;
  display_id: string;
  name: string;
  service_types: ServiceType[];
  location_on: boolean;
  current_latitude: number | null;
  current_longitude: number | null;
  current_location_at: string | null;
  status: ProviderStatus;
  approval_status: ApprovalStatus;
  on_active_booking: boolean;
}

// ---------------------------------------------------------------------
// Generic API envelope
// ---------------------------------------------------------------------

export interface ApiError {
  error: { code: string; message: string };
}

export interface Paginated<T> {
  items: T[];
  total: number;
  page: number;
  page_size: number;
}
