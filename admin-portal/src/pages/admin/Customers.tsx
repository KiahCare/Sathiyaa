import { useEffect, useState } from 'react';
import type { Customer, CustomerStatus } from '../../types';
import { listCustomers, setCustomerBlocked } from '../../api/services';
import { uploadUrl } from '../../api/client';
import {
  PageHeader, StatusBadge, TableSkeleton, EmptyState, ErrorState, ConfirmDialog, InlineBanner,
} from '../../components/ui';

type SortKey = 'created_at' | 'name';

const STATUS_TABS: { value: CustomerStatus | 'all'; label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'active', label: 'Active' },
  { value: 'pending_payment', label: 'Pending Payment' },
  { value: 'blocked', label: 'Blocked' },
];

export default function Customers() {
  const [customers, setCustomers] = useState<Customer[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<CustomerStatus | 'all'>('all');
  const [search, setSearch] = useState('');
  const [sortKey, setSortKey] = useState<SortKey>('created_at');
  const [toast, setToast] = useState<string | null>(null);
  const [target, setTarget] = useState<Customer | null>(null);

  async function load() {
    setError(null);
    try {
      const items = await listCustomers({ status, search: search || undefined });
      setCustomers(items);
    } catch (err: any) {
      setError(err?.message ?? 'Failed to load customers.');
    }
  }

  useEffect(() => {
    setCustomers(null);
    const t = setTimeout(load, search ? 300 : 0);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [status, search]);

  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 3200);
    return () => clearTimeout(t);
  }, [toast]);

  const sorted = customers
    ? [...customers].sort((a, b) =>
        sortKey === 'name' ? a.name.localeCompare(b.name) : (a.created_at < b.created_at ? 1 : -1)
      )
    : null;

  async function handleToggleBlock(c: Customer) {
    const willBlock = c.status !== 'blocked';
    await setCustomerBlocked(c.customer_id, willBlock);
    setToast(`${c.name} has been ${willBlock ? 'blocked' : 'unblocked'}.`);
    setTarget(null);
    load();
  }

  return (
    <div>
      <PageHeader title="Customers" subtitle="Search, sort, and manage customer accounts." />
      {toast && <InlineBanner kind="success">{toast}</InlineBanner>}

      <div className="card" style={{ marginBottom: 16, padding: '14px 16px', display: 'flex', gap: 16, flexWrap: 'wrap', alignItems: 'center' }}>
        <div className="tabs" style={{ borderBottom: 'none', flexWrap: 'wrap' }}>
          {STATUS_TABS.map((t) => (
            <button key={t.value} className={`tab-btn ${status === t.value ? 'active' : ''}`} onClick={() => setStatus(t.value)} style={{ marginRight: 18 }}>
              {t.label}
            </button>
          ))}
        </div>
        <select className="input" style={{ maxWidth: 170 }} value={sortKey} onChange={(e) => setSortKey(e.target.value as SortKey)}>
          <option value="created_at">Sort: Newest first</option>
          <option value="name">Sort: Name (A–Z)</option>
        </select>
        <input
          className="input"
          placeholder="Search by name, ID, or mobile…"
          style={{ maxWidth: 260, marginLeft: 'auto' }}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
      </div>

      <div className="card" style={{ overflow: 'hidden' }}>
        {sorted === null && !error && <TableSkeleton rows={7} cols={6} />}
        {error && <ErrorState message={error} onRetry={load} />}
        {sorted && sorted.length === 0 && <EmptyState icon="👥" title="No customers found" description="Try a different filter or search term." />}
        {sorted && sorted.length > 0 && (
          <div style={{ overflowX: 'auto' }}>
            <table className="data-table">
              <thead>
                <tr>
                  <th>Customer</th>
                  <th>ID</th>
                  <th>Mobile</th>
                  <th>City</th>
                  <th>Referred by</th>
                  <th>Status</th>
                  <th>Joined</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {sorted.map((c) => (
                  <tr key={c.customer_id}>
                    <td>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                        <img src={uploadUrl(c.photo_url)} alt="" style={{ width: 30, height: 30, borderRadius: '50%', objectFit: 'cover', background: '#eee' }} />
                        <div>
                          <div style={{ fontWeight: 600 }}>{c.name}</div>
                          <div style={{ fontSize: 11.5, color: 'var(--color-text-muted)' }}>{c.gender}</div>
                        </div>
                      </div>
                    </td>
                    <td>{c.display_id}</td>
                    <td>{c.mobile_number}</td>
                    <td>{c.city ?? '—'}</td>
                    <td>{c.referred_by_code ?? '—'}</td>
                    <td><StatusBadge status={c.status} /></td>
                    <td>{new Date(c.created_at).toLocaleDateString('en-IN')}</td>
                    <td>
                      {c.status === 'blocked' ? (
                        <button className="btn btn-secondary btn-sm" onClick={() => setTarget(c)}>Unblock</button>
                      ) : (
                        <button className="btn btn-danger btn-sm" onClick={() => setTarget(c)}>Block</button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {target && (
        <ConfirmDialog
          title={target.status === 'blocked' ? 'Unblock customer' : 'Block customer'}
          description={
            target.status === 'blocked'
              ? `${target.name} will regain login access to the Sathiyaa app.`
              : `${target.name} will be blocked from logging in and booking services.`
          }
          confirmLabel={target.status === 'blocked' ? 'Unblock' : 'Block customer'}
          danger={target.status !== 'blocked'}
          onConfirm={() => handleToggleBlock(target)}
          onCancel={() => setTarget(null)}
        />
      )}
    </div>
  );
}
