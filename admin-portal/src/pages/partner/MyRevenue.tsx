import { useEffect, useState } from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';
import { useAuth } from '../../context/AuthContext';
import { SERVICE_TYPE_LABELS } from '../../types';
import { getMyRevenue, type AgentRevenueSummary } from '../../api/services';
import { PageHeader, StatCard, ErrorState, EmptyState } from '../../components/ui';

export default function MyRevenue() {
  const { user } = useAuth();
  const [revenue, setRevenue] = useState<AgentRevenueSummary | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!user) return;
    getMyRevenue(user.id).then(setRevenue).catch((err) => setError(err?.message ?? 'Failed to load revenue.'));
  }, [user?.id]);

  if (error) return <ErrorState message={error} />;

  return (
    <div>
      <PageHeader title="My Revenue" subtitle="Earnings from customers you've referred, computed as hours used × the flat rate per service." />

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: 14, marginBottom: 20 }}>
        <StatCard label="Total earned" value={revenue ? `₹${revenue.total_earned.toLocaleString('en-IN')}` : '—'} accent="var(--color-primary)" />
        <StatCard label="Total hours used" value={revenue ? String(revenue.total_hours_used) : '—'} />
        <StatCard label="Referrals" value={revenue ? String(revenue.total_referrals) : '—'} />
      </div>

      <div className="card" style={{ padding: 20, marginBottom: 20 }}>
        <h3 style={{ margin: '0 0 14px', fontSize: 15, fontWeight: 700 }}>Earnings Over Time</h3>
        {!revenue ? (
          <div className="skeleton" style={{ height: 240 }} />
        ) : revenue.by_month.length === 0 ? (
          <EmptyState title="No earnings yet" description="Earnings will appear here once your referrals start using billable hours." />
        ) : (
          <ResponsiveContainer width="100%" height={260}>
            <LineChart data={revenue.by_month} margin={{ left: 0, right: 16 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#eef1f5" vertical={false} />
              <XAxis dataKey="month" tick={{ fontSize: 11.5 }} />
              <YAxis tick={{ fontSize: 11 }} width={56} tickFormatter={(v) => `₹${v}`} />
              <Tooltip formatter={(v: any) => [`₹${Number(v).toLocaleString('en-IN')}`, 'Revenue']} contentStyle={{ fontSize: 12.5, borderRadius: 8 }} />
              <Line type="monotone" dataKey="revenue" stroke="var(--color-primary)" strokeWidth={2.5} dot={{ r: 3 }} />
            </LineChart>
          </ResponsiveContainer>
        )}
      </div>

      <div className="card" style={{ padding: 20 }}>
        <h3 style={{ margin: '0 0 14px', fontSize: 15, fontWeight: 700 }}>Revenue by Referral</h3>
        {!revenue ? (
          <div className="skeleton" style={{ height: 200 }} />
        ) : revenue.by_referral.length === 0 ? (
          <EmptyState title="No referrals with billed hours yet" />
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <table className="data-table">
              <thead>
                <tr><th>Customer</th><th>Service</th><th>Hours used</th><th>Rate/hr</th><th>Revenue</th></tr>
              </thead>
              <tbody>
                {revenue.by_referral.map((r) => (
                  <tr key={r.referral_id}>
                    <td>{r.customer_name}</td>
                    <td>{SERVICE_TYPE_LABELS[r.service_type]}</td>
                    <td>{r.hours_used}</td>
                    <td>₹{r.flat_rate_per_hour}</td>
                    <td style={{ fontWeight: 600 }}>₹{r.revenue.toLocaleString('en-IN')}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
