import { useEffect, useState } from 'react';
import type { UserDevice, DeviceUserType } from '../../types';
import { getDevices, getAccountsOnDevice } from '../../api/services';
import { PageHeader, TableSkeleton, EmptyState, ErrorState, StatCard, Modal } from '../../components/ui';

const USER_TYPES: { value: DeviceUserType | 'all'; label: string }[] = [
  { value: 'all', label: 'Everyone' },
  { value: 'provider', label: 'Providers' },
  { value: 'customer', label: 'Customers' },
  { value: 'business_agent', label: 'Business Partners' },
  { value: 'admin', label: 'Admins' },
];

const TYPE_BADGE: Record<DeviceUserType, string> = {
  admin: 'badge-blue',
  provider: 'badge-green',
  customer: 'badge-amber',
  business_agent: 'badge-gray',
};

/** "3 minutes ago" beats a timestamp when the question is "is this now?". */
function since(iso: string | null): string {
  if (!iso) return '—';
  const mins = Math.round((Date.now() - new Date(iso).getTime()) / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins} min ago`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours} h ago`;
  const days = Math.round(hours / 24);
  if (days < 30) return `${days} d ago`;
  return new Date(iso).toLocaleDateString('en-IN');
}

function describe(d: UserDevice): string {
  const parts = [d.manufacturer, d.model].filter(Boolean);
  return parts.length > 0 ? parts.join(' ') : 'Unidentified device';
}

export default function Devices() {
  const [devices, setDevices] = useState<UserDevice[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [userType, setUserType] = useState<DeviceUserType | 'all'>('all');
  const [search, setSearch] = useState('');
  const [currentOnly, setCurrentOnly] = useState(false);

  // The one worth looking at twice: several accounts on one handset.
  const [shared, setShared] = useState<{ deviceId: string; accounts: UserDevice[] } | null>(null);
  const [sharedBusy, setSharedBusy] = useState(false);

  async function load() {
    setError(null);
    try {
      setDevices(await getDevices({ userType, search: search || undefined, currentOnly }));
    } catch (err: any) {
      setError(err?.message ?? 'Could not load the device list.');
    }
  }

  useEffect(() => {
    setDevices(null);
    const t = setTimeout(load, 250);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [userType, search, currentOnly]);

  async function openShared(deviceId: string) {
    setSharedBusy(true);
    try {
      const r = await getAccountsOnDevice(deviceId);
      setShared({ deviceId, accounts: r.accounts });
    } catch (err: any) {
      setError(err?.message ?? 'Could not load the accounts on that device.');
    } finally {
      setSharedBusy(false);
    }
  }

  const list = devices ?? [];
  const physical = list.filter((d) => d.isPhysical === false).length;
  const seenToday = list.filter(
    (d) => d.lastSeenAt && Date.now() - new Date(d.lastSeenAt).getTime() < 24 * 3600 * 1000,
  ).length;

  // A device id under more than one account, within what is loaded. Worth
  // surfacing because binding an account to a device exists precisely to stop
  // a verified carer passing their phone around.
  const idCounts = new Map<string, number>();
  list.forEach((d) => idCounts.set(d.deviceId, (idCounts.get(d.deviceId) ?? 0) + 1));
  const sharedCount = Array.from(idCounts.values()).filter((n) => n > 1).length;

  if (error && !devices) return <ErrorState message={error} onRetry={load} />;

  return (
    <div>
      <PageHeader
        title="Devices"
        subtitle="Every handset that has signed in — what it is, when it was last used, and from where."
      />

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: 14, marginBottom: 20 }}>
        <StatCard label="Devices listed" value={devices ? String(list.length) : '—'} accent="var(--color-primary)" />
        <StatCard label="Used in last 24h" value={devices ? String(seenToday) : '—'} />
        <StatCard label="Emulators" value={devices ? String(physical) : '—'} sub="Not a real handset" />
        <StatCard label="Shared handsets" value={devices ? String(sharedCount) : '—'} sub="One device, several accounts" />
      </div>

      <div className="card" style={{ marginBottom: 16, padding: '14px 16px', display: 'flex', gap: 12, flexWrap: 'wrap', alignItems: 'flex-end' }}>
        <div>
          <label className="field-label" htmlFor="dev-type">Account type</label>
          <select id="dev-type" value={userType} onChange={(e) => setUserType(e.target.value as DeviceUserType | 'all')}>
            {USER_TYPES.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}
          </select>
        </div>
        <div style={{ flex: '1 1 260px' }}>
          <label className="field-label" htmlFor="dev-search">Search</label>
          <input
            id="dev-search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Name, ID, model, IP address, device id"
            style={{ width: '100%' }}
          />
        </div>
        <label style={{ display: 'flex', alignItems: 'center', gap: 8, paddingBottom: 8, fontSize: 13.5 }}>
          <input type="checkbox" checked={currentOnly} onChange={(e) => setCurrentOnly(e.target.checked)} />
          Currently bound only
        </label>
        <button
          className="btn-secondary"
          onClick={() => { setUserType('all'); setSearch(''); setCurrentOnly(false); }}
          style={{ marginBottom: 2 }}
        >
          Reset
        </button>
      </div>

      {error && <div style={{ marginBottom: 12 }}><ErrorState message={error} onRetry={load} /></div>}

      {!devices ? (
        <TableSkeleton rows={8} cols={6} />
      ) : list.length === 0 ? (
        <EmptyState
          icon="📱"
          title="No devices recorded yet"
          description="A row appears here the first time somebody signs in from the customer or provider app. Nothing is recorded until then."
        />
      ) : (
        <div className="tbl-wrap card" style={{ overflowX: 'auto' }}>
          <table className="data-table">
            <thead>
              <tr>
                <th>Who</th>
                <th>Device</th>
                <th>OS / app</th>
                <th>Last seen</th>
                <th>From</th>
                <th>Device ID</th>
              </tr>
            </thead>
            <tbody>
              {list.map((d) => {
                const isShared = (idCounts.get(d.deviceId) ?? 0) > 1;
                return (
                  <tr key={d.id}>
                    <td>
                      <div style={{ fontWeight: 600 }}>{d.ownerName ?? 'Unknown'}</div>
                      <div style={{ display: 'flex', gap: 6, alignItems: 'center', marginTop: 3, flexWrap: 'wrap' }}>
                        <span className={`badge ${TYPE_BADGE[d.userType]}`}>{d.userType.replace('_', ' ')}</span>
                        {d.ownerDisplayId && <span style={{ fontSize: 12, color: 'var(--color-muted)' }}>{d.ownerDisplayId}</span>}
                      </div>
                      {d.ownerMobile && <div style={{ fontSize: 12, color: 'var(--color-muted)', marginTop: 2 }}>{d.ownerMobile}</div>}
                    </td>
                    <td>
                      <div style={{ fontWeight: 600 }}>{describe(d)}</div>
                      <div style={{ display: 'flex', gap: 6, marginTop: 3, flexWrap: 'wrap' }}>
                        {d.isCurrent && <span className="badge badge-green">bound</span>}
                        {d.isPhysical === false && <span className="badge badge-amber">emulator</span>}
                        {isShared && (
                          <button
                            className="badge badge-amber"
                            onClick={() => openShared(d.deviceId)}
                            disabled={sharedBusy}
                            style={{ border: 0, cursor: 'pointer' }}
                            title="Several accounts have used this handset"
                          >
                            shared →
                          </button>
                        )}
                      </div>
                    </td>
                    <td>
                      <div>{d.osVersion ?? '—'}</div>
                      <div style={{ fontSize: 12, color: 'var(--color-muted)' }}>{d.appVersion ? `app ${d.appVersion}` : '—'}</div>
                    </td>
                    <td>
                      <div>{since(d.lastSeenAt)}</div>
                      <div style={{ fontSize: 12, color: 'var(--color-muted)' }}>
                        first {d.firstSeenAt ? new Date(d.firstSeenAt).toLocaleDateString('en-IN') : '—'}
                      </div>
                    </td>
                    <td style={{ fontFamily: 'var(--font-mono, monospace)', fontSize: 12.5 }}>{d.lastIp ?? '—'}</td>
                    <td style={{ fontFamily: 'var(--font-mono, monospace)', fontSize: 11.5, wordBreak: 'break-all', maxWidth: 200 }}>
                      {d.deviceId}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      <p style={{ marginTop: 14, fontSize: 12.5, color: 'var(--color-muted)', maxWidth: '72ch' }}>
        What is recorded is what a handset reports about itself to any installed app —
        make, model, OS version — plus the address the request came from. No advertising
        identifier and no IMEI: Android stopped giving that out at version 10.
      </p>

      {shared && (
        <Modal onClose={() => setShared(null)} width={620}>
          <h3 style={{ margin: '0 0 6px', fontSize: 16, fontWeight: 700 }}>One handset, several accounts</h3>
          <p style={{ margin: '0 0 14px', fontSize: 13.5, color: 'var(--color-muted)' }}>
            These accounts have all signed in from <code>{shared.deviceId}</code>. For a
            family sharing a phone that is ordinary. For two <em>provider</em> accounts it
            is worth a question — binding an account to a device exists to stop a
            verified carer passing their phone on.
          </p>
          <div style={{ overflowX: 'auto' }}>
            <table className="data-table">
              <thead><tr><th>Account</th><th>Type</th><th>First seen</th><th>Last seen</th></tr></thead>
              <tbody>
                {shared.accounts.map((a) => (
                  <tr key={a.id}>
                    <td>
                      <div style={{ fontWeight: 600 }}>{a.ownerName ?? 'Unknown'}</div>
                      <div style={{ fontSize: 12, color: 'var(--color-muted)' }}>{a.ownerDisplayId ?? ''}</div>
                    </td>
                    <td><span className={`badge ${TYPE_BADGE[a.userType]}`}>{a.userType.replace('_', ' ')}</span></td>
                    <td>{a.firstSeenAt ? new Date(a.firstSeenAt).toLocaleDateString('en-IN') : '—'}</td>
                    <td>{since(a.lastSeenAt)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div style={{ marginTop: 16, textAlign: 'right' }}>
            <button className="btn-secondary" onClick={() => setShared(null)}>Close</button>
          </div>
        </Modal>
      )}
    </div>
  );
}
