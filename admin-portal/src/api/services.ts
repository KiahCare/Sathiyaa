// Unified API surface used by pages/components. Every function branches on
// USE_MOCK: true -> reads/writes the in-memory mock store with simulated
// latency; false -> calls the real backend per docs/api-contract.md.

import { apiClient, USE_MOCK, mockDelay, ApiRequestError } from './client';
import { store, pushAudit } from './mockStore';
import { MOCK_TRACKING, MOCK_REPORTS_DASHBOARD, MOCK_GROWTH, MOCK_DEVICES } from './mockData';
import type {
  ServiceProvider, ApprovalStatus, Customer, CustomerStatus, BusinessAgent,
  BusinessAgentReferral, AppConfiguration, RevenueSharingConfig, TimeBankConfig, BroadcastMessage,
  BroadcastAudience, AuditLogEntry, AuditUserType, ProviderTrackingEntry,
  ReportsDashboard, RevenueByCity, RevenueByServiceType, RevenueByProvider,
  GrowthReport, GrowthPeriod, AuthUser, LoginResponse, ServiceType,
  UserDevice, DeviceUserType, ServiceAreaConfig, SignupPlacesReport,
  NewProviderPayload, NewProviderResult, GeocodeResult,
} from '../types';

// ---------------------------------------------------------------------
// Devices
// ---------------------------------------------------------------------

export interface DeviceFilters {
  userType?: DeviceUserType | 'all';
  search?: string;
  currentOnly?: boolean;
}

export async function getDevices(filters: DeviceFilters = {}): Promise<UserDevice[]> {
  if (USE_MOCK) {
    await mockDelay(280);
    let items = [...MOCK_DEVICES];
    if (filters.userType && filters.userType !== 'all') {
      items = items.filter((d) => d.userType === filters.userType);
    }
    if (filters.currentOnly) items = items.filter((d) => d.isCurrent);
    if (filters.search) {
      const q = filters.search.toLowerCase();
      items = items.filter((d) =>
        [d.ownerName, d.ownerDisplayId, d.model, d.manufacturer, d.lastIp, d.deviceId]
          .some((v) => (v ?? '').toLowerCase().includes(q)));
    }
    return items;
  }
  const { data } = await apiClient.get('/admin/devices', {
    params: {
      userType: filters.userType,
      search: filters.search,
      currentOnly: filters.currentOnly ? 'true' : undefined,
    },
  });
  return data.devices ?? [];
}

export async function getAccountsOnDevice(
  deviceId: string,
): Promise<{ deviceId: string; accounts: UserDevice[]; shared: boolean }> {
  if (USE_MOCK) {
    await mockDelay(220);
    const accounts = MOCK_DEVICES.filter((d) => d.deviceId === deviceId);
    return { deviceId, accounts, shared: accounts.length > 1 };
  }
  const { data } = await apiClient.get(`/admin/devices/by-device/${encodeURIComponent(deviceId)}`);
  return data;
}


// ---------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------

export async function loginAdmin(email: string, password: string): Promise<LoginResponse> {
  if (USE_MOCK) {
    await mockDelay(500);
    if (!email || !password) throw new ApiRequestError('VALIDATION', 'Email and password are required.');
    if (password.length < 4) throw new ApiRequestError('INVALID_CREDENTIALS', 'Incorrect email or password.');
    const user: AuthUser = { role: 'admin', id: 1, displayId: 'ADM-000001', name: 'Priya Admin', email, adminRole: 'super_admin' };
    pushAudit({ user_type: 'admin', user_id: 1, user_name: user.name, device_id: 'DEV-WEBADMIN', location_id: null, form_name: 'Admin Login', action: 'login' });
    return { token: 'mock-admin-token', user };
  }
  // Real backend returns { token, admin: { adminId, name, role } } (see
  // authController.adminLogin) — reshape into the { token, user } contract
  // the rest of the app (AuthContext, ProtectedRoute) expects.
  const { data } = await apiClient.post('/auth/admin/login', { email, password });
  const user: AuthUser = {
    role: 'admin',
    id: data.admin.adminId,
    displayId: `ADM-${String(data.admin.adminId).padStart(6, '0')}`,
    name: data.admin.name,
    email,
    adminRole: data.admin.role,
  };
  return { token: data.token, user };
}

export async function loginBusinessAgent(
  userId: string,
  password: string
): Promise<LoginResponse> {
  if (USE_MOCK) {
    await mockDelay(500);
    const agent = store.businessAgents.find(
      (a) => a.display_id.toLowerCase() === userId.toLowerCase() || a.email?.toLowerCase() === userId.toLowerCase()
    ) ?? store.businessAgents[0];
    if (!password) throw new ApiRequestError('VALIDATION', 'Password is required.');
    if (agent.status === 'blocked') throw new ApiRequestError('BLOCKED', 'This business partner account is blocked. Contact Sathiyaa admin.');
    const user: AuthUser = { role: 'business_agent', id: agent.business_partner_id, displayId: agent.display_id, name: agent.partner_name };
    pushAudit({ user_type: 'business_agent', user_id: agent.business_partner_id, user_name: agent.partner_name, device_id: 'DEV-WEBPARTNER', location_id: null, form_name: 'Business Agent Login', action: 'login' });
    return { token: 'mock-agent-token', user };
  }
  // Real backend expects { identifier, password } (authController.
  // businessAgentLogin reads req.body.identifier, not user_id) and returns
  // { token, agent: { businessPartnerId, displayId, entityName, partnerName } }
  // — reshape both ways to match the { token, user } contract used above.
  const { data } = await apiClient.post('/auth/business-agent/login', { identifier: userId, password });
  const user: AuthUser = {
    role: 'business_agent',
    id: data.agent.businessPartnerId,
    displayId: data.agent.displayId,
    name: data.agent.partnerName,
  };
  return { token: data.token, user };
}

// ---------------------------------------------------------------------
// Providers (admin)
// ---------------------------------------------------------------------

export interface ProviderFilters {
  status?: ApprovalStatus | 'all';
  search?: string;
}

export async function listProviders(filters: ProviderFilters = {}): Promise<ServiceProvider[]> {
  if (USE_MOCK) {
    await mockDelay();
    let items = [...store.providers];
    if (filters.status && filters.status !== 'all') {
      items = items.filter((p) => p.approval_status === filters.status);
    }
    if (filters.search) {
      const q = filters.search.toLowerCase();
      items = items.filter(
        (p) => p.name.toLowerCase().includes(q) || p.display_id.toLowerCase().includes(q) || p.mobile_number.includes(q)
      );
    }
    return items.sort((a, b) => (a.created_at < b.created_at ? 1 : -1));
  }
  // Backend filters with a literal `WHERE status = ?` — sending the UI's "all"
  // tab value through would match zero rows, so only forward a real status.
  const { status, ...rest } = filters;
  const params = status && status !== 'all' ? { status, ...rest } : rest;
  const { data } = await apiClient.get('/admin/providers', { params });
  return data.providers ?? data;
}


async function setProviderApproval(id: number, status: ApprovalStatus, note?: string) {
  if (USE_MOCK) {
    await mockDelay(450);
    const p = store.providers.find((x) => x.provider_id === id);
    if (!p) throw new ApiRequestError('NOT_FOUND', 'Provider not found.', 404);
    p.approval_status = status;
    p.approval_notes = note ?? null;
    if (status === 'approved') {
      p.approved_by = 1;
      p.approved_at = new Date().toISOString();
    }
    pushAudit({
      user_type: 'admin', user_id: 1, user_name: 'Admin User', device_id: 'DEV-WEBADMIN', location_id: null,
      form_name: 'Provider Approval', action: status === 'approved' ? 'approve' : status === 'hold' ? 'hold' : 'reject',
    });
    return p;
  }
  const path = status === 'approved' ? 'approve' : status === 'hold' ? 'hold' : 'reject';
  const { data } = await apiClient.post(`/admin/providers/${id}/${path}`, { note });
  return data;
}

export const approveProvider = (id: number) => setProviderApproval(id, 'approved');
export const holdProvider = (id: number, note: string) => setProviderApproval(id, 'hold', note);
export const rejectProvider = (id: number, note: string) => setProviderApproval(id, 'rejected', note);

/**
 * Blocking is not an approval decision.
 *
 * It used to be routed through setProviderApproval, reading the provider's
 * current approval status out of `store` -- the mock store -- to pass along.
 * Against the live server that array is empty, the lookup returned undefined,
 * the fallback said 'approved', and the path mapping duly sent the request to
 * the **approve** endpoint. Pressing Block approved the provider instead, which
 * is why nothing appeared to happen. It has its own endpoint; it now uses it.
 */
export const blockProvider = async (id: number, note: string) => {
  if (USE_MOCK) {
    await mockDelay(450);
    const p = store.providers.find((x) => x.provider_id === id);
    if (!p) throw new ApiRequestError('NOT_FOUND', 'Provider not found.', 404);
    p.status = 'blocked';
    p.approval_notes = note || null;
    pushAudit({
      user_type: 'admin', user_id: 1, user_name: 'Admin User', device_id: 'DEV-WEBADMIN',
      location_id: null, form_name: 'Provider Directory', action: 'block',
    });
    return p;
  }
  const { data } = await apiClient.post(`/admin/providers/${id}/block`, { note });
  return data;
};
export const unblockProvider = async (id: number) => {
  if (USE_MOCK) {
    await mockDelay(400);
    const p = store.providers.find((x) => x.provider_id === id);
    if (!p) throw new ApiRequestError('NOT_FOUND', 'Provider not found.', 404);
    p.status = 'active';
    pushAudit({ user_type: 'admin', user_id: 1, user_name: 'Admin User', device_id: 'DEV-WEBADMIN', location_id: null, form_name: 'Provider Directory', action: 'unblock' });
    return p;
  }
  const { data } = await apiClient.post(`/admin/providers/${id}/unblock`, {});
  return data;
};

/**
 * Removes a registration that should never have been a row.
 *
 * Blocking is right for a real account that misbehaves: the history survives
 * and the audit trail still reads correctly. This is for the other case --
 * junk left behind by an automated test run, or a duplicate sign-up. The
 * server refuses once the account has any booking history, so nothing with a
 * story attached can be lost this way.
 */
export const deleteProvider = async (id: number) => {
  if (USE_MOCK) {
    await mockDelay(350);
    const i = store.providers.findIndex((x) => x.provider_id === id);
    if (i === -1) throw new ApiRequestError('NOT_FOUND', 'Provider not found.', 404);
    const [removed] = store.providers.splice(i, 1);
    pushAudit({
      user_type: 'admin', user_id: 1, user_name: 'Admin User', device_id: 'DEV-WEBADMIN',
      location_id: null, form_name: 'Provider Directory', action: 'delete',
    });
    return removed;
  }
  const { data } = await apiClient.delete(`/admin/providers/${id}`);
  return data;
};

/**
 * The same, for a customer with no bookings.
 *
 * No screen calls this yet, deliberately. The Customers page offers block and
 * unblock only, because blocking keeps the history and the server refuses to
 * delete an account that has ever taken a booking anyway — so for all but a
 * brand-new account, delete and block mean the same thing and block says so
 * honestly. Kept because the endpoint exists and is the right call for clearing
 * out a test sign-up.
 */
export const deleteCustomer = async (id: number) => {
  if (USE_MOCK) {
    await mockDelay(350);
    const i = store.customers.findIndex((x) => x.customer_id === id);
    if (i === -1) throw new ApiRequestError('NOT_FOUND', 'Customer not found.', 404);
    const [removed] = store.customers.splice(i, 1);
    pushAudit({
      user_type: 'admin', user_id: 1, user_name: 'Admin User', device_id: 'DEV-WEBADMIN',
      location_id: null, form_name: 'Customer Directory', action: 'delete',
    });
    return removed;
  }
  const { data } = await apiClient.delete(`/admin/customers/${id}`);
  return data;
};

/**
 * Releases the phone a provider's account is tied to.
 *
 * A provider account is bound to one handset by design, so a lost, replaced
 * or wiped phone locks them out with no way back. This is that way back, and
 * it is an admin action because self-service would defeat the binding.
 */
export const resetProviderDevice = async (id: number) => {
  if (USE_MOCK) {
    await mockDelay(400);
    const p = store.providers.find((x) => x.provider_id === id);
    if (!p) throw new ApiRequestError('NOT_FOUND', 'Provider not found.', 404);
    pushAudit({
      user_type: 'admin', user_id: 1, user_name: 'Admin User', device_id: 'DEV-WEBADMIN',
      location_id: null, form_name: 'Provider Directory', action: 'reset-device',
    });
    return { reset: true, providerId: id };
  }
  const { data } = await apiClient.post(`/admin/providers/${id}/reset-device`, {});
  return data;
};

/**
 * Sign a carer or an organisation up from the office.
 *
 * Most of Sathiyaa's providers are taken on in person, and before this the only
 * way in was to borrow their handset and drive the app's registration form on
 * it. Done on an office phone instead, the account bound itself to the office
 * phone and the provider could never sign in from their own.
 *
 * The server does the validating, not this function. It answers 422 with
 * `error.fields` keyed by the form's own field names, so the form shows each
 * problem next to the box it belongs to and every problem at once. Re-checking
 * the same rules here would mean two sets of rules to keep in step, and the
 * browser's would be the one that could be skipped.
 */
export async function createProvider(payload: NewProviderPayload): Promise<NewProviderResult> {
  if (USE_MOCK) {
    await mockDelay(700);
    if (store.providers.some((p) => p.mobile_number === payload.mobile)) {
      throw new ApiRequestError('VALIDATION', 'A provider with this mobile number already exists.', 422);
    }
    const id = Math.max(0, ...store.providers.map((p) => p.provider_id)) + 1;
    const provider: ServiceProvider = {
      provider_id: id,
      display_id: `SP-${String(id).padStart(6, '0')}`,
      provider_kind: payload.providerKind,
      organization_id: null,
      name: payload.name,
      photo_url: payload.photoUrl ?? null,
      gender: (payload.gender || null) as ServiceProvider['gender'],
      dob: payload.dob ?? null,
      mobile_number: payload.mobile,
      email: payload.email ?? null,
      hourly_rate: payload.noFees ? 0 : Number(payload.hourlyRate) || 0,
      no_fees: !!payload.noFees,
      languages: payload.languages,
      aadhar_doc_url: payload.aadharDocUrl ?? null,
      work_certificate_url: payload.workCertificateUrl ?? null,
      police_verification_url: payload.policeVerificationUrl ?? null,
      police_verification_valid_from: payload.policeVerificationValidFrom ?? null,
      police_verification_valid_to: payload.policeVerificationValidTo ?? null,
      medical_certificate_url: payload.medicalCertificateUrl ?? null,
      medical_certificate_valid_from: payload.medicalCertificateValidFrom ?? null,
      medical_certificate_valid_to: payload.medicalCertificateValidTo ?? null,
      org_registration_url: payload.orgRegistrationUrl ?? null,
      gst_number: payload.gstNumber ?? null,
      contact_person: payload.contactPerson ?? null,
      allocate_via_org: !!payload.allocateViaOrg,
      approval_status: payload.approvalStatus,
      approval_notes: 'Created in the admin console.',
      approved_by: payload.approvalStatus === 'approved' ? 1 : null,
      approved_at: payload.approvalStatus === 'approved' ? new Date().toISOString() : null,
      status: 'active',
      registration_fee_paid: !!payload.registrationFeePaid,
      device_id: null,
      location_on: false,
      current_latitude: null,
      current_longitude: null,
      current_location_at: null,
      distance_from_home_pref_km: null,
      distance_from_office_pref_km: null,
      rating_avg: 0,
      rating_count: 0,
      created_at: new Date().toISOString(),
      addresses: [{ address_type: 'home', ...payload.address }],
      work_hours: payload.workHours.map((w) => ({
        day_of_week: w.dayOfWeek, start_time: w.startTime, end_time: w.endTime,
      })),
      expertise: payload.expertise.map((service_type) => ({ service_type, years_experience: null })),
    };
    store.providers.unshift(provider);
    pushAudit({
      user_type: 'admin', user_id: 1, user_name: 'Admin User', device_id: 'DEV-WEBADMIN',
      location_id: null, form_name: 'AdminCreateProvider', action: 'create',
    });
    return { provider, outstanding: [] };
  }
  const { data } = await apiClient.post('/admin/providers', payload);
  return data;
}

/**
 * Turn a typed address into coordinates.
 *
 * Proxied through the API rather than called from the browser so the maps
 * provider's fair-use limit is enforced in one place and a paid provider's key
 * never reaches the bundle.
 */
export async function geocodeAddress(q: string): Promise<GeocodeResult> {
  if (USE_MOCK) {
    await mockDelay(500);
    // Somewhere in the launch city, so the form behaves the same way in a demo
    // as it does against a real server.
    return {
      formattedAddress: `${q} (mock)`,
      latitude: 23.0225 + (Math.random() - 0.5) / 40,
      longitude: 72.5714 + (Math.random() - 0.5) / 40,
      geocoder: 'mock',
    };
  }
  const { data } = await apiClient.get('/admin/geocode', { params: { q } });
  return data;
}

/**
 * Upload one document and return the path to store against the provider.
 *
 * The path comes back relative (`/uploads/aadhar/...`) on purpose — it is
 * resolved against the API's origin by `uploadUrl()` when it is displayed,
 * because the console is served from a different origin than the API and an
 * absolute URL built from the API's own `Host` header is wrong behind a CDN.
 */
export async function uploadProviderDocument(
  file: File,
  category: 'photo' | 'aadhar' | 'police-verification' | 'work-certificate'
    | 'medical-certificate' | 'org-registration',
): Promise<string> {
  if (USE_MOCK) {
    await mockDelay(600);
    // A real object URL, so the form's preview of the chosen file works in a
    // demo even though nothing has been stored anywhere.
    return URL.createObjectURL(file);
  }
  const form = new FormData();
  form.append('file', file);
  form.append('category', category);
  const { data } = await apiClient.post('/uploads', form);
  return data.url as string;
}

// ---------------------------------------------------------------------
// Customers (admin directory)
// ---------------------------------------------------------------------

export interface CustomerFilters {
  status?: CustomerStatus | 'all';
  search?: string;
}

export async function listCustomers(filters: CustomerFilters = {}): Promise<Customer[]> {
  if (USE_MOCK) {
    await mockDelay();
    let items = [...store.customers];
    if (filters.status && filters.status !== 'all') items = items.filter((c) => c.status === filters.status);
    if (filters.search) {
      const q = filters.search.toLowerCase();
      items = items.filter((c) => c.name.toLowerCase().includes(q) || c.display_id.toLowerCase().includes(q) || c.mobile_number.includes(q));
    }
    return items.sort((a, b) => (a.created_at < b.created_at ? 1 : -1));
  }
  // Same "all" caveat as listProviders above — the backend's WHERE status = ?
  // only makes sense for a real status value.
  const { status, ...rest } = filters;
  const params = status && status !== 'all' ? { status, ...rest } : rest;
  const { data } = await apiClient.get('/admin/customers', { params });
  return data.customers ?? data;
}

export async function setCustomerBlocked(id: number, blocked: boolean): Promise<Customer> {
  if (USE_MOCK) {
    await mockDelay(400);
    const c = store.customers.find((x) => x.customer_id === id);
    if (!c) throw new ApiRequestError('NOT_FOUND', 'Customer not found.', 404);
    c.status = blocked ? 'blocked' : 'active';
    pushAudit({ user_type: 'admin', user_id: 1, user_name: 'Admin User', device_id: 'DEV-WEBADMIN', location_id: null, form_name: 'Customer Directory', action: blocked ? 'block' : 'unblock' });
    return c;
  }
  const { data } = await apiClient.post(`/admin/customers/${id}/${blocked ? 'block' : 'unblock'}`, {});
  return data;
}

// ---------------------------------------------------------------------
// Business Agents
// ---------------------------------------------------------------------

export async function listBusinessAgents(): Promise<BusinessAgent[]> {
  if (USE_MOCK) {
    await mockDelay();
    return [...store.businessAgents].sort((a, b) => (a.created_at < b.created_at ? 1 : -1));
  }
  const { data } = await apiClient.get('/admin/business-agents');
  return data.businessAgents ?? data;
}

export interface NewBusinessAgentPayload {
  entity_name: string;
  partner_name: string;
  contact_number_1: string;
  contact_number_2?: string;
  email?: string;
  address?: string;
}

export async function registerBusinessAgent(payload: NewBusinessAgentPayload): Promise<BusinessAgent> {
  if (USE_MOCK) {
    await mockDelay(500);
    const id = store.nextBusinessAgentId++;
    const agent: BusinessAgent = {
      business_partner_id: id,
      display_id: `BP-${String(id).padStart(6, '0')}`,
      entity_name: payload.entity_name,
      partner_name: payload.partner_name,
      contact_number_1: payload.contact_number_1,
      contact_number_2: payload.contact_number_2 || null,
      email: payload.email || null,
      address: payload.address || null,
      referral_code: `REF-${payload.entity_name.replace(/[^A-Za-z]/g, '').slice(0, 3).toUpperCase() || 'BPX'}${String(id).padStart(2, '0')}`,
      status: 'active',
      created_at: new Date().toISOString(),
    };
    store.businessAgents.unshift(agent);
    pushAudit({ user_type: 'admin', user_id: 1, user_name: 'Admin User', device_id: 'DEV-WEBADMIN', location_id: null, form_name: 'Business Agent Registration', action: 'create' });
    return agent;
  }
  // camelCase in, snake_case out -- see the note in createReferral.
  const { data } = await apiClient.post('/admin/business-agents', {
    entityName: payload.entity_name,
    partnerName: payload.partner_name,
    contactNumber1: payload.contact_number_1,
    contactNumber2: payload.contact_number_2,
    email: payload.email,
    address: payload.address,
  });
  return data;
}

export async function setBusinessAgentBlocked(id: number, blocked: boolean): Promise<BusinessAgent> {
  if (USE_MOCK) {
    await mockDelay(400);
    const a = store.businessAgents.find((x) => x.business_partner_id === id);
    if (!a) throw new ApiRequestError('NOT_FOUND', 'Business partner not found.', 404);
    a.status = blocked ? 'blocked' : 'active';
    pushAudit({ user_type: 'admin', user_id: 1, user_name: 'Admin User', device_id: 'DEV-WEBADMIN', location_id: null, form_name: 'Business Agent Management', action: blocked ? 'block' : 'unblock' });
    return a;
  }
  const { data } = await apiClient.put(`/admin/business-agents/${id}`, { status: blocked ? 'blocked' : 'active' });
  return data;
}

function computeReferralRevenue(r: BusinessAgentReferral): number {
  const cfg = store.revenueSharing.find((c) => c.service_type === r.service_type);
  const flat = cfg?.business_partner_flat_per_hour ?? 0;
  return Math.round((r.hours_used ?? 0) * flat);
}

// The same referral list is read by two different people, and which route
// serves it depends on which:
//
//   a partner looking at their own  -> /business-agents/me/referrals
//   an admin looking at a partner's -> /admin/business-agents/:id/referrals
//
// One function used to serve both, pointed at the /me/ route with a
// business_partner_id query parameter. That route sits behind the business
// agent role, so the admin console got 403 -- and the handler scopes by the id
// in the token anyway, so the parameter was never read by anything. Keeping
// them as two named functions is what stops the next person picking one and
// silently getting the other's permissions.
async function fetchReferrals(path: string, businessPartnerId: number): Promise<BusinessAgentReferral[]> {
  if (USE_MOCK) {
    await mockDelay();
    return store.referrals
      .filter((r) => r.business_partner_id === businessPartnerId)
      .map((r) => ({ ...r, revenue_earned: computeReferralRevenue(r) }))
      .sort((a, b) => (a.created_at < b.created_at ? 1 : -1));
  }
  const { data } = await apiClient.get(path);
  return data.referrals ?? data;
}

/** Admin console, viewing somebody else's partner account. */
export function listReferralsForAgent(businessPartnerId: number): Promise<BusinessAgentReferral[]> {
  return fetchReferrals(`/admin/business-agents/${businessPartnerId}/referrals`, businessPartnerId);
}

/** Partner portal, the signed-in partner's own referrals. */
export function listMyReferrals(businessPartnerId: number): Promise<BusinessAgentReferral[]> {
  return fetchReferrals('/business-agents/me/referrals', businessPartnerId);
}

export interface AgentRevenueSummary {
  total_earned: number;
  total_hours_used: number;
  total_referrals: number;
  by_referral: { referral_id: number; customer_name: string; service_type: ServiceType; hours_used: number; flat_rate_per_hour: number; revenue: number }[];
  by_month: { month: string; revenue: number }[];
}

/** Admin console, viewing somebody else's partner account. */
export function getAgentRevenue(businessPartnerId: number): Promise<AgentRevenueSummary> {
  return fetchRevenue(`/admin/business-agents/${businessPartnerId}/revenue`, businessPartnerId);
}

export interface ReferralAllocation {
  referralId: number;
  allocatedProviderId: number;
  providerName: string;
  /** How many other carers also matched. Zero means no fallback. */
  alternatives: number;
}

/**
 * Allocates a carer to a referral.
 *
 * The endpoint has existed since the referral feature was built and nothing
 * in the console ever called it, so a referral submitted by a partner could
 * never be moved off 'pending' by anybody. The server picks the best match on
 * service type, availability and gender preference; this is the button that
 * asks it to.
 */
export async function allocateReferral(referralId: number): Promise<ReferralAllocation> {
  if (USE_MOCK) {
    await mockDelay(500);
    const referral = store.referrals.find((r) => r.id === referralId);
    if (!referral) throw new ApiRequestError('NOT_FOUND', 'Referral not found.', 404);
    const match = store.providers.find(
      (p) => p.approval_status === 'approved' && p.status === 'active'
        && p.expertise.some((e) => e.service_type === referral.service_type)
    );
    if (!match) {
      throw new ApiRequestError(
        'NO_PROVIDER_AVAILABLE', 'No approved, available provider matches this referral.', 409
      );
    }
    referral.status = 'booked';
    referral.allocated_provider_id = match.provider_id;
    referral.allocated_provider_name = match.name;
    referral.allocated_at = new Date().toISOString();
    return {
      referralId, allocatedProviderId: match.provider_id, providerName: match.name, alternatives: 0,
    };
  }
  const { data } = await apiClient.post(`/admin/business-agents/referrals/${referralId}/allocate`);
  return data;
}

/** Partner portal, the signed-in partner's own revenue. */
export function getMyRevenue(businessPartnerId: number): Promise<AgentRevenueSummary> {
  return fetchRevenue('/business-agents/me/revenue', businessPartnerId);
}

async function fetchRevenue(path: string, businessPartnerId: number): Promise<AgentRevenueSummary> {
  if (USE_MOCK) {
    await mockDelay();
    const referrals = store.referrals.filter((r) => r.business_partner_id === businessPartnerId);
    const by_referral = referrals.map((r) => {
      const cfg = store.revenueSharing.find((c) => c.service_type === r.service_type);
      const flat = cfg?.business_partner_flat_per_hour ?? 0;
      return {
        referral_id: r.id,
        customer_name: r.customer_name,
        service_type: r.service_type,
        hours_used: r.hours_used ?? 0,
        flat_rate_per_hour: flat,
        revenue: Math.round((r.hours_used ?? 0) * flat),
      };
    });
    const total_earned = by_referral.reduce((s, r) => s + r.revenue, 0);
    const total_hours_used = by_referral.reduce((s, r) => s + r.hours_used, 0);

    // group by month of referral creation, sorted chronologically
    const monthMap = new Map<string, { label: string; revenue: number }>();
    referrals.forEach((r, i) => {
      const d = new Date(r.created_at);
      const sortKey = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
      const label = d.toLocaleDateString('en-IN', { month: 'short', year: '2-digit' });
      const existing = monthMap.get(sortKey);
      monthMap.set(sortKey, { label, revenue: (existing?.revenue ?? 0) + by_referral[i].revenue });
    });
    const by_month = Array.from(monthMap.entries())
      .sort(([a], [b]) => (a < b ? -1 : 1))
      .map(([, v]) => ({ month: v.label, revenue: v.revenue }));

    return { total_earned, total_hours_used, total_referrals: referrals.length, by_referral, by_month };
  }
  // Reshaped, not passed through.
  //
  // The server answers with {referralCode, totalRevenue, bookings:[...]} in
  // camelCase; this page reads total_earned, total_hours_used, by_referral and
  // by_month. Handing `data` straight back type-checked fine -- it is `any` at
  // the boundary -- and then the first field read threw, unmounting the whole
  // partner portal. Demo mode built the right shape by hand, so it only ever
  // broke against the live server.
  const { data } = await apiClient.get(path);

  type WireBooking = {
    booking_id?: number;
    display_id?: string;
    service_type?: ServiceType;
    customer_name?: string;
    totalHours?: number;
    flatRatePerHour?: number;
    revenue?: number;
    completed_at?: string;
    start_date?: string;
  };

  const bookings: WireBooking[] = data?.bookings ?? [];

  const by_referral = bookings.map((b, i) => ({
    referral_id: Number(b.booking_id ?? i),
    customer_name: String(b.customer_name ?? 'Customer'),
    service_type: (b.service_type ?? 'companion') as ServiceType,
    hours_used: Number(b.totalHours ?? 0),
    flat_rate_per_hour: Number(b.flatRatePerHour ?? 0),
    revenue: Number(b.revenue ?? 0),
  }));

  // The server sends no monthly series, so it is derived from the bookings
  // themselves rather than leaving the chart to read an undefined array.
  const monthMap = new Map<string, { label: string; revenue: number }>();
  for (const b of bookings) {
    const raw = b.completed_at ?? b.start_date;
    if (!raw) continue;
    const d = new Date(raw);
    if (Number.isNaN(d.getTime())) continue;
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    const label = d.toLocaleDateString('en-IN', { month: 'short', year: '2-digit' });
    const existing = monthMap.get(key);
    monthMap.set(key, { label, revenue: (existing?.revenue ?? 0) + Number(b.revenue ?? 0) });
  }
  const by_month = [...monthMap.entries()]
    .sort(([a], [b]) => (a < b ? -1 : 1))
    .map(([, v]) => ({ month: v.label, revenue: v.revenue }));

  return {
    total_earned: Number(data?.totalRevenue ?? by_referral.reduce((sum, r) => sum + r.revenue, 0)),
    total_hours_used: by_referral.reduce((sum, r) => sum + r.hours_used, 0),
    total_referrals: by_referral.length,
    by_referral,
    by_month,
  };
}

export interface NewReferralPayload {
  customer_name: string;
  gender: 'male' | 'female' | 'other';
  service_type: ServiceType;
  duration_start: string;
  duration_end: string;
  time_from: string;
  time_to: string;
  mobile_number: string;
  address: string;
}

export async function createReferral(businessPartnerId: number, payload: NewReferralPayload): Promise<BusinessAgentReferral> {
  if (USE_MOCK) {
    await mockDelay(550);
    const id = store.nextReferralId++;
    const referral: BusinessAgentReferral = {
      id,
      business_partner_id: businessPartnerId,
      customer_id: null,
      status: 'pending',
      created_at: new Date().toISOString(),
      referral_code: `RC-${String(id).padStart(5, '0')}`,
      hours_used: 0,
      ...payload,
    };
    store.referrals.unshift(referral);
    pushAudit({ user_type: 'business_agent', user_id: businessPartnerId, user_name: store.businessAgents.find(a => a.business_partner_id === businessPartnerId)?.partner_name ?? null, device_id: 'DEV-WEBPARTNER', location_id: null, form_name: 'Refer a Customer', action: 'create' });
    return referral;
  }
  // The API reads camelCase request bodies and returns snake_case rows,
  // because responses are MySQL rows and requests are hand-written objects.
  // The payload types in this file are shaped after the *rows*, so posting one
  // straight through sends snake_case into an endpoint that reads camelCase.
  // Every field arrives undefined, and the first required one is what the
  // server names: "customerName is required". The mock branch above stores the
  // object as-is and is perfectly happy, so this only ever broke in live mode.
  const { data } = await apiClient.post('/business-agents/me/referrals', {
    customerName: payload.customer_name,
    gender: payload.gender,
    serviceType: payload.service_type,
    durationStart: payload.duration_start,
    durationEnd: payload.duration_end,
    timeFrom: payload.time_from,
    timeTo: payload.time_to,
    mobileNumber: payload.mobile_number,
    address: payload.address,
  });
  return data;
}

// ---------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------

// Backend returns { config: [{config_key, config_value, description, updated_at}, ...] }
// (see adminController.getConfigAll) — reshape the row list into the flat
// AppConfiguration object the rest of the app expects.
// Only the keys this form owns. The table also holds the service area, whose
// city is a word -- Number() turned it into NaN, and sending the reshaped
// object back would have written "NaN" over "Ahmedabad" every time somebody
// saved a fee.
const FEE_KEYS = [
  'customer_booking_amount',
  'customer_annual_fee_new',
  'customer_annual_fee_existing',
  'provider_annual_fee_new',
  'provider_annual_fee_existing',
  'org_revenue_share_percent',
] as const;

function reshapeConfigRows(rows: Array<{ config_key: string; config_value: string }>): AppConfiguration {
  const out: Record<string, number> = {};
  for (const row of rows) {
    if ((FEE_KEYS as readonly string[]).includes(row.config_key)) {
      out[row.config_key] = Number(row.config_value);
    }
  }
  return out as unknown as AppConfiguration;
}

function rowValue(rows: Array<{ config_key: string; config_value: string }>, key: string, fallback: string) {
  return rows.find((r) => r.config_key === key)?.config_value ?? fallback;
}

export async function getConfig(): Promise<AppConfiguration> {
  if (USE_MOCK) {
    await mockDelay(200);
    return { ...store.config };
  }
  const { data } = await apiClient.get('/admin/config');
  return reshapeConfigRows(data.config ?? data);
}

export async function updateConfig(cfg: AppConfiguration): Promise<AppConfiguration> {
  if (USE_MOCK) {
    await mockDelay(500);
    store.config = { ...cfg };
    pushAudit({ user_type: 'admin', user_id: 1, user_name: 'Admin User', device_id: 'DEV-WEBADMIN', location_id: null, form_name: 'Configuration Update', action: 'update' });
    return { ...store.config };
  }
  // Only the fee keys. Sending the whole object would include anything else
  // the table holds, reshaped through Number().
  const payload: Record<string, number> = {};
  for (const k of FEE_KEYS) payload[k] = (cfg as unknown as Record<string, number>)[k];
  const { data } = await apiClient.put('/admin/config', { config: payload });
  return reshapeConfigRows(data.config ?? data);
}

// ---------------------------------------------------------------------
// Service area
// ---------------------------------------------------------------------

const SERVICE_AREA_FALLBACK: ServiceAreaConfig = {
  enabled: true, city: 'Ahmedabad', state: 'Gujarat',
  lat: 23.0225, lng: 72.5714, radius_km: 35,
};

export async function getServiceAreaConfig(): Promise<ServiceAreaConfig> {
  if (USE_MOCK) {
    await mockDelay(200);
    return { ...(store.serviceArea ?? SERVICE_AREA_FALLBACK) };
  }
  const { data } = await apiClient.get('/admin/config');
  const rows = (data.config ?? data) as Array<{ config_key: string; config_value: string }>;
  return {
    enabled: rowValue(rows, 'service_area_enabled', 'true') !== 'false',
    city: rowValue(rows, 'service_area_city', SERVICE_AREA_FALLBACK.city),
    state: rowValue(rows, 'service_area_state', SERVICE_AREA_FALLBACK.state),
    lat: Number(rowValue(rows, 'service_area_lat', String(SERVICE_AREA_FALLBACK.lat))),
    lng: Number(rowValue(rows, 'service_area_lng', String(SERVICE_AREA_FALLBACK.lng))),
    radius_km: Number(rowValue(rows, 'service_area_radius_km', String(SERVICE_AREA_FALLBACK.radius_km))),
  };
}

export async function updateServiceAreaConfig(area: ServiceAreaConfig): Promise<ServiceAreaConfig> {
  if (USE_MOCK) {
    await mockDelay(400);
    store.serviceArea = { ...area };
    pushAudit({ user_type: 'admin', user_id: 1, user_name: 'Admin User', device_id: 'DEV-WEBADMIN', location_id: null, form_name: 'Service Area Update', action: 'update' });
    return { ...area };
  }
  await apiClient.put('/admin/config', {
    config: {
      service_area_enabled: String(area.enabled),
      service_area_city: area.city,
      service_area_state: area.state,
      service_area_lat: area.lat,
      service_area_lng: area.lng,
      service_area_radius_km: area.radius_km,
    },
  });
  return getServiceAreaConfig();
}

// ---------------------------------------------------------------------
// Where people are signing up from
// ---------------------------------------------------------------------

export async function getSignupPlaces(): Promise<SignupPlacesReport> {
  if (USE_MOCK) {
    await mockDelay(250);
    return {
      serviceArea: { city: 'Ahmedabad', state: 'Gujarat', radiusKm: 35, enabled: true },
      places: [
        { city: 'Ahmedabad', state: 'Gujarat', customers: 34, customersInside: 34, providers: 12, providersInside: 12, latest: null },
        { city: 'Gandhinagar', state: 'Gujarat', customers: 6, customersInside: 6, providers: 3, providersInside: 3, latest: null },
        { city: 'Surat', state: 'Gujarat', customers: 9, customersInside: 0, providers: 1, providersInside: 0, latest: null },
        { city: 'Rajkot', state: 'Gujarat', customers: 4, customersInside: 0, providers: 2, providersInside: 0, latest: null },
      ],
      notReported: { customers: 3, providers: 1 },
    };
  }
  const { data } = await apiClient.get('/admin/reports/signup-places');
  return data as SignupPlacesReport;
}

export async function getRevenueSharing(): Promise<RevenueSharingConfig[]> {
  if (USE_MOCK) {
    await mockDelay(200);
    return [...store.revenueSharing];
  }
  const { data } = await apiClient.get('/admin/revenue-sharing');
  return data.revenueSharing ?? data;
}

export async function updateRevenueSharing(list: RevenueSharingConfig[]): Promise<RevenueSharingConfig[]> {
  if (USE_MOCK) {
    await mockDelay(500);
    store.revenueSharing = [...list];
    pushAudit({ user_type: 'admin', user_id: 1, user_name: 'Admin User', device_id: 'DEV-WEBADMIN', location_id: null, form_name: 'Revenue Sharing Update', action: 'update' });
    return [...store.revenueSharing];
  }
  const { data } = await apiClient.put('/admin/revenue-sharing', { items: list });
  return data.revenueSharing ?? data;
}

export async function getTimeBankConfig(): Promise<TimeBankConfig[]> {
  if (USE_MOCK) {
    await mockDelay(200);
    return [...store.timeBankConfig];
  }
  const { data } = await apiClient.get('/admin/time-bank-config');
  return data.timeBankConfig ?? data;
}

// Backend upserts by the (service_type, application_year) unique pair — see
// adminController.putTimeBankConfig. Only service_type/points_per_hour/
// application_year are read from each item; id/updated_by/updated_at are
// server-assigned, so callers may send freshly-added rows with a local id.
export async function updateTimeBankConfig(list: TimeBankConfig[]): Promise<TimeBankConfig[]> {
  if (USE_MOCK) {
    await mockDelay(500);
    for (const item of list) {
      const existing = store.timeBankConfig.find(
        (r) => r.service_type === item.service_type && r.application_year === item.application_year
      );
      if (existing) {
        existing.points_per_hour = item.points_per_hour;
        existing.updated_by = 1;
        existing.updated_at = new Date().toISOString();
      } else {
        store.timeBankConfig.push({
          id: store.nextTimeBankConfigId++,
          service_type: item.service_type,
          points_per_hour: item.points_per_hour,
          application_year: item.application_year,
          updated_by: 1,
          updated_at: new Date().toISOString(),
        });
      }
    }
    store.timeBankConfig.sort((a, b) => b.application_year - a.application_year || a.service_type.localeCompare(b.service_type));
    pushAudit({ user_type: 'admin', user_id: 1, user_name: 'Admin User', device_id: 'DEV-WEBADMIN', location_id: null, form_name: 'Time Bank Configuration Update', action: 'update' });
    return [...store.timeBankConfig];
  }
  const { data } = await apiClient.put('/admin/time-bank-config', { items: list });
  return data.timeBankConfig ?? data;
}

// ---------------------------------------------------------------------
// Broadcast
// ---------------------------------------------------------------------

export async function listBroadcasts(): Promise<BroadcastMessage[]> {
  if (USE_MOCK) {
    await mockDelay();
    return [...store.broadcasts].sort((a, b) => (a.sent_at < b.sent_at ? 1 : -1));
  }
  const { data } = await apiClient.get('/admin/broadcast');
  // Mapped into the declared type rather than handed through as-is. The page
  // reads recipient_count and sent_by_name; the server did not send either,
  // and `data.broadcasts` being typed as `any` meant nothing complained until
  // the first real broadcast turned the whole console blank.
  const rows: unknown[] = data.broadcasts ?? data ?? [];
  return rows.map((raw) => {
    const b = raw as Partial<BroadcastMessage> & Record<string, unknown>;
    return {
      ...b,
      id: Number(b.id ?? 0),
      title: String(b.title ?? ''),
      message_text: String(b.message_text ?? ''),
      image_url: (b.image_url as string | null) ?? null,
      target_audience: (b.target_audience ?? 'both') as BroadcastMessage['target_audience'],
      sent_by_name: String(b.sent_by_name ?? 'Admin'),
      sent_at: String(b.sent_at ?? ''),
      recipient_count: Number(b.recipient_count ?? 0),
    } as BroadcastMessage;
  });
}

export interface NewBroadcastPayload {
  title: string;
  message: string;
  image_url?: string | null;
  audience: BroadcastAudience;
  /** Narrow to one or more cities. Mutually exclusive with the id lists. */
  cities?: string[];
  pincodes?: string[];
  /** Hand-picked people. Sent exactly as given; no area filter is applied. */
  customerIds?: number[];
  providerIds?: number[];
}

export interface BroadcastReach {
  total: number;
  customers: number;
  providers: number;
  sample: Array<{ userType: 'customer' | 'provider'; name: string }>;
}

export interface BroadcastCity {
  city: string;
  customers: number;
  providers: number;
}

/**
 * How many people would this reach? Asked while the form is being filled in.
 *
 * It resolves exactly what sending would and writes nothing, so the number on
 * screen cannot disagree with what actually goes out.
 */
export async function previewBroadcast(p: NewBroadcastPayload): Promise<BroadcastReach> {
  if (USE_MOCK) {
    await mockDelay(200);
    const c = p.customerIds?.length ?? (p.audience === 'providers' ? 0 : store.customers.length);
    const v = p.providerIds?.length ?? (p.audience === 'customers' ? 0 : store.providers.length);
    return { total: c + v, customers: c, providers: v, sample: [] };
  }
  const { data } = await apiClient.post('/admin/broadcast/preview', {
    audience: p.audience,
    cities: p.cities,
    pincodes: p.pincodes,
    customerIds: p.customerIds,
    providerIds: p.providerIds,
  });
  return data;
}

/** Cities that actually have somebody in them, with counts. */
export async function listBroadcastCities(): Promise<BroadcastCity[]> {
  if (USE_MOCK) {
    await mockDelay(200);
    return [
      { city: 'Bengaluru', customers: 8, providers: 12 },
      { city: 'Chennai', customers: 4, providers: 5 },
      { city: 'Pune', customers: 3, providers: 2 },
    ];
  }
  const { data } = await apiClient.get('/admin/broadcast/cities');
  return data.cities ?? [];
}

export async function sendBroadcast(payload: NewBroadcastPayload): Promise<BroadcastMessage> {
  if (USE_MOCK) {
    await mockDelay(700);
    const audienceCount = payload.audience === 'both'
      ? store.customers.length + store.providers.length
      : payload.audience === 'customers' ? store.customers.length : store.providers.length;
    const msg: BroadcastMessage = {
      id: store.nextBroadcastId++,
      title: payload.title,
      message_text: payload.message,
      image_url: payload.image_url ?? null,
      target_audience: payload.audience,
      sent_by: 1,
      sent_by_name: 'Admin User',
      sent_at: new Date().toISOString(),
      recipient_count: audienceCount,
    };
    store.broadcasts.unshift(msg);
    pushAudit({ user_type: 'admin', user_id: 1, user_name: 'Admin User', device_id: 'DEV-WEBADMIN', location_id: null, form_name: 'Broadcast Message', action: 'create' });
    return msg;
  }
  // Quieter than the other two: title, message and audience happen to match,
  // so a broadcast sent fine and only the image silently never attached.
  const { data } = await apiClient.post('/admin/broadcast', {
    title: payload.title,
    message: payload.message,
    imageUrl: payload.image_url ?? null,
    audience: payload.audience,
    cities: payload.cities,
    pincodes: payload.pincodes,
    customerIds: payload.customerIds,
    providerIds: payload.providerIds,
  });
  return data;
}

// ---------------------------------------------------------------------
// Tracking
// ---------------------------------------------------------------------

export async function getTracking(): Promise<ProviderTrackingEntry[]> {
  if (USE_MOCK) {
    await mockDelay(300);
    return MOCK_TRACKING;
  }
  const { data } = await apiClient.get('/admin/tracking/providers');
  return data.providers ?? data;
}

// ---------------------------------------------------------------------
// Reports
// ---------------------------------------------------------------------

/**
 * The reports endpoints group revenue by city, service and provider, but name
 * the groups `byCity` / `byServiceType` / `byProvider` and do not carry the
 * headline totals the dashboard tiles show. Reshaping here keeps the screen
 * unchanged and the totals derived from the same rows the charts draw, so a
 * tile can never disagree with the chart under it.
 */
export async function getReportsDashboard(): Promise<ReportsDashboard> {
  if (USE_MOCK) {
    await mockDelay(400);
    return MOCK_REPORTS_DASHBOARD;
  }
  const { data } = await apiClient.get('/admin/reports/dashboard');

  const byCity: RevenueByCity[] = (data.byCity ?? []).map((r: { city: string; revenue: number; bookings: number }) => ({
    city: r.city,
    revenue: Number(r.revenue) || 0,
    bookings: Number(r.bookings) || 0,
  }));
  const byServiceType: RevenueByServiceType[] = (data.byServiceType ?? []).map(
    (r: { service_type: string; revenue: number; bookings: number }) => ({
      service_type: r.service_type,
      revenue: Number(r.revenue) || 0,
      bookings: Number(r.bookings) || 0,
    })
  );
  // Typed as RevenueByProvider rather than left to inference: the server calls
  // this column `name` and the rest of the app calls it `provider_name`, and
  // an un-annotated object literal let the mismatch through silently -- the
  // live report rendered a column of blank provider names while demo mode,
  // built from the same type, filled it in.
  const byProvider: RevenueByProvider[] = (data.byProvider ?? []).map(
    (r: { provider_id: number; display_id: string; name: string; revenue: number; bookings: number }) => ({
      provider_id: r.provider_id,
      display_id: r.display_id,
      provider_name: r.name,
      revenue: Number(r.revenue) || 0,
      bookings: Number(r.bookings) || 0,
    })
  );

  return {
    // City is the one grouping every booking belongs to exactly once, so it
    // is the safe basis for a total — service type omits anything unclassified.
    total_revenue: byCity.reduce((sum: number, r: { revenue: number }) => sum + r.revenue, 0),
    total_bookings: byCity.reduce((sum: number, r: { bookings: number }) => sum + r.bookings, 0),
    revenue_by_city: byCity,
    revenue_by_service_type: byServiceType,
    revenue_by_provider: byProvider,
  };
}

/**
 * Growth arrives as two independent series keyed by bucket; the chart draws
 * one line per audience against a shared x-axis, so they are zipped together
 * across the union of buckets rather than assuming both cover the same range.
 */
export async function getGrowthReport(period: GrowthPeriod): Promise<GrowthReport> {
  if (USE_MOCK) {
    await mockDelay(350);
    return MOCK_GROWTH[period];
  }
  const { data } = await apiClient.get('/admin/reports/growth', { params: { period } });

  const customers = new Map<string, number>(
    (data.customers ?? []).map((r: { bucket: string; count: number }) => [r.bucket, Number(r.count) || 0])
  );
  const providers = new Map<string, number>(
    (data.providers ?? []).map((r: { bucket: string; count: number }) => [r.bucket, Number(r.count) || 0])
  );
  const buckets = [...new Set([...customers.keys(), ...providers.keys()])].sort();

  return {
    period,
    points: buckets.map((bucket) => ({
      period_label: bucket,
      new_customers: customers.get(bucket) ?? 0,
      new_providers: providers.get(bucket) ?? 0,
    })),
  };
}

// ---------------------------------------------------------------------
// Audit Log
// ---------------------------------------------------------------------

export interface AuditFilters {
  user_type?: AuditUserType | 'all';
  form_name?: string;
  from?: string;
  to?: string;
}

export async function getAuditLog(filters: AuditFilters = {}): Promise<AuditLogEntry[]> {
  if (USE_MOCK) {
    await mockDelay(300);
    let items = [...store.auditLog];
    if (filters.user_type && filters.user_type !== 'all') items = items.filter((e) => e.user_type === filters.user_type);
    if (filters.form_name) items = items.filter((e) => e.form_name === filters.form_name);
    if (filters.from) items = items.filter((e) => e.transaction_date >= filters.from!);
    if (filters.to) items = items.filter((e) => e.transaction_date <= filters.to! + 'T23:59:59');
    return items;
  }
  const { data } = await apiClient.get('/admin/audit-log', { params: filters });
  return data.auditLog ?? data;
}
