// In-memory mutable clone of mockData, so actions taken in mock mode (approve,
// block, register agent, add referral, update config, send broadcast...)
// persist for the rest of the browser session.

import {
  MOCK_PROVIDERS, MOCK_CUSTOMERS, MOCK_BUSINESS_AGENTS, MOCK_REFERRALS,
  MOCK_CONFIG, MOCK_REVENUE_SHARING, MOCK_TIME_BANK_CONFIG, MOCK_BROADCASTS, MOCK_AUDIT_LOG,
} from './mockData';
import type {
  ServiceProvider, Customer, BusinessAgent, BusinessAgentReferral,
  AppConfiguration, ServiceAreaConfig, RevenueSharingConfig, TimeBankConfig, BroadcastMessage, AuditLogEntry,
} from '../types';

function clone<T>(v: T): T {
  return JSON.parse(JSON.stringify(v));
}

export const store = {
  providers: clone(MOCK_PROVIDERS) as ServiceProvider[],
  customers: clone(MOCK_CUSTOMERS) as Customer[],
  businessAgents: clone(MOCK_BUSINESS_AGENTS) as BusinessAgent[],
  referrals: clone(MOCK_REFERRALS) as BusinessAgentReferral[],
  config: clone(MOCK_CONFIG) as AppConfiguration,
  // Where Sathiyaa operates. Separate from `config` because it is not a
  // number: putting it in there would go through the same Number() reshape
  // the fee form uses and come back as NaN.
  serviceArea: {
    enabled: true, city: 'Ahmedabad', state: 'Gujarat',
    lat: 23.0225, lng: 72.5714, radius_km: 35,
  } as ServiceAreaConfig,
  revenueSharing: clone(MOCK_REVENUE_SHARING) as RevenueSharingConfig[],
  timeBankConfig: clone(MOCK_TIME_BANK_CONFIG) as TimeBankConfig[],
  broadcasts: clone(MOCK_BROADCASTS) as BroadcastMessage[],
  auditLog: clone(MOCK_AUDIT_LOG) as AuditLogEntry[],
  nextBusinessAgentId: MOCK_BUSINESS_AGENTS.length + 1,
  nextReferralId: MOCK_REFERRALS.length + 1,
  nextBroadcastId: MOCK_BROADCASTS.length + 1,
  nextAuditId: MOCK_AUDIT_LOG.length + 1,
  nextTimeBankConfigId: MOCK_TIME_BANK_CONFIG.length + 1,
};

export function pushAudit(entry: Omit<AuditLogEntry, 'id' | 'transaction_date'>) {
  store.auditLog.unshift({
    id: store.nextAuditId++,
    transaction_date: new Date().toISOString(),
    ...entry,
  });
}
