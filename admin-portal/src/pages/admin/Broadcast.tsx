import { useEffect, useState, type FormEvent } from 'react';
import type { BroadcastAudience, BroadcastMessage } from '../../types';
import {
  listBroadcasts, sendBroadcast, previewBroadcast, listBroadcastCities,
  listCustomers, listProviders,
  type BroadcastReach, type BroadcastCity, type NewBroadcastPayload,
} from '../../api/services';
import { PageHeader, TableSkeleton, EmptyState, ErrorState, InlineBanner } from '../../components/ui';

const AUDIENCE_LABEL: Record<BroadcastAudience, string> = {
  customers: 'Customers',
  providers: 'Service Providers',
  both: 'Everyone',
};

export default function Broadcast() {
  const [history, setHistory] = useState<BroadcastMessage[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [title, setTitle] = useState('');
  const [message, setMessage] = useState('');
  const [imageUrl, setImageUrl] = useState('');
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [audience, setAudience] = useState<BroadcastAudience>('both');
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [sending, setSending] = useState(false);
  const [toast, setToast] = useState<string | null>(null);

  // How the recipients are chosen. "everyone" is the old behaviour and stays
  // the default, so the page does nothing surprising to somebody who just
  // wants to announce something to all.
  const [mode, setMode] = useState<'everyone' | 'area' | 'people'>('everyone');
  const [cities, setCities] = useState<string[]>([]);
  const [pincodeText, setPincodeText] = useState('');
  const [cityOptions, setCityOptions] = useState<BroadcastCity[]>([]);
  const [people, setPeople] = useState<Array<{ type: 'customer' | 'provider'; id: number; name: string }>>([]);
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [peopleSearch, setPeopleSearch] = useState('');

  // The live "this will reach N people" figure.
  const [reach, setReach] = useState<BroadcastReach | null>(null);
  const [reaching, setReaching] = useState(false);

  const pincodes = pincodeText.split(/[\s,]+/).map((x) => x.trim()).filter(Boolean);

  /** Exactly what will be sent, and what the preview is asked about. */
  function targeting(): Pick<NewBroadcastPayload, 'audience' | 'cities' | 'pincodes' | 'customerIds' | 'providerIds'> {
    if (mode === 'area') {
      return { audience, cities, pincodes };
    }
    if (mode === 'people') {
      const ids = [...picked].map((k) => k.split(':'));
      return {
        audience,
        customerIds: ids.filter(([t]) => t === 'customer').map(([, id]) => Number(id)),
        providerIds: ids.filter(([t]) => t === 'provider').map(([, id]) => Number(id)),
      };
    }
    return { audience };
  }

  async function load() {
    setError(null);
    try {
      setHistory(await listBroadcasts());
    } catch (err: any) {
      setError(err?.message ?? 'Failed to load broadcast history.');
    }
  }

  useEffect(() => { load(); }, []);

  // The cities picker, and the people list, loaded once.
  useEffect(() => {
    listBroadcastCities().then(setCityOptions).catch(() => setCityOptions([]));
    Promise.all([listCustomers(), listProviders({ status: 'all' })])
      .then(([cs, ps]) => setPeople([
        ...cs.map((c) => ({ type: 'customer' as const, id: c.customer_id, name: c.name })),
        ...ps.map((v) => ({ type: 'provider' as const, id: v.provider_id, name: v.name })),
      ]))
      .catch(() => setPeople([]));
  }, []);

  // Ask the server who this would reach, whenever the targeting changes.
  //
  // Debounced, because typing a pincode changes it on every keystroke, and
  // asked of the server rather than counted here so the number on screen
  // cannot disagree with what actually goes out.
  useEffect(() => {
    let live = true;
    setReaching(true);
    const t = setTimeout(() => {
      previewBroadcast({ title, message, ...targeting() } as NewBroadcastPayload)
        .then((r) => { if (live) { setReach(r); setReaching(false); } })
        .catch(() => { if (live) { setReach(null); setReaching(false); } });
    }, 300);
    return () => { live = false; clearTimeout(t); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [audience, mode, cities.join('|'), pincodeText, picked.size]);
  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 3500);
    return () => clearTimeout(t);
  }, [toast]);

  function handleImageFile(file: File | null) {
    if (!file) { setImagePreview(null); return; }
    const reader = new FileReader();
    reader.onload = () => setImagePreview(reader.result as string);
    reader.readAsDataURL(file);
  }

  function validate(): boolean {
    const e: Record<string, string> = {};
    if (!title.trim()) e.title = 'Title is required.';
    else if (title.length > 200) e.title = 'Title must be 200 characters or fewer.';
    if (!message.trim()) e.message = 'Message is required.';
    else if (message.length > 2000) e.message = 'Message must be 2000 characters or fewer.';
    setErrors(e);
    return Object.keys(e).length === 0;
  }

  async function handleSend(ev: FormEvent) {
    ev.preventDefault();
    if (!validate()) return;
    setSending(true);
    try {
      const res = await sendBroadcast({
        title,
        message,
        image_url: imagePreview ?? (imageUrl || null),
        ...targeting(),
      } as NewBroadcastPayload);
      const n = (res as any)?.recipients ?? reach?.total ?? 0;
      setToast(`Sent to ${n} ${n === 1 ? 'person' : 'people'}.`);
      setTitle('');
      setMessage('');
      setImageUrl('');
      setImagePreview(null);
      setAudience('both');
      setMode('everyone');
      setCities([]);
      setPincodeText('');
      setPicked(new Set());
      load();
    } catch (err: any) {
      setErrors({ submit: err?.message ?? 'Failed to send broadcast.' });
    } finally {
      setSending(false);
    }
  }

  return (
    <div>
      <PageHeader title="Broadcast Messaging" subtitle="Send a mass message with an optional picture to customers and/or providers." />
      {toast && <InlineBanner kind="success">{toast}</InlineBanner>}

      <div style={{ display: 'grid', gridTemplateColumns: 'minmax(320px, 420px) 1fr', gap: 20, alignItems: 'flex-start' }} className="broadcast-grid">
        <div className="card" style={{ padding: 22 }}>
          <h2 style={{ margin: '0 0 16px', fontSize: 16, fontWeight: 700 }}>Compose Message</h2>
          <form onSubmit={handleSend}>
            {errors.submit && <div className="err-text" style={{ marginBottom: 12 }}>{errors.submit}</div>}
            <div style={{ marginBottom: 14 }}>
              <label className="field-label">Title</label>
              <input className={`input ${errors.title ? 'err' : ''}`} value={title} onChange={(e) => setTitle(e.target.value)} placeholder="e.g. Independence Day Offer" />
              {errors.title && <div className="err-text">{errors.title}</div>}
            </div>
            <div style={{ marginBottom: 14 }}>
              <label className="field-label">Message</label>
              <textarea className={`input ${errors.message ? 'err' : ''}`} rows={5} value={message} onChange={(e) => setMessage(e.target.value)} placeholder="Write your message…" />
              <div className="field-hint">{message.length}/2000 characters</div>
              {errors.message && <div className="err-text">{errors.message}</div>}
            </div>
            <div style={{ marginBottom: 14 }}>
              <label className="field-label">Image <span style={{ fontWeight: 400, color: 'var(--color-text-muted)' }}>(optional)</span></label>
              <input type="file" accept="image/*" className="input" onChange={(e) => handleImageFile(e.target.files?.[0] ?? null)} />
              {imagePreview && (
                <img src={imagePreview} alt="Preview" style={{ marginTop: 10, maxHeight: 140, borderRadius: 8, border: '1px solid var(--color-border)' }} />
              )}
            </div>
            <div style={{ marginBottom: 14 }}>
              <label className="field-label">Audience</label>
              <div style={{ display: 'flex', gap: 8 }}>
                {(['customers', 'providers', 'both'] as BroadcastAudience[]).map((a) => (
                  <button
                    type="button"
                    key={a}
                    onClick={() => setAudience(a)}
                    className={`btn btn-sm ${audience === a ? 'btn-primary' : 'btn-secondary'}`}
                    style={{ flex: 1 }}
                  >
                    {AUDIENCE_LABEL[a]}
                  </button>
                ))}
              </div>
            </div>

            <div style={{ marginBottom: 14 }}>
              <label className="field-label">Send to</label>
              <div style={{ display: 'flex', gap: 8 }}>
                {([
                  ['everyone', 'Everyone'],
                  ['area', 'By area'],
                  ['people', 'Pick people'],
                ] as Array<['everyone' | 'area' | 'people', string]>).map(([m, label]) => (
                  <button
                    type="button"
                    key={m}
                    onClick={() => setMode(m)}
                    className={`btn btn-sm ${mode === m ? 'btn-primary' : 'btn-secondary'}`}
                    style={{ flex: 1 }}
                  >
                    {label}
                  </button>
                ))}
              </div>
            </div>

            {mode === 'area' && (
              <div style={{ marginBottom: 14 }}>
                <label className="field-label">Cities</label>
                {cityOptions.length === 0 ? (
                  <div className="field-hint">
                    No addresses on file yet, so there is nothing to filter by.
                  </div>
                ) : (
                  <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginBottom: 10 }}>
                    {cityOptions.map((c) => {
                      const on = cities.includes(c.city);
                      const n = audience === 'customers' ? c.customers
                        : audience === 'providers' ? c.providers
                          : c.customers + c.providers;
                      return (
                        <button
                          type="button"
                          key={c.city}
                          className={`btn btn-sm ${on ? 'btn-primary' : 'btn-secondary'}`}
                          onClick={() => setCities(on ? cities.filter((x) => x !== c.city) : [...cities, c.city])}
                        >
                          {c.city} <span style={{ opacity: 0.7 }}>({n})</span>
                        </button>
                      );
                    })}
                  </div>
                )}
                <label className="field-label">Pincodes <span style={{ fontWeight: 400, color: 'var(--color-text-muted)' }}>(optional)</span></label>
                <input
                  className="input"
                  value={pincodeText}
                  onChange={(e) => setPincodeText(e.target.value)}
                  placeholder="560001, 411001"
                />
                <div className="field-hint">
                  Anyone with no address on file is not in any city, so they are not reached by an area filter.
                </div>
              </div>
            )}

            {mode === 'people' && (
              <div style={{ marginBottom: 14 }}>
                <label className="field-label">Pick people</label>
                <input
                  className="input"
                  value={peopleSearch}
                  onChange={(e) => setPeopleSearch(e.target.value)}
                  placeholder="Search by name…"
                  style={{ marginBottom: 8 }}
                />
                <div style={{ maxHeight: 220, overflowY: 'auto', border: '1px solid var(--color-border)', borderRadius: 8 }}>
                  {people
                    .filter((x) => audience === 'both'
                      || (audience === 'customers' && x.type === 'customer')
                      || (audience === 'providers' && x.type === 'provider'))
                    .filter((x) => !peopleSearch || x.name.toLowerCase().includes(peopleSearch.toLowerCase()))
                    .slice(0, 200)
                    .map((x) => {
                      const key = `${x.type}:${x.id}`;
                      const on = picked.has(key);
                      return (
                        <label
                          key={key}
                          style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '7px 10px', cursor: 'pointer' }}
                        >
                          <input
                            type="checkbox"
                            checked={on}
                            onChange={() => {
                              const next = new Set(picked);
                              if (on) next.delete(key); else next.add(key);
                              setPicked(next);
                            }}
                          />
                          <span style={{ fontSize: 13.5 }}>{x.name}</span>
                          <span style={{ marginLeft: 'auto', fontSize: 11, color: 'var(--color-text-muted)' }}>
                            {x.type === 'customer' ? 'Customer' : 'Carer'}
                          </span>
                        </label>
                      );
                    })}
                </div>
                <div className="field-hint">{picked.size} selected</div>
              </div>
            )}

            {/* What is about to happen, in people rather than settings. */}
            <div
              style={{
                marginBottom: 20,
                padding: '10px 12px',
                borderRadius: 8,
                background: reach && reach.total === 0 ? 'var(--color-danger-tint, #fdecec)' : '#f4f7fb',
                border: '1px solid var(--color-border)',
              }}
            >
              {reaching ? (
                <span style={{ fontSize: 13, color: 'var(--color-text-muted)' }}>Counting…</span>
              ) : reach == null ? (
                <span style={{ fontSize: 13, color: 'var(--color-text-muted)' }}>
                  Choose who this is for.
                </span>
              ) : reach.total === 0 ? (
                <span style={{ fontSize: 13, fontWeight: 600 }}>
                  This reaches nobody. Sending is blocked.
                </span>
              ) : (
                <span style={{ fontSize: 13 }}>
                  Reaches <strong>{reach.total}</strong> {reach.total === 1 ? 'person' : 'people'}
                  {reach.customers > 0 && reach.providers > 0 && (
                    <span style={{ color: 'var(--color-text-muted)' }}>
                      {' '}— {reach.customers} customers, {reach.providers} carers
                    </span>
                  )}
                </span>
              )}
            </div>
            <button className="btn btn-primary" type="submit" style={{ width: '100%' }} disabled={sending}>
              {sending ? 'Sending…' : 'Send Broadcast'}
            </button>
          </form>
        </div>

        <div className="card" style={{ padding: 22 }}>
          <h2 style={{ margin: '0 0 16px', fontSize: 16, fontWeight: 700 }}>Send History</h2>
          {history === null && !error && <TableSkeleton rows={4} cols={3} />}
          {error && <ErrorState message={error} onRetry={load} />}
          {history && history.length === 0 && <EmptyState icon="📢" title="No broadcasts sent yet" />}
          {history && history.length > 0 && (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12, maxHeight: 640, overflowY: 'auto' }}>
              {history.map((b) => (
                <div key={b.id} style={{ display: 'flex', gap: 14, border: '1px solid var(--color-border)', borderRadius: 10, padding: 14 }}>
                  {b.image_url && <img src={b.image_url} alt="" style={{ width: 64, height: 64, borderRadius: 8, objectFit: 'cover', flexShrink: 0 }} />}
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', gap: 10, alignItems: 'flex-start' }}>
                      <div style={{ fontWeight: 600, fontSize: 13.5 }}>{b.title}</div>
                      <span className="badge badge-blue" style={{ flexShrink: 0 }}>{AUDIENCE_LABEL[b.target_audience]}</span>
                    </div>
                    <p style={{ margin: '4px 0 8px', fontSize: 12.5, color: 'var(--color-text-muted)', lineHeight: 1.5 }}>{b.message_text}</p>
                    <div style={{ fontSize: 11.5, color: 'var(--color-text-muted)' }}>
                      {/* Every field defended. A history row is not worth taking
                          the console down for, and this line already did once:
                          the server was not storing recipient_count, so reading
                          it threw and React unmounted the whole tree. */}
                      Sent by {b.sent_by_name || 'Admin'}
                      {' · '}
                      {b.sent_at ? new Date(b.sent_at).toLocaleString('en-IN') : 'date unknown'}
                      {' · '}
                      {Number(b.recipient_count ?? 0).toLocaleString('en-IN')} recipients
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
      <style>{`@media (max-width: 900px) { .broadcast-grid { grid-template-columns: 1fr !important; } }`}</style>
    </div>
  );
}
