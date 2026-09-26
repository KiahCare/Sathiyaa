import { useEffect, useMemo, useState } from 'react';
import type { AuditLogEntry, AuditUserType } from '../../types';
import { getAuditLog } from '../../api/services';
import { PageHeader, TableSkeleton, EmptyState, ErrorState } from '../../components/ui';

const USER_TYPES: { value: AuditUserType | 'all'; label: string }[] = [
  { value: 'all', label: 'All users' },
  { value: 'admin', label: 'Admin' },
  { value: 'provider', label: 'Provider' },
  { value: 'customer', label: 'Customer' },
  { value: 'business_agent', label: 'Business Partner' },
  { value: 'system', label: 'System' },
];

const TYPE_BADGE: Record<AuditUserType, string> = {
  admin: 'badge-blue', provider: 'badge-green', customer: 'badge-amber', business_agent: 'badge-gray', system: 'badge-gray',
};

/**
 * The recorded detail, as one readable line.
 *
 * Not raw JSON: an audit log is read by somebody working out what happened,
 * and `{"bookingId":412,"providersNotified":3}` makes them parse punctuation
 * before they can read the fact. Keys become words, nulls are dropped because
 * "this did not apply" is not worth a column inch, and the whole thing is
 * truncated — the full value is on the row's title attribute for anyone who
 * wants it.
 */
function summarise(metadata: AuditLogEntry['metadata']): { short: string; full: string } {
  if (metadata == null) return { short: '—', full: '' };

  let obj: Record<string, unknown>;
  if (typeof metadata === 'string') {
    try {
      obj = JSON.parse(metadata);
    } catch {
      return { short: metadata.slice(0, 80), full: metadata };
    }
  } else {
    obj = metadata;
  }

  const parts = Object.entries(obj)
    .filter(([, v]) => v !== null && v !== undefined && v !== '')
    .map(([k, v]) => {
      const label = k
        .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
        .replace(/_/g, ' ')
        .toLowerCase();
      const value = typeof v === 'object' ? JSON.stringify(v) : String(v);
      return `${label} ${value}`;
    });

  if (parts.length === 0) return { short: '—', full: '' };
  const full = parts.join(' · ');
  return { short: full.length > 90 ? `${full.slice(0, 88)}…` : full, full };
}

export default function AuditLog() {
  const [entries, setEntries] = useState<AuditLogEntry[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [userType, setUserType] = useState<AuditUserType | 'all'>('all');
  const [formName, setFormName] = useState('');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');

  async function load() {
    setError(null);
    try {
      setEntries(await getAuditLog({ user_type: userType, form_name: formName || undefined, from: from || undefined, to: to || undefined }));
    } catch (err: any) {
      setError(err?.message ?? 'Failed to load audit log.');
    }
  }

  useEffect(() => {
    setEntries(null);
    const t = setTimeout(load, 250);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [userType, formName, from, to]);

  const formOptions = useMemo(() => {
    const s = new Set<string>();
    (entries ?? []).forEach((e) => s.add(e.form_name));
    return Array.from(s).sort();
  }, [entries]);

  function resetFilters() {
    setUserType('all');
    setFormName('');
    setFrom('');
    setTo('');
  }

  return (
    <div>
      <PageHeader title="Audit Log" subtitle="Every write action across the platform, with device and location context." />

      <div className="card" style={{ marginBottom: 16, padding: '14px 16px', display: 'flex', gap: 12, flexWrap: 'wrap', alignItems: 'flex-end' }}>
        <div>
          <label className="field-label">User type</label>
          <select className="input" style={{ minWidth: 160 }} value={userType} onChange={(e) => setUserType(e.target.value as AuditUserType | 'all')}>
            {USER_TYPES.map((u) => <option key={u.value} value={u.value}>{u.label}</option>)}
          </select>
        </div>
        <div>
          <label className="field-label">Form name</label>
          <select className="input" style={{ minWidth: 190 }} value={formName} onChange={(e) => setFormName(e.target.value)}>
            <option value="">All forms</option>
            {formOptions.map((f) => <option key={f} value={f}>{f}</option>)}
          </select>
        </div>
        <div>
          <label className="field-label">From</label>
          <input type="date" className="input" value={from} onChange={(e) => setFrom(e.target.value)} />
        </div>
        <div>
          <label className="field-label">To</label>
          <input type="date" className="input" value={to} onChange={(e) => setTo(e.target.value)} />
        </div>
        <button className="btn btn-secondary" onClick={resetFilters}>Reset</button>
      </div>

      <div className="card" style={{ overflow: 'hidden' }}>
        {entries === null && !error && <TableSkeleton rows={9} cols={8} />}
        {error && <ErrorState message={error} onRetry={load} />}
        {entries && entries.length === 0 && <EmptyState icon="🧾" title="No audit entries match these filters" />}
        {entries && entries.length > 0 && (
          <div style={{ overflowX: 'auto', maxHeight: 620, overflowY: 'auto' }}>
            <table className="data-table">
              <thead>
                <tr>
                  <th>Date/Time</th>
                  <th>User type</th>
                  <th>User</th>
                  <th>Form</th>
                  <th>Action</th>
                  <th>What happened</th>
                  <th>Device</th>
                  <th>Location</th>
                </tr>
              </thead>
              <tbody>
                {entries.map((e) => {
                  const detail = summarise(e.metadata);
                  return (
                  <tr key={e.id}>
                    <td>{new Date(e.transaction_date).toLocaleString('en-IN')}</td>
                    <td><span className={`badge ${TYPE_BADGE[e.user_type]}`}>{e.user_type.replace('_', ' ')}</span></td>
                    <td>{e.user_name ?? '—'}</td>
                    <td>{e.form_name}</td>
                    <td style={{ textTransform: 'capitalize' }}>{e.action}</td>
                    <td
                      title={detail.full}
                      style={{ fontSize: 12.5, color: 'var(--ink-soft, #5A6B77)', maxWidth: 340 }}
                    >
                      {detail.short}
                    </td>
                    <td style={{ fontFamily: 'monospace', fontSize: 12 }}>{e.device_id ?? '—'}</td>
                    <td style={{ fontFamily: 'monospace', fontSize: 12 }}>{e.location_id ?? '—'}</td>
                  </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
