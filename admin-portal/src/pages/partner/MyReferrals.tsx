import { useEffect, useState, type FormEvent } from 'react';
import { useAuth } from '../../context/AuthContext';
import type { BusinessAgentReferral, Gender, ServiceType } from '../../types';
import { SERVICE_TYPE_LABELS } from '../../types';
import { listMyReferrals, createReferral, type NewReferralPayload } from '../../api/services';
import { PageHeader, TableSkeleton, EmptyState, ErrorState, Modal, InlineBanner } from '../../components/ui';

const SERVICE_OPTIONS: ServiceType[] = ['companion', 'medical_companion', 'nurse'];

const STATUS_CLASS: Record<string, string> = {
  pending: 'badge-gray', booked: 'badge-blue', completed: 'badge-green', cancelled: 'badge-red',
};

const emptyForm: NewReferralPayload = {
  customer_name: '', gender: 'female', service_type: 'companion',
  duration_start: '', duration_end: '', time_from: '09:00', time_to: '17:00',
  mobile_number: '', address: '',
};

export default function MyReferrals() {
  const { user } = useAuth();
  const [referrals, setReferrals] = useState<BusinessAgentReferral[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [successCode, setSuccessCode] = useState<string | null>(null);

  async function load() {
    if (!user) return;
    setError(null);
    try {
      setReferrals(await listMyReferrals(user.id));
    } catch (err: any) {
      setError(err?.message ?? 'Failed to load referrals.');
    }
  }

  useEffect(() => { load(); }, [user?.id]);

  return (
    <div>
      <PageHeader
        title="My Referrals"
        subtitle="Customers you've referred to Sathiyaa, and their booking status."
        actions={<button className="btn btn-primary" onClick={() => setShowForm(true)}>+ Refer a Customer</button>}
      />

      {successCode && (
        <InlineBanner kind="success">
          Referral submitted. Share this code with your customer if needed: <strong>{successCode}</strong>
        </InlineBanner>
      )}

      <div className="card" style={{ overflow: 'hidden' }}>
        {referrals === null && !error && <TableSkeleton rows={6} cols={6} />}
        {error && <ErrorState message={error} onRetry={load} />}
        {referrals && referrals.length === 0 && (
          <EmptyState icon="🧾" title="No referrals yet" description="Use “Refer a Customer” to submit your first referral." />
        )}
        {referrals && referrals.length > 0 && (
          <div style={{ overflowX: 'auto' }}>
            <table className="data-table">
              <thead>
                <tr>
                  <th>Referral code</th>
                  <th>Customer</th>
                  <th>Service</th>
                  <th>Duration</th>
                  <th>Time</th>
                  <th>Status</th>
                  <th>Hours used</th>
                </tr>
              </thead>
              <tbody>
                {referrals.map((r) => (
                  <tr key={r.id}>
                    <td><span className="badge badge-blue">{r.referral_code}</span></td>
                    <td>
                      <div style={{ fontWeight: 600 }}>{r.customer_name}</div>
                      <div style={{ fontSize: 11.5, color: 'var(--color-text-muted)' }}>{r.mobile_number}</div>
                    </td>
                    <td>{SERVICE_TYPE_LABELS[r.service_type]}</td>
                    <td>{r.duration_start} → {r.duration_end}</td>
                    <td>{r.time_from}–{r.time_to}</td>
                    <td><span className={`badge ${STATUS_CLASS[r.status]}`}>{r.status}</span></td>
                    <td>{r.hours_used ?? 0} hrs</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {showForm && user && (
        <ReferCustomerModal
          onClose={() => setShowForm(false)}
          onCreated={(r) => { setSuccessCode(r.referral_code); setShowForm(false); load(); }}
          businessPartnerId={user.id}
        />
      )}
    </div>
  );
}

function ReferCustomerModal({
  onClose, onCreated, businessPartnerId,
}: {
  onClose: () => void;
  onCreated: (r: BusinessAgentReferral) => void;
  businessPartnerId: number;
}) {
  const [form, setForm] = useState<NewReferralPayload>(emptyForm);
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [submitting, setSubmitting] = useState(false);
  const [apiError, setApiError] = useState<string | null>(null);

  function set<K extends keyof NewReferralPayload>(key: K, value: NewReferralPayload[K]) {
    setForm((f) => ({ ...f, [key]: value }));
  }

  function validate(): boolean {
    const e: Record<string, string> = {};
    if (!form.customer_name.trim()) e.customer_name = 'Customer name is required.';
    if (!/^\d{10}$/.test(form.mobile_number)) e.mobile_number = 'Enter a valid 10-digit mobile number.';
    if (!form.duration_start) e.duration_start = 'Start date is required.';
    if (!form.duration_end) e.duration_end = 'End date is required.';
    if (form.duration_start && form.duration_end && form.duration_end < form.duration_start) {
      e.duration_end = 'End date must be on or after the start date.';
    }
    if (form.time_from && form.time_to && form.time_to <= form.time_from) {
      e.time_to = 'End time must be after start time.';
    }
    if (!form.address.trim()) e.address = 'Address is required.';
    setErrors(e);
    return Object.keys(e).length === 0;
  }

  async function handleSubmit(ev: FormEvent) {
    ev.preventDefault();
    setApiError(null);
    if (!validate()) return;
    setSubmitting(true);
    try {
      const referral = await createReferral(businessPartnerId, form);
      onCreated(referral);
    } catch (err: any) {
      setApiError(err?.message ?? 'Failed to submit referral.');
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Modal onClose={onClose} width={580}>
      <form onSubmit={handleSubmit} style={{ padding: 26 }}>
        <h2 style={{ margin: '0 0 4px', fontSize: 18, fontWeight: 700 }}>Refer a Customer</h2>
        <p style={{ margin: '0 0 20px', fontSize: 13, color: 'var(--color-text-muted)' }}>A referral code is generated once submitted.</p>

        {apiError && <div className="err-text" style={{ marginBottom: 14 }}>{apiError}</div>}

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14 }}>
          <div style={{ gridColumn: '1 / -1' }}>
            <label className="field-label">Customer name</label>
            <input className={`input ${errors.customer_name ? 'err' : ''}`} value={form.customer_name} onChange={(e) => set('customer_name', e.target.value)} />
            {errors.customer_name && <div className="err-text">{errors.customer_name}</div>}
          </div>
          <div>
            <label className="field-label">Gender</label>
            <select className="input" value={form.gender} onChange={(e) => set('gender', e.target.value as Gender)}>
              <option value="female">Female</option>
              <option value="male">Male</option>
              <option value="other">Other</option>
            </select>
          </div>
          <div>
            <label className="field-label">Service type</label>
            <select className="input" value={form.service_type} onChange={(e) => set('service_type', e.target.value as ServiceType)}>
              {SERVICE_OPTIONS.map((s) => <option key={s} value={s}>{SERVICE_TYPE_LABELS[s]}</option>)}
            </select>
          </div>
          <div>
            <label className="field-label">Duration start</label>
            <input type="date" className={`input ${errors.duration_start ? 'err' : ''}`} value={form.duration_start} onChange={(e) => set('duration_start', e.target.value)} />
            {errors.duration_start && <div className="err-text">{errors.duration_start}</div>}
          </div>
          <div>
            <label className="field-label">Duration end</label>
            <input type="date" className={`input ${errors.duration_end ? 'err' : ''}`} value={form.duration_end} onChange={(e) => set('duration_end', e.target.value)} />
            {errors.duration_end && <div className="err-text">{errors.duration_end}</div>}
          </div>
          <div>
            <label className="field-label">Time from</label>
            <input type="time" className="input" value={form.time_from} onChange={(e) => set('time_from', e.target.value)} />
          </div>
          <div>
            <label className="field-label">Time to</label>
            <input type="time" className={`input ${errors.time_to ? 'err' : ''}`} value={form.time_to} onChange={(e) => set('time_to', e.target.value)} />
            {errors.time_to && <div className="err-text">{errors.time_to}</div>}
          </div>
          <div>
            <label className="field-label">Mobile number</label>
            <input className={`input ${errors.mobile_number ? 'err' : ''}`} value={form.mobile_number} onChange={(e) => set('mobile_number', e.target.value)} placeholder="10-digit mobile" />
            {errors.mobile_number && <div className="err-text">{errors.mobile_number}</div>}
          </div>
          <div style={{ gridColumn: '1 / -1' }}>
            <label className="field-label">Address</label>
            <textarea className={`input ${errors.address ? 'err' : ''}`} rows={2} value={form.address} onChange={(e) => set('address', e.target.value)} />
            {errors.address && <div className="err-text">{errors.address}</div>}
          </div>
        </div>

        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 10, marginTop: 20 }}>
          <button type="button" className="btn btn-secondary" onClick={onClose} disabled={submitting}>Cancel</button>
          <button type="submit" className="btn btn-primary" disabled={submitting}>{submitting ? 'Submitting…' : 'Submit referral'}</button>
        </div>
      </form>
    </Modal>
  );
}
