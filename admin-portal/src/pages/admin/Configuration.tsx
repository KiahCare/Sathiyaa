import { useEffect, useRef, useState } from 'react';
import type { AppConfiguration, RevenueSharingConfig, TimeBankConfig, ServiceType, ServiceAreaConfig } from '../../types';
import { SERVICE_TYPE_LABELS } from '../../types';
import {
  getConfig, updateConfig, getRevenueSharing, updateRevenueSharing,
  getTimeBankConfig, updateTimeBankConfig,
  getServiceAreaConfig, updateServiceAreaConfig,
} from '../../api/services';
import { PageHeader, ErrorState, InlineBanner } from '../../components/ui';

const EXAMPLE_HOURS = 20;
const SERVICE_TYPES = Object.keys(SERVICE_TYPE_LABELS) as ServiceType[];
const CURRENT_YEAR = new Date().getFullYear();

export default function Configuration() {
  const [config, setConfig] = useState<AppConfiguration | null>(null);
  const [revShare, setRevShare] = useState<RevenueSharingConfig[] | null>(null);
  const [timeBank, setTimeBank] = useState<TimeBankConfig[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [savingConfig, setSavingConfig] = useState(false);
  const [savingRevShare, setSavingRevShare] = useState(false);
  const [savingTimeBank, setSavingTimeBank] = useState(false);
  const [toast, setToast] = useState<string | null>(null);
  const [area, setArea] = useState<ServiceAreaConfig | null>(null);
  const [savingArea, setSavingArea] = useState(false);
  const [sameCustomerFee, setSameCustomerFee] = useState(false);
  const [sameProviderFee, setSameProviderFee] = useState(false);
  const draftIdRef = useRef(-1);

  async function load() {
    setError(null);
    try {
      const [cfg, rs, tb, sa] = await Promise.all([
        getConfig(), getRevenueSharing(), getTimeBankConfig(), getServiceAreaConfig(),
      ]);
      setConfig(cfg);
      setArea(sa);
      setRevShare(rs);
      setTimeBank(tb);
      setSameCustomerFee(cfg.customer_annual_fee_new === cfg.customer_annual_fee_existing);
      setSameProviderFee(cfg.provider_annual_fee_new === cfg.provider_annual_fee_existing);
    } catch (err: any) {
      setError(err?.message ?? 'Failed to load configuration.');
    }
  }

  useEffect(() => { load(); }, []);
  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 3200);
    return () => clearTimeout(t);
  }, [toast]);

  function setConfigField<K extends keyof AppConfiguration>(key: K, value: number) {
    setConfig((c) => (c ? { ...c, [key]: value } : c));
  }

  async function handleSaveConfig() {
    if (!config) return;
    if (config.org_revenue_share_percent < 0 || config.org_revenue_share_percent > 100) {
      setError('Organization revenue share must be between 0 and 100.');
      return;
    }
    setError(null);
    setSavingConfig(true);
    try {
      const payload: AppConfiguration = {
        ...config,
        customer_annual_fee_existing: sameCustomerFee ? config.customer_annual_fee_new : config.customer_annual_fee_existing,
        provider_annual_fee_existing: sameProviderFee ? config.provider_annual_fee_new : config.provider_annual_fee_existing,
      };
      const saved = await updateConfig(payload);
      setConfig(saved);
      setToast('Fee configuration saved. Renewal fees will reflect the updated amounts.');
    } catch (err: any) {
      setError(err?.message ?? 'Failed to save configuration.');
    } finally {
      setSavingConfig(false);
    }
  }

  async function handleSaveArea() {
    if (!area) return;
    if (area.city.trim().length < 2) {
      setError('Enter the name of the city Sathiyaa operates in.');
      return;
    }
    if (!Number.isFinite(area.lat) || area.lat < -90 || area.lat > 90 ||
        !Number.isFinite(area.lng) || area.lng < -180 || area.lng > 180) {
      setError('Those coordinates are not a place on Earth. Check the latitude and longitude.');
      return;
    }
    if (!(area.radius_km >= 1)) {
      setError('The radius has to be at least 1 km.');
      return;
    }
    setError(null);
    setSavingArea(true);
    try {
      setArea(await updateServiceAreaConfig(area));
      setToast(
        area.enabled
          ? `Saved. New sign-ups outside ${area.city} will be put on the waiting list.`
          : 'Saved. Anybody can now register, from anywhere.'
      );
    } catch (err: any) {
      setError(err?.message ?? 'Failed to save the service area.');
    } finally {
      setSavingArea(false);
    }
  }

  function setRevShareField(service_type: ServiceType, key: keyof RevenueSharingConfig, value: number) {
    setRevShare((list) => list?.map((r) => (r.service_type === service_type ? { ...r, [key]: value } : r)) ?? list);
  }

  async function handleSaveRevShare() {
    if (!revShare) return;
    setError(null);
    setSavingRevShare(true);
    try {
      const saved = await updateRevenueSharing(revShare);
      setRevShare(saved);
      setToast('Revenue sharing rates saved.');
    } catch (err: any) {
      setError(err?.message ?? 'Failed to save revenue sharing.');
    } finally {
      setSavingRevShare(false);
    }
  }

  function setTimeBankField<K extends keyof TimeBankConfig>(id: number, key: K, value: TimeBankConfig[K]) {
    setTimeBank((list) => list?.map((r) => (r.id === id ? { ...r, [key]: value } : r)) ?? list);
  }

  function addTimeBankRow() {
    setTimeBank((list) => {
      const years = (list ?? []).map((r) => r.application_year);
      const year = years.length ? Math.max(...years) : CURRENT_YEAR;
      const newRow: TimeBankConfig = {
        id: draftIdRef.current--,
        service_type: 'companion',
        points_per_hour: 0,
        application_year: year,
        updated_by: null,
        updated_at: new Date().toISOString(),
      };
      return [newRow, ...(list ?? [])];
    });
  }

  // Only unsaved draft rows (negative local id) can be removed — the backend
  // endpoint only upserts by (service_type, application_year) and has no
  // delete, so a persisted row would simply reappear on the next save.
  function removeTimeBankRow(id: number) {
    setTimeBank((list) => list?.filter((r) => r.id !== id) ?? list);
  }

  async function handleSaveTimeBank() {
    if (!timeBank) return;
    const seen = new Set<string>();
    for (const row of timeBank) {
      const key = `${row.service_type}-${row.application_year}`;
      if (seen.has(key)) {
        setError(`Duplicate row for ${SERVICE_TYPE_LABELS[row.service_type]} in ${row.application_year} — each service/year combination can only appear once.`);
        return;
      }
      seen.add(key);
      if (!Number.isInteger(row.application_year) || row.application_year < 2000 || row.application_year > 2100) {
        setError('Application year must be a valid year between 2000 and 2100.');
        return;
      }
      if (row.points_per_hour < 0) {
        setError('Points per hour cannot be negative.');
        return;
      }
    }
    setError(null);
    setSavingTimeBank(true);
    try {
      const saved = await updateTimeBankConfig(timeBank);
      setTimeBank(saved);
      setToast('Time Bank points configuration saved.');
    } catch (err: any) {
      setError(err?.message ?? 'Failed to save Time Bank configuration.');
    } finally {
      setSavingTimeBank(false);
    }
  }

  if (error && !config) return <ErrorState message={error} onRetry={load} />;

  const orgShareInvalid = !!config && (config.org_revenue_share_percent < 0 || config.org_revenue_share_percent > 100);
  const sortedTimeBank = timeBank
    ? [...timeBank].sort((a, b) => b.application_year - a.application_year || a.service_type.localeCompare(b.service_type))
    : [];

  return (
    <div>
      <PageHeader title="Configuration" subtitle="Service area, booking amount, annual fees, revenue sharing, and Time Bank points." />
      {toast && <InlineBanner kind="success">{toast}</InlineBanner>}
      {error && config && <InlineBanner kind="error">{error}</InlineBanner>}

      <div className="card" style={{ padding: 22, marginBottom: 20 }}>
        <h2 style={{ margin: '0 0 4px', fontSize: 16, fontWeight: 700 }}>Booking &amp; Registration Fees</h2>
        <p style={{ margin: '0 0 18px', fontSize: 13, color: 'var(--color-text-muted)' }}>
          Applies platform-wide. Annual fees may be set the same for new and existing users, or different.
        </p>

        {!config ? (
          <div className="skeleton" style={{ height: 160 }} />
        ) : (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: 20 }}>
            <div>
              <label className="field-label">Customer booking amount (₹)</label>
              <input
                type="number" className="input" value={config.customer_booking_amount}
                onChange={(e) => setConfigField('customer_booking_amount', Number(e.target.value))}
              />
              <div className="field-hint">Charged to customer when a booking is confirmed.</div>
            </div>

            <div style={{ gridColumn: 'span 2' }}>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 6 }}>
                <label className="field-label" style={{ marginBottom: 0 }}>Customer annual registration fee (₹)</label>
                <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, color: 'var(--color-text-muted)', cursor: 'pointer' }}>
                  <input type="checkbox" checked={sameCustomerFee} onChange={(e) => setSameCustomerFee(e.target.checked)} />
                  Same for new &amp; existing
                </label>
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
                <div>
                  <input
                    type="number" className="input" value={config.customer_annual_fee_new}
                    onChange={(e) => setConfigField('customer_annual_fee_new', Number(e.target.value))}
                  />
                  <div className="field-hint">
                    New customer. Set to 0 and no fee is charged at all — the app shows
                    &ldquo;nothing to pay&rdquo; instead of a payment screen.
                  </div>
                </div>
                <div>
                  <input
                    type="number" className="input" disabled={sameCustomerFee}
                    value={sameCustomerFee ? config.customer_annual_fee_new : config.customer_annual_fee_existing}
                    onChange={(e) => setConfigField('customer_annual_fee_existing', Number(e.target.value))}
                  />
                  <div className="field-hint">
                    Existing customer. Charged a year after they last paid. Nothing is cut
                    off when that year passes &mdash; the app simply offers to renew.
                  </div>
                </div>
              </div>
            </div>

            <div style={{ gridColumn: 'span 2' }}>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 6 }}>
                <label className="field-label" style={{ marginBottom: 0 }}>Provider annual registration fee (₹)</label>
                <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, color: 'var(--color-text-muted)', cursor: 'pointer' }}>
                  <input type="checkbox" checked={sameProviderFee} onChange={(e) => setSameProviderFee(e.target.checked)} />
                  Same for new &amp; existing
                </label>
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
                <div>
                  <input
                    type="number" className="input" value={config.provider_annual_fee_new}
                    onChange={(e) => setConfigField('provider_annual_fee_new', Number(e.target.value))}
                  />
                  <div className="field-hint">New provider</div>
                </div>
                <div>
                  <input
                    type="number" className="input" disabled={sameProviderFee}
                    value={sameProviderFee ? config.provider_annual_fee_new : config.provider_annual_fee_existing}
                    onChange={(e) => setConfigField('provider_annual_fee_existing', Number(e.target.value))}
                  />
                  <div className="field-hint">
                    Existing provider, a year after they last paid.
                  </div>
                </div>
              </div>
            </div>
          </div>
        )}

        <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 20 }}>
          <button className="btn btn-primary" onClick={handleSaveConfig} disabled={!config || savingConfig}>
            {savingConfig ? 'Saving…' : 'Save fee configuration'}
          </button>
        </div>
      </div>

      <div className="card" style={{ padding: 22, marginBottom: 20 }}>
        <h2 style={{ margin: '0 0 4px', fontSize: 16, fontWeight: 700 }}>Where Sathiyaa operates</h2>
        <p style={{ margin: '0 0 18px', fontSize: 13, color: 'var(--color-text-muted)' }}>
          Both apps ask the phone where it is once, straight after registration, and anybody
          outside this area is kept on a waiting list instead of being let in to a search that
          would find nobody. They keep their account, and they are counted in Reports → where
          people are signing up from. Changing the city here takes effect immediately, with no
          new app release.
        </p>

        {!area ? (
          <div className="skeleton" style={{ height: 140 }} />
        ) : (
          <>
            <label style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 18, cursor: 'pointer' }}>
              <input
                type="checkbox"
                checked={area.enabled}
                onChange={(e) => setArea({ ...area, enabled: e.target.checked })}
              />
              <span style={{ fontSize: 13 }}>
                Restrict new registrations to this area
                <span style={{ color: 'var(--color-text-muted)' }}>
                  {' '}— untick to let anybody, anywhere, use the apps
                </span>
              </span>
            </label>

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(190px, 1fr))', gap: 20, opacity: area.enabled ? 1 : 0.5 }}>
              <div>
                <label className="field-label">City</label>
                <input
                  className="input" value={area.city} disabled={!area.enabled}
                  onChange={(e) => setArea({ ...area, city: e.target.value })}
                />
                <div className="field-hint">Matched loosely against what the geocoder returns.</div>
              </div>
              <div>
                <label className="field-label">State</label>
                <input
                  className="input" value={area.state} disabled={!area.enabled}
                  onChange={(e) => setArea({ ...area, state: e.target.value })}
                />
                <div className="field-hint">Used when the geocoder gives no city.</div>
              </div>
              <div>
                <label className="field-label">Radius (km)</label>
                <input
                  type="number" className="input" value={area.radius_km} disabled={!area.enabled}
                  onChange={(e) => setArea({ ...area, radius_km: Number(e.target.value) })}
                />
                <div className="field-hint">Be generous. Turning away somebody who is in the catchment loses them for good.</div>
              </div>
              <div>
                <label className="field-label">Centre latitude</label>
                <input
                  type="number" step="0.0001" className="input" value={area.lat} disabled={!area.enabled}
                  onChange={(e) => setArea({ ...area, lat: Number(e.target.value) })}
                />
              </div>
              <div>
                <label className="field-label">Centre longitude</label>
                <input
                  type="number" step="0.0001" className="input" value={area.lng} disabled={!area.enabled}
                  onChange={(e) => setArea({ ...area, lng: Number(e.target.value) })}
                />
              </div>
            </div>
          </>
        )}

        <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 20 }}>
          <button className="btn btn-primary" onClick={handleSaveArea} disabled={!area || savingArea}>
            {savingArea ? 'Saving…' : 'Save service area'}
          </button>
        </div>
      </div>

      <div className="card" style={{ padding: 22, marginBottom: 20 }}>
        <h2 style={{ margin: '0 0 4px', fontSize: 16, fontWeight: 700 }}>Organization Revenue Share</h2>
        <p style={{ margin: '0 0 18px', fontSize: 13, color: 'var(--color-text-muted)' }}>
          Applied on top of each organization's own per-service fee — e.g. an organization charging ₹100/hr with a 20% share shows as ₹120/hr to the customer. Freelancers are unaffected — they use the revenue sharing rates below instead.
        </p>

        {!config ? (
          <div className="skeleton" style={{ height: 60 }} />
        ) : (
          <div style={{ maxWidth: 220 }}>
            <label className="field-label">Organization revenue share</label>
            <div style={{ position: 'relative' }}>
              <input
                type="number" min={0} max={100} step={1}
                className={`input ${orgShareInvalid ? 'err' : ''}`}
                style={{ paddingRight: 32 }}
                value={config.org_revenue_share_percent}
                onChange={(e) => setConfigField('org_revenue_share_percent', Number(e.target.value))}
              />
              <span style={{ position: 'absolute', right: 12, top: '50%', transform: 'translateY(-50%)', fontSize: 13, color: 'var(--color-text-muted)', pointerEvents: 'none' }}>
                %
              </span>
            </div>
            {orgShareInvalid ? (
              <div className="err-text">Must be between 0 and 100.</div>
            ) : (
              <div className="field-hint">Sathiyaa's markup, as a percentage of the organization's own hourly fee.</div>
            )}
          </div>
        )}

        <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 20 }}>
          <button className="btn btn-primary" onClick={handleSaveConfig} disabled={!config || savingConfig || orgShareInvalid}>
            {savingConfig ? 'Saving…' : 'Save'}
          </button>
        </div>
      </div>

      <div className="card" style={{ padding: 22, marginBottom: 20 }}>
        <h2 style={{ margin: '0 0 4px', fontSize: 16, fontWeight: 700 }}>Revenue Sharing by Service Type</h2>
        <p style={{ margin: '0 0 18px', fontSize: 13, color: 'var(--color-text-muted)' }}>
          Set the customer-facing rate, what the provider earns, and the flat business-partner rate per hour, for each service.
        </p>

        {!revShare ? (
          <div className="skeleton" style={{ height: 320 }} />
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
            {revShare.map((r) => (
              <RevShareRow key={r.service_type} row={r} onChange={setRevShareField} />
            ))}
          </div>
        )}

        <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 20 }}>
          <button className="btn btn-primary" onClick={handleSaveRevShare} disabled={!revShare || savingRevShare}>
            {savingRevShare ? 'Saving…' : 'Save revenue sharing'}
          </button>
        </div>
      </div>

      <div className="card" style={{ padding: 22 }}>
        <h2 style={{ margin: '0 0 4px', fontSize: 16, fontWeight: 700 }}>Time Bank — Points per Hour</h2>
        <p style={{ margin: '0 0 18px', fontSize: 13, color: 'var(--color-text-muted)' }}>
          Points a No-Fees (volunteer) provider earns per donated hour of a service, by application year. All years are shown below, sorted newest first — add a row for a new year or service.
        </p>

        {!timeBank ? (
          <div className="skeleton" style={{ height: 220 }} />
        ) : (
          <>
            <div style={{ overflowX: 'auto' }}>
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Service Type</th>
                    <th>Points / Hour</th>
                    <th>Application Year</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  {sortedTimeBank.map((row) => (
                    <tr key={row.id}>
                      <td style={{ minWidth: 190 }}>
                        <select
                          className="input"
                          value={row.service_type}
                          onChange={(e) => setTimeBankField(row.id, 'service_type', e.target.value as ServiceType)}
                        >
                          {SERVICE_TYPES.map((st) => (
                            <option key={st} value={st}>{SERVICE_TYPE_LABELS[st]}</option>
                          ))}
                        </select>
                      </td>
                      <td style={{ minWidth: 130 }}>
                        <input
                          type="number" min={0} className="input" value={row.points_per_hour}
                          onChange={(e) => setTimeBankField(row.id, 'points_per_hour', Number(e.target.value))}
                        />
                      </td>
                      <td style={{ minWidth: 110 }}>
                        <input
                          type="number" min={2000} max={2100} className="input" value={row.application_year}
                          onChange={(e) => setTimeBankField(row.id, 'application_year', Number(e.target.value))}
                        />
                      </td>
                      <td>
                        {row.id < 0 && (
                          <button className="btn btn-danger btn-sm" onClick={() => removeTimeBankRow(row.id)}>
                            Remove
                          </button>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 16 }}>
              <button className="btn btn-secondary btn-sm" onClick={addTimeBankRow}>+ Add row</button>
              <button className="btn btn-primary" onClick={handleSaveTimeBank} disabled={savingTimeBank}>
                {savingTimeBank ? 'Saving…' : 'Save Time Bank configuration'}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

function RevShareRow({
  row, onChange,
}: {
  row: RevenueSharingConfig;
  onChange: (service_type: ServiceType, key: keyof RevenueSharingConfig, value: number) => void;
}) {
  const providerTotal = row.provider_rate_per_hour * EXAMPLE_HOURS;
  const partnerTotal = row.business_partner_flat_per_hour * EXAMPLE_HOURS;
  const customerTotal = row.customer_rate_per_hour * EXAMPLE_HOURS;
  const platformMargin = customerTotal - providerTotal - partnerTotal;
  const overCharged = row.provider_rate_per_hour > row.customer_rate_per_hour;

  return (
    <div style={{ border: '1px solid var(--color-border)', borderRadius: 10, padding: 16 }}>
      <div style={{ fontWeight: 700, fontSize: 14, marginBottom: 12 }}>{SERVICE_TYPE_LABELS[row.service_type]}</div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))', gap: 14, marginBottom: 12 }}>
        <div>
          <label className="field-label">Customer rate / hr (₹)</label>
          <input type="number" className="input" value={row.customer_rate_per_hour} onChange={(e) => onChange(row.service_type, 'customer_rate_per_hour', Number(e.target.value))} />
        </div>
        <div>
          <label className="field-label">Provider rate / hr (₹)</label>
          <input type="number" className="input" value={row.provider_rate_per_hour} onChange={(e) => onChange(row.service_type, 'provider_rate_per_hour', Number(e.target.value))} />
        </div>
        <div>
          <label className="field-label">Business partner flat rate / hr (₹)</label>
          <input type="number" className="input" value={row.business_partner_flat_per_hour} onChange={(e) => onChange(row.service_type, 'business_partner_flat_per_hour', Number(e.target.value))} />
        </div>
      </div>

      {overCharged && (
        <div style={{ fontSize: 12, color: 'var(--color-danger)', marginBottom: 8 }}>
          Provider rate exceeds customer rate — the platform would lose money on this service.
        </div>
      )}

      <div style={{ background: '#fafbfc', border: '1px solid var(--color-border)', borderRadius: 8, padding: '10px 14px', fontSize: 12.5, color: 'var(--color-text)' }}>
        <strong>Example:</strong> if used for {EXAMPLE_HOURS} hours → customer pays{' '}
        <strong>₹{customerTotal.toLocaleString('en-IN')}</strong>, provider earns{' '}
        <strong>₹{providerTotal.toLocaleString('en-IN')}</strong>, business partner earns{' '}
        <strong>₹{partnerTotal.toLocaleString('en-IN')}</strong>, platform margin{' '}
        <strong style={{ color: platformMargin < 0 ? 'var(--color-danger)' : 'var(--color-success)' }}>
          ₹{platformMargin.toLocaleString('en-IN')}
        </strong>.
      </div>
    </div>
  );
}
