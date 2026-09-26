import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { useState } from 'react';

interface NavItem {
  to: string;
  label: string;
  icon: string;
}

const ADMIN_NAV: NavItem[] = [
  { to: '/admin/providers', label: 'Service Providers', icon: '🩺' },
  { to: '/admin/customers', label: 'Customers', icon: '👥' },
  { to: '/admin/business-agents', label: 'Business Partners', icon: '🤝' },
  { to: '/admin/configuration', label: 'Configuration', icon: '⚙️' },
  { to: '/admin/reports', label: 'Reports', icon: '📊' },
  { to: '/admin/broadcast', label: 'Broadcast', icon: '📢' },
  { to: '/admin/tracking', label: 'Live Tracking', icon: '📍' },
  { to: '/admin/devices', label: 'Devices', icon: '📱' },
  { to: '/admin/audit-log', label: 'Audit Log', icon: '🧾' },
];

const PARTNER_NAV: NavItem[] = [
  { to: '/partner/referrals', label: 'My Referrals', icon: '🧾' },
  { to: '/partner/revenue', label: 'My Revenue', icon: '💰' },
];

export default function Layout() {
  const { user, logout } = useAuth();
  const navigate = useNavigate();
  const [mobileOpen, setMobileOpen] = useState(false);
  const nav = user?.role === 'admin' ? ADMIN_NAV : PARTNER_NAV;

  function handleLogout() {
    logout();
    navigate('/login');
  }

  return (
    <div style={{ display: 'flex', minHeight: '100vh' }}>
      {mobileOpen && (
        <div
          onClick={() => setMobileOpen(false)}
          style={{ position: 'fixed', inset: 0, background: 'rgba(16,24,40,0.45)', zIndex: 40 }}
          className="lg:hidden"
        />
      )}
      <aside
        style={{
          width: 'var(--sidebar-w)',
          background: '#0f2b26',
          color: '#e8f1ee',
          flexShrink: 0,
          position: 'fixed',
          top: 0,
          bottom: 0,
          left: 0,
          zIndex: 50,
          flexDirection: 'column',
        }}
        className={mobileOpen ? 'flex' : 'hidden lg:flex'}
      >
        <div style={{ padding: '22px 20px', display: 'flex', alignItems: 'center', gap: 10 }}>
          <img
            src="/logo/sathiyaa-mark.png"
            alt="Sathiyaa"
            style={{ width: 34, height: 34, objectFit: 'contain', flexShrink: 0 }}
          />
          <div>
            <div style={{ fontWeight: 700, fontSize: 15.5, lineHeight: 1.2 }}>Sathiyaa</div>
            <div style={{ fontSize: 11, color: '#9fc8bd' }}>
              {user?.role === 'admin' ? 'Admin Console' : 'Partner Portal'}
            </div>
          </div>
        </div>
        <nav style={{ flex: 1, padding: '8px 12px', overflowY: 'auto' }}>
          {nav.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              onClick={() => setMobileOpen(false)}
              style={({ isActive }) => ({
                display: 'flex',
                alignItems: 'center',
                gap: 11,
                padding: '10px 12px',
                borderRadius: 8,
                fontSize: 13.5,
                fontWeight: 600,
                marginBottom: 2,
                color: isActive ? '#fff' : '#bcd8d0',
                background: isActive ? '#14554a' : 'transparent',
              })}
            >
              <span style={{ fontSize: 15 }}>{item.icon}</span>
              {item.label}
            </NavLink>
          ))}
        </nav>
        <div style={{ padding: '14px 20px', fontSize: 11, color: '#6f9a90', borderTop: '1px solid #1c453d' }}>
          Sathiyaa Admin Portal v1.0
        </div>
      </aside>

      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0 }} className="ml-0 lg:ml-[var(--sidebar-w)]">
        <header
          style={{
            height: 'var(--header-h)',
            background: '#fff',
            borderBottom: '1px solid var(--color-border)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            padding: '0 24px',
            position: 'sticky',
            top: 0,
            zIndex: 30,
          }}
        >
          {/* `display` belongs in the class, not here. An inline style beats
              every stylesheet rule, so `display: flex` inline silently won
              against `lg:hidden` and this whole group stayed on screen at
              desktop widths -- where the sidebar is always shown and the
              button it holds therefore does nothing when clicked. */}
          <div className="flex lg:hidden" style={{ alignItems: 'center', gap: 10 }}>
            <button
              className="btn btn-secondary btn-sm"
              onClick={() => setMobileOpen((v) => !v)}
              aria-label="Toggle navigation"
            >
              ☰
            </button>
            <img src="/logo/sathiyaa-mark.png" alt="Sathiyaa" style={{ width: 26, height: 26, objectFit: 'contain' }} />
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginLeft: 'auto' }}>
            <div style={{ textAlign: 'right' }}>
              <div style={{ fontSize: 13.5, fontWeight: 600 }}>{user?.name}</div>
              <div style={{ fontSize: 11.5, color: 'var(--color-text-muted)' }}>
                {user?.role === 'admin' ? (user?.adminRole ?? 'admin')?.replace('_', ' ') : 'Business Partner'} · {user?.displayId}
              </div>
            </div>
            <div
              style={{
                width: 36, height: 36, borderRadius: '50%', background: 'var(--color-primary-light)',
                color: 'var(--color-primary-dark)', display: 'flex', alignItems: 'center', justifyContent: 'center',
                fontWeight: 700, fontSize: 14,
              }}
            >
              {user?.name?.charAt(0) ?? '?'}
            </div>
            <button className="btn btn-secondary btn-sm" onClick={handleLogout}>
              Log out
            </button>
          </div>
        </header>
        <main style={{ flex: 1, padding: 24, maxWidth: 1440, width: '100%', margin: '0 auto' }}>
          <Outlet />
        </main>
      </div>
    </div>
  );
}
