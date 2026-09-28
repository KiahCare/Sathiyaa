import { useEffect, useMemo, useState } from 'react';
import type { ApprovalStatus, ServiceProvider } from '../../types';
import { SERVICE_TYPE_LABELS, DAY_LABELS } from '../../types';
import { uploadUrl } from '../../api/client';
import {
  listProviders, approveProvider, holdProvider, rejectProvider, blockProvider, unblockProvider, deleteProvider,
  resetProviderDevice,
} from '../../api/services';
import {
  PageHeader, ApprovalBadge, StatusBadge, TableSkeleton, EmptyState, ErrorState,
  ConfirmDialog, Modal, InlineBanner,
} from '../../components/ui';

const STATUS_TABS: { value: ApprovalStatus | 'all'; label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'pending', label: 'Pending' },
  { value: 'hold', label: 'On Hold' },
  { value: 'approved', label: 'Approved' },
  { value: 'rejected', label: 'Rejected' },
];

type DialogState =
  | { type: 'approve'; provider: ServiceProvider }
  | { type: 'reset-device'; provider: ServiceProvider }
  | { type: 'hold'; provider: ServiceProvider }
  | { type: 'reject'; provider: ServiceProvider }
  | { type: 'delete'; provider: ServiceProvider }
  | { type: 'block'; provider: ServiceProvider }
  | { type: 'unblock'; provider: ServiceProvider }
  | null;

export default function ServiceProviders() {
  const [providers, setProviders] = useState<ServiceProvider[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<ApprovalStatus | 'all'>('all');
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<ServiceProvider | null>(null);
  const [dialog, setDialog] = useState<DialogState>(null);
  const [toast, setToast] = useState<string | null>(null);

  async function load() {
    setError(null);
    try {
      const items = await listProviders({ status: statusFilter, search: search || undefined });
      setProviders(items);
    } catch (err: any) {
      setError(err?.message ?? 'Failed to load service providers.');
    }
  }

  useEffect(() => {
    setProviders(null);
    const t = setTimeout(load, search ? 300 : 0);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [statusFilter, search]);

  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 3200);
    return () => clearTimeout(t);
  }, [toast]);

  const counts = useMemo(() => {
    const c: Record<string, number> = { all: providers?.length ?? 0 };
    return c;
  }, [providers]);

  async function handleApprove(p: ServiceProvider) {
    await approveProvider(p.provider_id);
    setToast(`${p.name} has been approved and is now visible in customer search.`);
    setDialog(null);
    setSelected(null);
    load();
  }
  async function handleHold(p: ServiceProvider, note?: string) {
    await holdProvider(p.provider_id, note ?? '');
    setToast(`${p.name} has been put on hold.`);
    setDialog(null);
    setSelected(null);
    load();
  }
  async function handleReject(p: ServiceProvider, note?: string) {
    await rejectProvider(p.provider_id, note ?? '');
    setToast(`${p.name}'s registration has been rejected.`);
    setDialog(null);
    setSelected(null);
    load();
  }
  async function handleDelete(p: ServiceProvider) {
    try {
      await deleteProvider(p.provider_id);
      setToast(`${p.name} has been removed from the directory.`);
    } catch (e) {
      // The server refuses to delete an account with history, and says why.
      setError(e instanceof Error ? e.message : 'Could not remove that account.');
    }
    setDialog(null);
    setSelected(null);
    load();
  }
  async function handleBlock(p: ServiceProvider, note?: string) {
    await blockProvider(p.provider_id, note ?? '');
    setToast(`${p.name} has been blocked.`);
    setDialog(null);
    setSelected(null);
    load();
  }
  async function handleResetDevice(p: ServiceProvider) {
    await resetProviderDevice(p.provider_id);
    await load();
    setDialog(null);
  }

  async function handleUnblock(p: ServiceProvider) {
    await unblockProvider(p.provider_id);
    setToast(`${p.name} has been unblocked.`);
    setDialog(null);
    setSelected(null);
    load();
  }

  return (
    <div>
      <PageHeader
        title="Service Providers"
        subtitle="Review new registrations, approve for customer search, or hold/block providers."
      />

      {toast && <InlineBanner kind="success">{toast}</InlineBanner>}

      {/* The two columns were read as one thing with two contradictory values
          -- "Approval: Rejected, Account: Active, so which is it?" They answer
          different questions, and the only reliable fix is to say so on the
          page rather than expect anybody to infer it from two badges. The
          "Bookable" column below is the answer people actually wanted. */}
      <div className="card" style={{ marginBottom: 16, padding: '12px 16px', fontSize: 12.5, lineHeight: 1.6, color: 'var(--color-text-muted)' }}>
        <strong style={{ color: 'var(--color-text)' }}>Approval</strong> is about their paperwork —
        whether we have checked this person and are willing to put them in front of a family.{' '}
        <strong style={{ color: 'var(--color-text)' }}>Account</strong> is about their login —
        whether they can sign in at all. They are independent on purpose: a carer rejected for a
        missing police check still has a working account, so they can re-upload the document and
        be approved without registering again. <strong style={{ color: 'var(--color-text)' }}>Bookable</strong>{' '}
        is the one that matters day to day, and it needs both.
      </div>

      <div className="card" style={{ marginBottom: 16, padding: '14px 16px', display: 'flex', gap: 16, flexWrap: 'wrap', alignItems: 'center' }}>
        <div className="tabs" style={{ borderBottom: 'none', flexWrap: 'wrap' }}>
          {STATUS_TABS.map((t) => (
            <button
              key={t.value}
              className={`tab-btn ${statusFilter === t.value ? 'active' : ''}`}
              onClick={() => setStatusFilter(t.value)}
              style={{ marginRight: 18 }}
            >
              {t.label}{t.value === 'all' && providers ? ` (${counts.all})` : ''}
            </button>
          ))}
        </div>
        <input
          className="input"
          placeholder="Search by name, ID, or mobile…"
          style={{ maxWidth: 260, marginLeft: 'auto' }}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
      </div>

      <div className="card" style={{ overflow: 'hidden' }}>
        {providers === null && !error && <TableSkeleton rows={7} cols={7} />}
        {error && <ErrorState message={error} onRetry={load} />}
        {providers && providers.length === 0 && (
          <EmptyState icon="🩺" title="No providers found" description="Try a different filter or search term." />
        )}
        {providers && providers.length > 0 && (
          <div style={{ overflowX: 'auto' }}>
            <table className="data-table">
              <thead>
                <tr>
                  <th>Provider</th>
                  <th>ID</th>
                  <th>Expertise</th>
                  <th>Rate/hr</th>
                  <th>Approval</th>
                  <th>Account</th>
                  <th>Bookable</th>
                  <th>Registered</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {providers.map((p) => (
                  <tr key={p.provider_id}>
                    <td>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                        <img src={uploadUrl(p.photo_url)} alt="" style={{ width: 32, height: 32, borderRadius: '50%', objectFit: 'cover', background: '#eee' }} />
                        <div>
                          <div style={{ fontWeight: 600 }}>{p.name}</div>
                          <div style={{ fontSize: 11.5, color: 'var(--color-text-muted)' }}>{p.mobile_number}</div>
                        </div>
                      </div>
                    </td>
                    <td>{p.display_id}</td>
                    <td>{p.expertise.map((e) => SERVICE_TYPE_LABELS[e.service_type]).join(', ') || '—'}</td>
                    <td>₹{p.hourly_rate}</td>
                    <td>
                      <ApprovalBadge status={p.approval_status} />
                      {/* The reason is captured when a provider is put on hold
                          or rejected, and until now it was only visible after
                          opening the profile -- so a list of rejections gave no
                          hint why any of them happened. */}
                      {p.approval_notes && (
                        <div
                          title={p.approval_notes}
                          style={{ fontSize: 11, color: 'var(--color-text-muted)', marginTop: 4, maxWidth: 220, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}
                        >
                          {p.approval_notes}
                        </div>
                      )}
                    </td>
                    <td><StatusBadge status={p.status} /></td>
                    <td><BookableCell provider={p} /></td>
                    <td>{new Date(p.created_at).toLocaleDateString('en-IN')}</td>
                    <td>
                      <button className="btn btn-secondary btn-sm" onClick={() => setSelected(p)}>
                        View
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {selected && (
        <ProviderProfileModal
          provider={selected}
          onClose={() => setSelected(null)}
          onApprove={() => setDialog({ type: 'approve', provider: selected })}
          onHold={() => setDialog({ type: 'hold', provider: selected })}
          onReject={() => setDialog({ type: 'reject', provider: selected })}
          onDelete={() => setDialog({ type: 'delete', provider: selected })}
          onBlock={() => setDialog({ type: 'block', provider: selected })}
          onUnblock={() => setDialog({ type: 'unblock', provider: selected })}
          onResetDevice={() => setDialog({ type: 'reset-device', provider: selected })}
        />
      )}

      {dialog?.type === 'approve' && (
        <ConfirmDialog
          title="Approve provider"
          description={`${dialog.provider.name} will become visible in customer search results immediately.`}
          confirmLabel="Approve"
          onConfirm={() => handleApprove(dialog.provider)}
          onCancel={() => setDialog(null)}
        />
      )}
      {dialog?.type === 'hold' && (
        <ConfirmDialog
          title="Put provider on hold"
          description={`${dialog.provider.name} will be hidden from customer search until the issue is resolved and the provider is re-approved.`}
          confirmLabel="Put on hold"
          requireNote
          notePlaceholder="e.g. Police verification document is unreadable, please re-upload."
          onConfirm={(note) => handleHold(dialog.provider, note)}
          onCancel={() => setDialog(null)}
        />
      )}
      {dialog?.type === 'delete' && (
        <ConfirmDialog
          title="Remove this registration"
          description={`${dialog.provider.name} (${dialog.provider.display_id}) will be deleted outright. Use this for junk sign-ups and leftover test accounts — an account with any booking history cannot be removed, and should be blocked instead.`}
          confirmLabel="Remove permanently"
          danger
          onConfirm={() => handleDelete(dialog.provider)}
          onCancel={() => setDialog(null)}
        />
      )}
      {dialog?.type === 'reject' && (
        <ConfirmDialog
          title="Reject this registration"
          description={`${dialog.provider.name} will not be approved and will not appear in customer search. They can be approved later if the problem is resolved.`}
          confirmLabel="Reject registration"
          danger
          requireNote
          notePlaceholder="e.g. Nursing certificate could not be verified."
          onConfirm={(note) => handleReject(dialog.provider, note)}
          onCancel={() => setDialog(null)}
        />
      )}
      {dialog?.type === 'block' && (
        <ConfirmDialog
          title="Block provider"
          description={`${dialog.provider.name} will be blocked from logging in and will no longer receive booking requests. This is a serious action.`}
          confirmLabel="Block provider"
          danger
          requireNote
          notePlaceholder="e.g. Blocked after repeated no-shows reported by customers."
          onConfirm={(note) => handleBlock(dialog.provider, note)}
          onCancel={() => setDialog(null)}
        />
      )}
      {dialog?.type === 'reset-device' && (
        <ConfirmDialog
          title="Release this provider's device"
          description={`${dialog.provider.name} is signed in on one phone and cannot sign in on another. Releasing it lets them sign in on a new device — the next one to log in becomes the bound device. Do this when a provider has lost or replaced their phone.`}
          confirmLabel="Release device"
          onConfirm={() => handleResetDevice(dialog.provider)}
          onCancel={() => setDialog(null)}
        />
      )}

      {dialog?.type === 'unblock' && (
        <ConfirmDialog
          title="Unblock provider"
          description={`${dialog.provider.name} will regain login access and be eligible to receive booking requests again.`}
          confirmLabel="Unblock provider"
          onConfirm={() => handleUnblock(dialog.provider)}
          onCancel={() => setDialog(null)}
        />
      )}
    </div>
  );
}

/**
 * Whether a family can actually find and book this person, and if not, why.
 *
 * Approval and account status are separate values that combine into one fact,
 * and reading that fact off two badges is exactly what nobody could do: a row
 * showing "Rejected" next to "Active" looks like a contradiction rather than
 * two true statements about different things. This states the conclusion.
 *
 * Blocked wins over approval, because a blocked account cannot sign in to
 * accept the booking however good its paperwork is.
 */
function bookable(p: ServiceProvider): { yes: boolean; label: string; why: string } {
  if (p.status === 'blocked') {
    return { yes: false, label: 'No', why: 'Blocked — cannot sign in, so cannot take a booking.' };
  }
  switch (p.approval_status) {
    case 'approved':
      return { yes: true, label: 'Yes', why: 'Approved and able to sign in. Appears in customer search.' };
    case 'pending':
      return { yes: false, label: 'No', why: 'Waiting for review. Hidden from customer search until approved.' };
    case 'hold':
      return { yes: false, label: 'No', why: 'On hold. Hidden from search until the issue is resolved and they are approved.' };
    case 'rejected':
      return { yes: false, label: 'No', why: 'Rejected. Can still sign in and fix their documents, but is hidden from search.' };
    default:
      return { yes: false, label: 'No', why: 'Not approved.' };
  }
}

function BookableCell({ provider }: { provider: ServiceProvider }) {
  const b = bookable(provider);
  return (
    <span className={`badge ${b.yes ? 'badge-green' : 'badge-gray'}`} title={b.why}>
      {b.label}
    </span>
  );
}

function DocLink({ label, url }: { label: string; url: string | null }) {
  // A stored value that is neither an http(s) URL nor a path under /uploads/
  // is a file path from somebody's phone, written in by a registration that
  // skipped the upload. It cannot be fetched from anywhere, so say so plainly
  // rather than offering a link that opens a blank tab.
  const resolved = uploadUrl(url);
  const unusable = !!url && !resolved;

  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '9px 12px', background: '#fafbfc', border: '1px solid var(--color-border)', borderRadius: 8, marginBottom: 8 }}>
      <span style={{ fontSize: 13, fontWeight: 500 }}>{label}</span>
      {resolved ? (
        <a href={resolved} target="_blank" rel="noreferrer" className="btn btn-secondary btn-sm">
          View / Download
        </a>
      ) : unusable ? (
        <span style={{ fontSize: 12, color: 'var(--color-danger, #be123c)' }} title={url ?? ''}>
          Never uploaded — ask for it again
        </span>
      ) : (
        <span style={{ fontSize: 12, color: 'var(--color-text-muted)' }}>Not uploaded</span>
      )}
    </div>
  );
}

function ProviderProfileModal({
  provider, onClose, onApprove, onHold, onReject, onBlock, onUnblock, onResetDevice, onDelete,
}: {
  provider: ServiceProvider;
  onClose: () => void;
  onApprove: () => void;
  onHold: () => void;
  onReject: () => void;
  onDelete: () => void;
  onBlock: () => void;
  onUnblock: () => void;
  onResetDevice: () => void;
}) {
  return (
    <Modal onClose={onClose} width={680}>
      <div style={{ padding: 26 }}>
        <div style={{ display: 'flex', gap: 16, alignItems: 'flex-start', marginBottom: 20 }}>
          <img src={uploadUrl(provider.photo_url)} alt="" style={{ width: 68, height: 68, borderRadius: 14, objectFit: 'cover', background: '#eee' }} />
          <div style={{ flex: 1 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
              <h2 style={{ margin: 0, fontSize: 19, fontWeight: 700 }}>{provider.name}</h2>
              <ApprovalBadge status={provider.approval_status} />
              <StatusBadge status={provider.status} />
            </div>
            <div style={{ fontSize: 13, color: 'var(--color-text-muted)', marginTop: 4 }}>
              {provider.display_id} · {provider.gender} · {provider.provider_kind.replace('_', ' ')} · {provider.mobile_number}
              {provider.email ? ` · ${provider.email}` : ''}
            </div>
            {provider.provider_kind === 'org_employee' && (
              <div style={{ marginTop: 6, fontSize: 12.5 }}>
                <span className="badge badge-blue">
                  Carer at {provider.organization_name ?? 'an organisation'}
                </span>
                <span style={{ marginLeft: 8, color: 'var(--color-text-muted)' }}>
                  Put forward by the organisation. Approving them is what tells families they
                  have been checked.
                </span>
              </div>
            )}
            {/* The conclusion, in words, above the two badges that produce it.
                Asked for directly: an admin looking at "Rejected" and "Active"
                together could not tell what was true of the carer. */}
            <div style={{ marginTop: 8, fontSize: 12.5, color: 'var(--color-text-muted)' }}>
              {bookable(provider).yes ? '✓ ' : '· '}{bookable(provider).why}
            </div>
            {provider.approval_notes && (
              <div style={{ marginTop: 8, fontSize: 12.5, background: 'var(--color-warning-light)', color: 'var(--color-warning)', padding: '7px 10px', borderRadius: 7 }}>
                <strong>Reason given:</strong> {provider.approval_notes}
                {provider.approved_at && (
                  <div style={{ marginTop: 3, opacity: 0.8 }}>
                    Recorded {new Date(provider.approved_at).toLocaleString('en-IN')}
                  </div>
                )}
              </div>
            )}
          </div>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16, marginBottom: 20 }}>
          <div>
            <div className="field-label">Hourly rate</div>
            <div style={{ fontSize: 14 }}>₹{provider.hourly_rate} / hr</div>
          </div>
          <div>
            <div className="field-label">Rating</div>
            <div style={{ fontSize: 14 }}>{provider.rating_count > 0 ? `★ ${provider.rating_avg.toFixed(1)} (${provider.rating_count})` : 'No ratings yet'}</div>
          </div>
          <div>
            <div className="field-label">Expertise</div>
            <div style={{ fontSize: 14 }}>
              {provider.expertise.map((e) => `${SERVICE_TYPE_LABELS[e.service_type]}${e.years_experience ? ` (${e.years_experience}y)` : ''}`).join(', ') || '—'}
            </div>
          </div>
          <div>
            <div className="field-label">Distance preference</div>
            <div style={{ fontSize: 14 }}>
              Home ≤{provider.distance_from_home_pref_km ?? '—'} km · Office ≤{provider.distance_from_office_pref_km ?? '—'} km
            </div>
          </div>
          <div style={{ gridColumn: '1 / -1' }}>
            <div className="field-label">Address</div>
            <div style={{ fontSize: 14 }}>
              {provider.addresses.map((a, i) => (
                <div key={i}>{a.line1}{a.city ? `, ${a.city}` : ''}{a.state ? `, ${a.state}` : ''} {a.pincode ?? ''}</div>
              ))}
            </div>
          </div>
          <div style={{ gridColumn: '1 / -1' }}>
            {/* A family filters on this and reads it before choosing, so it is
                worth an administrator being able to see what a carer claimed. */}
            <div className="field-label">Languages</div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
              {(() => {
                const raw = provider.languages as unknown;
                const list = Array.isArray(raw)
                  ? raw
                  : typeof raw === 'string' && raw.trim().startsWith('[')
                    ? (JSON.parse(raw) as string[])
                    : [];
                return list.length === 0 ? (
                  <span style={{ fontSize: 13, color: 'var(--color-text-muted)' }}>Not set</span>
                ) : (
                  list.map((l) => <span key={l} className="badge badge-blue">{l}</span>)
                );
              })()}
            </div>
          </div>
          <div style={{ gridColumn: '1 / -1' }}>
            <div className="field-label">Work days &amp; hours</div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
              {provider.work_hours.length === 0 && <span style={{ fontSize: 13, color: 'var(--color-text-muted)' }}>Not set</span>}
              {provider.work_hours.map((wh) => (
                <span key={wh.day_of_week} className="badge badge-blue">
                  {DAY_LABELS[wh.day_of_week]} {wh.start_time}–{wh.end_time}
                </span>
              ))}
            </div>
          </div>
        </div>

        <div className="field-label" style={{ marginBottom: 8 }}>
          {provider.provider_kind === 'organization' ? 'Registration' : 'Verification documents'}
        </div>
        {provider.provider_kind === 'organization' ? (
          <>
            {/* An organisation has no Aadhaar and nobody runs a police check on
                a company. What verifies an agency is its registration; what
                verifies the people it sends is each carer's own paperwork,
                collected on the screen that adds that carer. Showing the two
                personal rows here meant an empty drawer and an approval made
                without seeing anything. */}
            <DocLink label="Registration certificate" url={provider.org_registration_url ?? null} />
            <div style={{ display: 'flex', gap: 24, flexWrap: 'wrap', margin: '10px 0 4px' }}>
              <div>
                <div className="field-label">GST number</div>
                <div style={{ fontSize: 14 }}>{provider.gst_number || 'Not registered'}</div>
              </div>
              <div>
                <div className="field-label">Contact person</div>
                <div style={{ fontSize: 14 }}>{provider.contact_person || '—'}</div>
              </div>
            </div>
            <div style={{ fontSize: 12.5, color: 'var(--color-text-muted)', marginTop: 8, lineHeight: 1.5 }}>
              Each carer this organisation adds has their own Aadhaar and police
              verification. A carer without them cannot be allocated a visit,
              whatever this organisation's status is.
            </div>
          </>
        ) : (
          <>
            <DocLink label="Aadhar card" url={provider.aadhar_doc_url} />
            <DocLink label="Police verification" url={provider.police_verification_url} />
            <DocLink label="Work / education certificate" url={provider.work_certificate_url} />
          </>
        )}

        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 10, marginTop: 22, flexWrap: 'wrap' }}>
          <button className="btn btn-secondary" onClick={onClose}>Close</button>
          {provider.status === 'blocked' ? (
            <button className="btn btn-secondary" onClick={onUnblock}>Unblock</button>
          ) : (
            <button className="btn btn-danger" onClick={onBlock}>Block</button>
          )}
          {provider.device_id && (
            <button className="btn btn-secondary" onClick={onResetDevice}>Release device</button>
          )}
          {provider.approval_status !== 'approved' && (
            <button className="btn btn-warning" onClick={onHold}>Put on Hold</button>
          )}
          {provider.approval_status !== 'rejected' && (
            <button className="btn btn-danger" onClick={onReject}>Reject</button>
          )}
          {/* Was labelled "Remove", which told nobody what it removed or how
              it differed from Block -- the question came back as "what is the
              Remove button for?". It deletes the registration outright, and is
              for junk sign-ups and leftover test accounts only. The server
              refuses once there is any history, so the real answer for a
              misbehaving carer is Block, next to it. */}
          <button
            className="btn btn-secondary"
            onClick={onDelete}
            title="Deletes this registration permanently. Only for junk sign-ups and test accounts — an account with booking history cannot be deleted, and should be blocked instead."
          >
            Delete registration
          </button>
          {provider.approval_status !== 'approved' && (
            <button className="btn btn-primary" onClick={onApprove}>Approve</button>
          )}
        </div>
      </div>
    </Modal>
  );
}
