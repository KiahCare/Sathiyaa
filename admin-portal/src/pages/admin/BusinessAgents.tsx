import { useEffect, useState, type FormEvent } from 'react';
import type { BusinessAgent, BusinessAgentReferral } from '../../types';
import { SERVICE_TYPE_LABELS } from '../../types';
import {
  listBusinessAgents, registerBusinessAgent, setBusinessAgentBlocked,
  listReferralsForAgent, getAgentRevenue, type AgentRevenueSummary, type NewBusinessAgentPayload,
} from '../../api/services';
import {
  PageHeader, StatusBadge, TableSkeleton, EmptyState, ErrorState, ConfirmDialog, Modal, InlineBanner,
} from '../../components/ui';

export default function BusinessAgents() {
  const [agents, setAgents] = useState<BusinessAgent[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [showRegister, setShowRegister] = useState(false);
  const [detailAgent, setDetailAgent] = useState<BusinessAgent | null>(null);
  const [blockTarget, setBlockTarget] = useState<BusinessAgent | null>(null);
  const [toast, setToast] = useState<string | null>(null);

  async function load() {
    setError(null);
    try {
      setAgents(await listBusinessAgents());
    } catch (err: any) {
      setError(err?.message ?? 'Failed to load business partners.');
    }
  }

  useEffect(() => { load(); }, []);
  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 3500);
    return () => clearTimeout(t);
  }, [toast]);

  async function handleToggleBlock(a: BusinessAgent) {
    const willBlock = a.status !== 'blocked';
    await setBusinessAgentBlocked(a.business_partner_id, willBlock);
    setToast(`${a.entity_name} has been ${willBlock ? 'blocked' : 'unblocked'}.`);
    setBlockTarget(null);
    load();
  }

  return (
    <div>
      <PageHeader
        title="Business Partners"
        subtitle="Register agencies/individuals who refer customers and manage their access."
        actions={<button className="btn btn-primary" onClick={() => setShowRegister(true)}>+ Register Business Partner</button>}
      />
      {toast && <InlineBanner kind="success">{toast}</InlineBanner>}

      <div className="card" style={{ overflow: 'hidden' }}>
        {agents === null && !error && <TableSkeleton rows={5} cols={6} />}
        {error && <ErrorState message={error} onRetry={load} />}
        {agents && agents.length === 0 && <EmptyState icon="🤝" title="No business partners yet" description="Register your first business partner to start tracking referrals." />}
        {agents && agents.length > 0 && (
          <div style={{ overflowX: 'auto' }}>
            <table className="data-table">
              <thead>
                <tr>
                  <th>Entity</th>
                  <th>Partner</th>
                  <th>Contact</th>
                  <th>Referral Code</th>
                  <th>Status</th>
                  <th>Registered</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {agents.map((a) => (
                  <tr key={a.business_partner_id}>
                    <td>
                      <div style={{ fontWeight: 600 }}>{a.entity_name}</div>
                      <div style={{ fontSize: 11.5, color: 'var(--color-text-muted)' }}>{a.display_id}</div>
                    </td>
                    <td>{a.partner_name}</td>
                    <td>
                      <div>{a.contact_number_1}</div>
                      {a.contact_number_2 && <div style={{ fontSize: 11.5, color: 'var(--color-text-muted)' }}>{a.contact_number_2}</div>}
                    </td>
                    <td><span className="badge badge-blue">{a.referral_code}</span></td>
                    <td><StatusBadge status={a.status} /></td>
                    <td>{new Date(a.created_at).toLocaleDateString('en-IN')}</td>
                    <td style={{ display: 'flex', gap: 8 }}>
                      <button className="btn btn-secondary btn-sm" onClick={() => setDetailAgent(a)}>View</button>
                      {a.status === 'blocked' ? (
                        <button className="btn btn-secondary btn-sm" onClick={() => setBlockTarget(a)}>Unblock</button>
                      ) : (
                        <button className="btn btn-danger btn-sm" onClick={() => setBlockTarget(a)}>Block</button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {showRegister && (
        <RegisterAgentModal
          onClose={() => setShowRegister(false)}
          onCreated={(a) => { setToast(`${a.entity_name} registered with referral code ${a.referral_code}.`); load(); }}
        />
      )}

      {detailAgent && <AgentDetailModal agent={detailAgent} onClose={() => setDetailAgent(null)} />}

      {blockTarget && (
        <ConfirmDialog
          title={blockTarget.status === 'blocked' ? 'Unblock business partner' : 'Block business partner'}
          description={
            blockTarget.status === 'blocked'
              ? `${blockTarget.entity_name} will regain access to the partner portal.`
              : `${blockTarget.entity_name} will lose access to the partner portal and cannot submit new referrals.`
          }
          confirmLabel={blockTarget.status === 'blocked' ? 'Unblock' : 'Block partner'}
          danger={blockTarget.status !== 'blocked'}
          onConfirm={() => handleToggleBlock(blockTarget)}
          onCancel={() => setBlockTarget(null)}
        />
      )}
    </div>
  );
}

function RegisterAgentModal({ onClose, onCreated }: { onClose: () => void; onCreated: (a: BusinessAgent) => void }) {
  const [form, setForm] = useState<NewBusinessAgentPayload>({
    entity_name: '', partner_name: '', contact_number_1: '', contact_number_2: '', email: '', address: '',
  });
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [submitting, setSubmitting] = useState(false);
  const [apiError, setApiError] = useState<string | null>(null);

  function set<K extends keyof NewBusinessAgentPayload>(key: K, value: string) {
    setForm((f) => ({ ...f, [key]: value }));
  }

  function validate(): boolean {
    const e: Record<string, string> = {};
    if (!form.entity_name.trim()) e.entity_name = 'Entity name is required.';
    if (!form.partner_name.trim()) e.partner_name = 'Partner name is required.';
    if (!/^\d{10}$/.test(form.contact_number_1)) e.contact_number_1 = 'Enter a valid 10-digit mobile number.';
    if (form.contact_number_2 && !/^\d{10}$/.test(form.contact_number_2)) e.contact_number_2 = 'Enter a valid 10-digit mobile number.';
    if (form.email && !/^\S+@\S+\.\S+$/.test(form.email)) e.email = 'Enter a valid email address.';
    setErrors(e);
    return Object.keys(e).length === 0;
  }

  async function handleSubmit(ev: FormEvent) {
    ev.preventDefault();
    setApiError(null);
    if (!validate()) return;
    setSubmitting(true);
    try {
      const agent = await registerBusinessAgent(form);
      onCreated(agent);
      onClose();
    } catch (err: any) {
      setApiError(err?.message ?? 'Failed to register business partner.');
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Modal onClose={onClose} width={560}>
      <form onSubmit={handleSubmit} style={{ padding: 26 }}>
        <h2 style={{ margin: '0 0 4px', fontSize: 18, fontWeight: 700 }}>Register Business Partner</h2>
        <p style={{ margin: '0 0 20px', fontSize: 13, color: 'var(--color-text-muted)' }}>An auto-generated ID and referral code will be issued on save.</p>

        {apiError && <div className="err-text" style={{ marginBottom: 14 }}>{apiError}</div>}

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14, marginBottom: 4 }}>
          <div style={{ gridColumn: '1 / -1' }}>
            <label className="field-label">Entity name</label>
            <input className={`input ${errors.entity_name ? 'err' : ''}`} value={form.entity_name} onChange={(e) => set('entity_name', e.target.value)} placeholder="e.g. Sunrise Elder Care Referrals" />
            {errors.entity_name && <div className="err-text">{errors.entity_name}</div>}
          </div>
          <div style={{ gridColumn: '1 / -1' }}>
            <label className="field-label">Partner name</label>
            <input className={`input ${errors.partner_name ? 'err' : ''}`} value={form.partner_name} onChange={(e) => set('partner_name', e.target.value)} placeholder="Contact person's full name" />
            {errors.partner_name && <div className="err-text">{errors.partner_name}</div>}
          </div>
          <div>
            <label className="field-label">Contact number 1</label>
            <input className={`input ${errors.contact_number_1 ? 'err' : ''}`} value={form.contact_number_1} onChange={(e) => set('contact_number_1', e.target.value)} placeholder="10-digit mobile" />
            {errors.contact_number_1 && <div className="err-text">{errors.contact_number_1}</div>}
          </div>
          <div>
            <label className="field-label">Contact number 2 <span style={{ fontWeight: 400, color: 'var(--color-text-muted)' }}>(optional)</span></label>
            <input className={`input ${errors.contact_number_2 ? 'err' : ''}`} value={form.contact_number_2} onChange={(e) => set('contact_number_2', e.target.value)} placeholder="10-digit mobile" />
            {errors.contact_number_2 && <div className="err-text">{errors.contact_number_2}</div>}
          </div>
          <div style={{ gridColumn: '1 / -1' }}>
            <label className="field-label">Email</label>
            <input className={`input ${errors.email ? 'err' : ''}`} value={form.email} onChange={(e) => set('email', e.target.value)} placeholder="partner@example.com" />
            {errors.email && <div className="err-text">{errors.email}</div>}
          </div>
          <div style={{ gridColumn: '1 / -1' }}>
            <label className="field-label">Address</label>
            <textarea className="input" rows={2} value={form.address} onChange={(e) => set('address', e.target.value)} />
          </div>
        </div>

        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 10, marginTop: 20 }}>
          <button type="button" className="btn btn-secondary" onClick={onClose} disabled={submitting}>Cancel</button>
          <button type="submit" className="btn btn-primary" disabled={submitting}>{submitting ? 'Registering…' : 'Register partner'}</button>
        </div>
      </form>
    </Modal>
  );
}

function AgentDetailModal({ agent, onClose }: { agent: BusinessAgent; onClose: () => void }) {
  const [referrals, setReferrals] = useState<BusinessAgentReferral[] | null>(null);
  const [revenue, setRevenue] = useState<AgentRevenueSummary | null>(null);
  const [tab, setTab] = useState<'referrals' | 'revenue'>('referrals');
  const [error, setError] = useState<string | null>(null);

  // Both calls used to be bare .then(). A rejected promise left the state at
  // null forever, and null is exactly what draws the loading skeleton -- so a
  // 403 was indistinguishable from a request that had not come back yet, on
  // both tabs, with nothing anywhere saying otherwise.
  async function load() {
    setError(null);
    setReferrals(null);
    setRevenue(null);
    try {
      const [r, rev] = await Promise.all([
        listReferralsForAgent(agent.business_partner_id),
        getAgentRevenue(agent.business_partner_id),
      ]);
      setReferrals(r);
      setRevenue(rev);
    } catch (err: any) {
      setError(err?.message ?? 'Could not load this partner.');
    }
  }

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [agent.business_partner_id]);

  return (
    <Modal onClose={onClose} width={720}>
      <div style={{ padding: 26 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 6 }}>
          <div>
            <h2 style={{ margin: 0, fontSize: 18, fontWeight: 700 }}>{agent.entity_name}</h2>
            <div style={{ fontSize: 13, color: 'var(--color-text-muted)' }}>{agent.partner_name} · {agent.display_id} · Code {agent.referral_code}</div>
          </div>
          <StatusBadge status={agent.status} />
        </div>

        <div className="tabs" style={{ margin: '18px 0 16px' }}>
          <button className={`tab-btn ${tab === 'referrals' ? 'active' : ''}`} onClick={() => setTab('referrals')}>Referrals</button>
          <button className={`tab-btn ${tab === 'revenue' ? 'active' : ''}`} onClick={() => setTab('revenue')}>Revenue Earned</button>
        </div>

        {error && <ErrorState message={error} onRetry={load} />}

        {tab === 'referrals' && !error && (
          <div style={{ maxHeight: 380, overflowY: 'auto' }}>
            {referrals === null && <TableSkeleton rows={3} cols={4} />}
            {referrals && referrals.length === 0 && <EmptyState title="No referrals yet" description="Referrals submitted by this partner will appear here." />}
            {referrals && referrals.length > 0 && (
              <table className="data-table">
                <thead>
                  <tr><th>Customer</th><th>Service</th><th>Duration</th><th>Status</th><th>Hours used</th></tr>
                </thead>
                <tbody>
                  {referrals.map((r) => (
                    <tr key={r.id}>
                      <td>{r.customer_name}<div style={{ fontSize: 11, color: 'var(--color-text-muted)' }}>{r.referral_code}</div></td>
                      <td>{SERVICE_TYPE_LABELS[r.service_type]}</td>
                      <td>{r.duration_start} → {r.duration_end}</td>
                      <td><span className={`badge ${r.status === 'completed' ? 'badge-green' : r.status === 'cancelled' ? 'badge-red' : r.status === 'booked' ? 'badge-blue' : 'badge-gray'}`}>{r.status}</span></td>
                      <td>{r.hours_used ?? 0} hrs</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        )}

        {tab === 'revenue' && !error && (
          <div>
            {revenue === null ? (
              <TableSkeleton rows={3} cols={3} />
            ) : (
              <>
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 12, marginBottom: 18 }}>
                  <div className="card" style={{ padding: 14 }}>
                    <div style={{ fontSize: 11.5, color: 'var(--color-text-muted)', textTransform: 'uppercase' }}>Total earned</div>
                    <div style={{ fontSize: 20, fontWeight: 700, marginTop: 4 }}>₹{revenue.total_earned.toLocaleString('en-IN')}</div>
                  </div>
                  <div className="card" style={{ padding: 14 }}>
                    <div style={{ fontSize: 11.5, color: 'var(--color-text-muted)', textTransform: 'uppercase' }}>Hours used</div>
                    <div style={{ fontSize: 20, fontWeight: 700, marginTop: 4 }}>{revenue.total_hours_used}</div>
                  </div>
                  <div className="card" style={{ padding: 14 }}>
                    <div style={{ fontSize: 11.5, color: 'var(--color-text-muted)', textTransform: 'uppercase' }}>Referrals</div>
                    <div style={{ fontSize: 20, fontWeight: 700, marginTop: 4 }}>{revenue.total_referrals}</div>
                  </div>
                </div>
                <div style={{ maxHeight: 260, overflowY: 'auto' }}>
                  {revenue.by_referral.length === 0 ? (
                    <EmptyState title="No revenue yet" description="Revenue accrues once referred customers use billable hours." />
                  ) : (
                    <table className="data-table">
                      <thead><tr><th>Customer</th><th>Service</th><th>Hours × Rate</th><th>Revenue</th></tr></thead>
                      <tbody>
                        {revenue.by_referral.map((r) => (
                          <tr key={r.referral_id}>
                            <td>{r.customer_name}</td>
                            <td>{SERVICE_TYPE_LABELS[r.service_type]}</td>
                            <td>{r.hours_used} hrs × ₹{r.flat_rate_per_hour}</td>
                            <td style={{ fontWeight: 600 }}>₹{r.revenue.toLocaleString('en-IN')}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  )}
                </div>
              </>
            )}
          </div>
        )}

        <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 20 }}>
          <button className="btn btn-secondary" onClick={onClose}>Close</button>
        </div>
      </div>
    </Modal>
  );
}
