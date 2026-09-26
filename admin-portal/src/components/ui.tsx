import { type ReactNode, useState } from 'react';
import { createPortal } from 'react-dom';

// ---------------------------------------------------------------------
// PageHeader
// ---------------------------------------------------------------------

export function PageHeader({ title, subtitle, actions }: { title: string; subtitle?: string; actions?: ReactNode }) {
  return (
    <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 16, marginBottom: 22, flexWrap: 'wrap' }}>
      <div>
        <h1 style={{ fontSize: 22, fontWeight: 700, margin: 0, letterSpacing: '-0.01em' }}>{title}</h1>
        {subtitle && <p style={{ margin: '4px 0 0', fontSize: 13.5, color: 'var(--color-text-muted)' }}>{subtitle}</p>}
      </div>
      {actions && <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>{actions}</div>}
    </div>
  );
}

// ---------------------------------------------------------------------
// Badges
// ---------------------------------------------------------------------

const APPROVAL_BADGE: Record<string, string> = {
  approved: 'badge-green',
  pending: 'badge-amber',
  hold: 'badge-amber',
  rejected: 'badge-red',
};
const STATUS_BADGE: Record<string, string> = {
  active: 'badge-green',
  blocked: 'badge-red',
  pending_payment: 'badge-gray',
};

export function ApprovalBadge({ status }: { status: string }) {
  return <span className={`badge ${APPROVAL_BADGE[status] ?? 'badge-gray'}`}>{status}</span>;
}
export function StatusBadge({ status }: { status: string }) {
  return <span className={`badge ${STATUS_BADGE[status] ?? 'badge-gray'}`}>{status.replace('_', ' ')}</span>;
}

// ---------------------------------------------------------------------
// Loading / Empty / Error states
// ---------------------------------------------------------------------

export function TableSkeleton({ rows = 6, cols = 5 }: { rows?: number; cols?: number }) {
  return (
    <div style={{ padding: 16 }}>
      {Array.from({ length: rows }).map((_, r) => (
        <div key={r} style={{ display: 'flex', gap: 14, marginBottom: 14 }}>
          {Array.from({ length: cols }).map((_, c) => (
            <div key={c} className="skeleton" style={{ height: 16, flex: c === 0 ? 2 : 1 }} />
          ))}
        </div>
      ))}
    </div>
  );
}

export function EmptyState({ icon = '📭', title, description }: { icon?: string; title: string; description?: string }) {
  return (
    <div style={{ textAlign: 'center', padding: '56px 24px', color: 'var(--color-text-muted)' }}>
      <div style={{ fontSize: 34, marginBottom: 10 }}>{icon}</div>
      <div style={{ fontWeight: 600, fontSize: 14.5, color: 'var(--color-text)', marginBottom: 4 }}>{title}</div>
      {description && <div style={{ fontSize: 13 }}>{description}</div>}
    </div>
  );
}

export function ErrorState({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div style={{ textAlign: 'center', padding: '48px 24px' }}>
      <div style={{ fontSize: 30, marginBottom: 10 }}>⚠️</div>
      <div style={{ fontWeight: 600, fontSize: 14.5, color: 'var(--color-danger)', marginBottom: 6 }}>Something went wrong</div>
      <div style={{ fontSize: 13, color: 'var(--color-text-muted)', marginBottom: 16 }}>{message}</div>
      {onRetry && (
        <button className="btn btn-secondary btn-sm" onClick={onRetry}>
          Try again
        </button>
      )}
    </div>
  );
}

export function InlineBanner({ kind = 'error', children }: { kind?: 'error' | 'success' | 'warning'; children: ReactNode }) {
  const styles = {
    error: { bg: 'var(--color-danger-light)', color: 'var(--color-danger)' },
    success: { bg: 'var(--color-success-light)', color: 'var(--color-success)' },
    warning: { bg: 'var(--color-warning-light)', color: 'var(--color-warning)' },
  }[kind];
  return (
    <div style={{ background: styles.bg, color: styles.color, padding: '10px 14px', borderRadius: 8, fontSize: 13, fontWeight: 500, marginBottom: 14 }}>
      {children}
    </div>
  );
}

// ---------------------------------------------------------------------
// StatCard
// ---------------------------------------------------------------------

export function StatCard({ label, value, sub, accent }: { label: string; value: string; sub?: string; accent?: string }) {
  return (
    <div className="card" style={{ padding: '18px 20px' }}>
      <div style={{ fontSize: 12, fontWeight: 600, color: 'var(--color-text-muted)', textTransform: 'uppercase', letterSpacing: '0.03em' }}>{label}</div>
      <div style={{ fontSize: 26, fontWeight: 700, marginTop: 6, color: accent ?? 'var(--color-text)' }}>{value}</div>
      {sub && <div style={{ fontSize: 12, color: 'var(--color-text-muted)', marginTop: 4 }}>{sub}</div>}
    </div>
  );
}

// ---------------------------------------------------------------------
// Modal / ConfirmDialog
// ---------------------------------------------------------------------

export function Modal({ onClose, children, width }: { onClose: () => void; children: ReactNode; width?: number }) {
  return createPortal(
    <div className="modal-overlay" onMouseDown={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="modal-panel" style={width ? { maxWidth: width } : undefined}>{children}</div>
    </div>,
    document.body
  );
}

interface ConfirmDialogProps {
  title: string;
  description: string;
  confirmLabel?: string;
  danger?: boolean;
  requireNote?: boolean;
  notePlaceholder?: string;
  onConfirm: (note?: string) => void | Promise<void>;
  onCancel: () => void;
}

export function ConfirmDialog({
  title, description, confirmLabel = 'Confirm', danger, requireNote, notePlaceholder, onConfirm, onCancel,
}: ConfirmDialogProps) {
  const [note, setNote] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleConfirm() {
    if (requireNote && !note.trim()) {
      setError('Please add a note explaining why.');
      return;
    }
    setSubmitting(true);
    try {
      await onConfirm(note.trim() || undefined);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Modal onClose={onCancel} width={440}>
      <div style={{ padding: 24 }}>
        <h3 style={{ margin: '0 0 8px', fontSize: 16.5, fontWeight: 700 }}>{title}</h3>
        <p style={{ margin: '0 0 16px', fontSize: 13.5, color: 'var(--color-text-muted)', lineHeight: 1.5 }}>{description}</p>
        {requireNote && (
          <div style={{ marginBottom: 16 }}>
            <label className="field-label">Note</label>
            <textarea
              className={`input ${error ? 'err' : ''}`}
              rows={3}
              placeholder={notePlaceholder}
              value={note}
              onChange={(e) => { setNote(e.target.value); setError(null); }}
            />
            {error && <div className="err-text">{error}</div>}
          </div>
        )}
        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 10 }}>
          <button className="btn btn-secondary" onClick={onCancel} disabled={submitting}>
            Cancel
          </button>
          <button
            className={`btn ${danger ? 'btn-danger-solid' : 'btn-primary'}`}
            onClick={handleConfirm}
            disabled={submitting}
          >
            {submitting ? 'Please wait…' : confirmLabel}
          </button>
        </div>
      </div>
    </Modal>
  );
}
