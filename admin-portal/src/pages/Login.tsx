import { useState, type FormEvent } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { loginAdmin, loginBusinessAgent } from '../api/services';
import { USE_MOCK, API_BASE_URL } from '../api/client';

type Tab = 'admin' | 'business_agent';

export default function Login() {
  const [tab, setTab] = useState<Tab>('admin');
  // Only pre-fill in demo mode, where any 4+ character password is accepted.
  // Against a real server these placeholders are simply wrong credentials, and
  // pre-filling them meant clicking Sign in produced an inexplicable "no such
  // account" rather than an empty form asking to be filled.
  const [email, setEmail] = useState(USE_MOCK ? 'admin@sathiyaa.example' : '');
  const [password, setPassword] = useState(USE_MOCK ? 'admin1234' : '');
  const [userId, setUserId] = useState(USE_MOCK ? 'BP-000001' : '');
  const [agentPassword, setAgentPassword] = useState(USE_MOCK ? 'partner1234' : '');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const { login } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      if (tab === 'admin') {
        const res = await loginAdmin(email, password);
        login(res.token, res.user);
        navigate((location.state as any)?.from ?? '/admin/providers', { replace: true });
      } else {
        const res = await loginBusinessAgent(userId, agentPassword);
        login(res.token, res.user);
        navigate((location.state as any)?.from ?? '/partner/referrals', { replace: true });
      }
    } catch (err: any) {
      setError(err?.message ?? 'Login failed. Please check your credentials.');
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div style={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'linear-gradient(160deg, #0f2b26 0%, #0a5346 45%, #14a085 100%)', padding: 20 }}>
      <div style={{ width: '100%', maxWidth: 420 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, justifyContent: 'center', marginBottom: 28 }}>
          <img src="/logo/sathiyaa-mark.png" alt="Sathiyaa" style={{ width: 46, height: 46, objectFit: 'contain' }} />
          <div>
            <div style={{ fontWeight: 800, fontSize: 22, color: '#fff' }}>Sathiyaa</div>
            <div style={{ fontSize: 12.5, color: '#bcd8d0' }}>Admin &amp; Business Partner Portal</div>
          </div>
        </div>

        <div className="card" style={{ padding: 28, boxShadow: '0 24px 60px rgba(0,0,0,0.25)' }}>
          <div className="tabs" style={{ marginBottom: 22 }}>
            <button
              type="button"
              className={`tab-btn ${tab === 'admin' ? 'active' : ''}`}
              onClick={() => { setTab('admin'); setError(null); }}
            >
              Admin
            </button>
            <button
              type="button"
              className={`tab-btn ${tab === 'business_agent' ? 'active' : ''}`}
              onClick={() => { setTab('business_agent'); setError(null); }}
            >
              Business Partner
            </button>
          </div>

          {USE_MOCK ? (
            <div style={{ background: 'var(--color-primary-light)', color: 'var(--color-primary-dark)', fontSize: 12, padding: '9px 12px', borderRadius: 8, marginBottom: 18, lineHeight: 1.5 }}>
              Demo mode — any non-empty password (4+ chars) signs in. {tab === 'business_agent' && 'Try BP-000001 / BP-000002.'}
            </div>
          ) : (
            <div style={{ background: '#eef4ff', color: '#1e3a5f', fontSize: 12, padding: '9px 12px', borderRadius: 8, marginBottom: 18, lineHeight: 1.5 }}>
              Connected to <strong>{API_BASE_URL}</strong>. Sign in with a real account
              {tab === 'admin'
                ? ' — the seeded one is admin@sathiyaa.com.'
                : ' — a Business Partner ID, referral code or mobile number.'}
            </div>
          )}

          <form onSubmit={handleSubmit}>
            {tab === 'admin' ? (
              <>
                <div style={{ marginBottom: 16 }}>
                  <label className="field-label">Email</label>
                  <input className="input" type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="admin@sathiyaa.com" required />
                </div>
                <div style={{ marginBottom: 20 }}>
                  <label className="field-label">Password</label>
                  <input className="input" type="password" value={password} onChange={(e) => setPassword(e.target.value)} required />
                </div>
              </>
            ) : (
              <>
                <div style={{ marginBottom: 16 }}>
                  <label className="field-label">User ID or Email</label>
                  <input className="input" value={userId} onChange={(e) => setUserId(e.target.value)} placeholder="BP-000001, a referral code, or a mobile number" required />
                </div>
                <div style={{ marginBottom: 20 }}>
                  <label className="field-label">Password</label>
                  <input className="input" type="password" value={agentPassword} onChange={(e) => setAgentPassword(e.target.value)} required />
                  <div className="field-hint">Or sign in with mobile + OTP from the app (not shown in this demo).</div>
                </div>
              </>
            )}

            {error && <div className="err-text" style={{ marginBottom: 14, fontSize: 13 }}>{error}</div>}

            <button className="btn btn-primary" type="submit" style={{ width: '100%', padding: '11px' }} disabled={submitting}>
              {submitting ? 'Signing in…' : 'Sign in'}
            </button>
          </form>
        </div>
        <div style={{ textAlign: 'center', marginTop: 18, fontSize: 11.5, color: '#bcd8d0' }}>
          © {new Date().getFullYear()} Sathiyaa. Home-healthcare booking platform.
        </div>
      </div>
    </div>
  );
}
