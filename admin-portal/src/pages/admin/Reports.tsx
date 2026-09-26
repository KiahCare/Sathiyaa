import { useEffect, useState } from 'react';
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
  PieChart, Pie, Cell, Legend, LineChart, Line,
} from 'recharts';
import type { ReportsDashboard, GrowthReport, GrowthPeriod, SignupPlacesReport } from '../../types';
import { SERVICE_TYPE_LABELS } from '../../types';
import { getReportsDashboard, getGrowthReport, getSignupPlaces } from '../../api/services';
import { PageHeader, StatCard, ErrorState, EmptyState } from '../../components/ui';

const PALETTE = ['#0e6e5f', '#2563eb', '#d97706', '#7c3aed', '#dc2626', '#0891b2'];

const PERIODS: { value: GrowthPeriod; label: string }[] = [
  { value: 'day', label: 'Daily' },
  { value: 'week', label: 'Weekly' },
  { value: 'month', label: 'Monthly' },
  { value: 'quarter', label: 'Quarterly' },
  { value: 'year', label: 'Yearly' },
];

function inr(v: number) {
  // Whole rupees. A summed DECIMAL column comes back with whatever paise the
  // rows happened to carry, so the headline read "₹4,707.2" — one decimal
  // place, which reads as a number that has not finished loading. These are
  // aggregates; nobody is reconciling a ledger from this page.
  return `₹${v.toLocaleString('en-IN', { maximumFractionDigits: 0 })}`;
}

/// Recharts draws axes around nothing when handed an empty array, which is
/// how this page looked on a database with no bookings yet: four panels of
/// blank grid and no explanation.
function NoData({ height, title, description }: { height: number; title: string; description: string }) {
  return (
    <div style={{ height, display: 'grid', placeItems: 'center' }}>
      <EmptyState icon="📊" title={title} description={description} />
    </div>
  );
}

export default function Reports() {
  const [dash, setDash] = useState<ReportsDashboard | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [period, setPeriod] = useState<GrowthPeriod>('month');
  const [growth, setGrowth] = useState<GrowthReport | null>(null);
  const [growthError, setGrowthError] = useState<string | null>(null);
  const [places, setPlaces] = useState<SignupPlacesReport | null>(null);
  const [placesError, setPlacesError] = useState<string | null>(null);

  useEffect(() => {
    getReportsDashboard().then(setDash).catch((err) => setError(err?.message ?? 'Failed to load reports.'));
  }, []);

  useEffect(() => {
    getSignupPlaces()
      .then(setPlaces)
      .catch((err) => setPlacesError(err?.message ?? 'Could not load sign-up locations.'));
  }, []);

  useEffect(() => {
    setGrowth(null);
    setGrowthError(null);
    getGrowthReport(period)
      .then(setGrowth)
      .catch((err) => setGrowthError(err?.message ?? 'Could not load the growth report.'));
  }, [period]);

  if (error) return <ErrorState message={error} />;

  return (
    <div>
      <PageHeader title="Reports" subtitle="Revenue and growth across the platform." />

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: 14, marginBottom: 20 }}>
        <StatCard label="Total revenue" value={dash ? inr(dash.total_revenue) : '—'} sub="Trailing period" accent="var(--color-primary)" />
        <StatCard label="Total bookings" value={dash ? dash.total_bookings.toLocaleString('en-IN') : '—'} />
        <StatCard label="Active service cities" value={dash ? String(dash.revenue_by_city.length) : '—'} />
        <StatCard
          label="Top service"
          value={
            dash && dash.revenue_by_service_type.length > 0
              ? SERVICE_TYPE_LABELS[[...dash.revenue_by_service_type].sort((a, b) => b.revenue - a.revenue)[0].service_type]
              : '—'
          }
        />
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(420px, 1fr))', gap: 18, marginBottom: 20 }}>
        <div className="card" style={{ padding: 20 }}>
          <h3 style={{ margin: '0 0 14px', fontSize: 15, fontWeight: 700 }}>Revenue by City</h3>
          {!dash ? <div className="skeleton" style={{ height: 260 }} /> : dash.revenue_by_city.length === 0 ? (
            <NoData
              height={260}
              title="No revenue yet"
              description="Revenue appears here once bookings have been paid for. Nothing has been settled in any city so far."
            />
          ) : (
            <ResponsiveContainer width="100%" height={260}>
              <BarChart data={dash.revenue_by_city} margin={{ left: 0, right: 8 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#eef1f5" vertical={false} />
                <XAxis dataKey="city" tick={{ fontSize: 11.5 }} />
                <YAxis tick={{ fontSize: 11 }} tickFormatter={(v) => `₹${(v / 1000).toFixed(0)}k`} width={48} />
                <Tooltip formatter={(v: any) => inr(Number(v))} contentStyle={{ fontSize: 12.5, borderRadius: 8 }} />
                <Bar dataKey="revenue" radius={[6, 6, 0, 0]} fill={PALETTE[0]} />
              </BarChart>
            </ResponsiveContainer>
          )}
        </div>

        <div className="card" style={{ padding: 20 }}>
          <h3 style={{ margin: '0 0 14px', fontSize: 15, fontWeight: 700 }}>Revenue by Service Type</h3>
          {!dash ? <div className="skeleton" style={{ height: 260 }} /> : dash.revenue_by_service_type.length === 0 ? (
            <NoData
              height={260}
              title="No revenue yet"
              description="Once visits are paid for, this shows how the money splits between companions, nurses and physiotherapy."
            />
          ) : (
            <ResponsiveContainer width="100%" height={260}>
              <PieChart>
                <Pie
                  data={dash.revenue_by_service_type}
                  dataKey="revenue"
                  nameKey="service_type"
                  innerRadius={58}
                  outerRadius={92}
                  paddingAngle={2}
                  label={({ percent }) => `${((percent ?? 0) * 100).toFixed(0)}%`}
                  labelLine={false}
                >
                  {dash.revenue_by_service_type.map((_, i) => <Cell key={i} fill={PALETTE[i % PALETTE.length]} />)}
                </Pie>
                <Tooltip formatter={(v: any, _n, p: any) => [inr(Number(v)), SERVICE_TYPE_LABELS[p.payload.service_type as keyof typeof SERVICE_TYPE_LABELS]]} contentStyle={{ fontSize: 12.5, borderRadius: 8 }} />
                <Legend
                  formatter={(_v, entry: any) => SERVICE_TYPE_LABELS[entry?.payload?.service_type as keyof typeof SERVICE_TYPE_LABELS] ?? ''}
                  wrapperStyle={{ fontSize: 12 }}
                />
              </PieChart>
            </ResponsiveContainer>
          )}
        </div>
      </div>

      <div className="card" style={{ padding: 20, marginBottom: 20 }}>
        <h3 style={{ margin: '0 0 14px', fontSize: 15, fontWeight: 700 }}>Revenue by Provider</h3>
        {!dash ? <div className="skeleton" style={{ height: 220 }} /> : dash.revenue_by_provider.length === 0 ? (
          <NoData
            height={220}
            title="No provider has earned yet"
            description="This ranks providers by what their completed visits have brought in. It fills up as bookings are settled."
          />
        ) : (
          <>
            <ResponsiveContainer width="100%" height={Math.max(220, dash.revenue_by_provider.length * 30)}>
              <BarChart data={dash.revenue_by_provider} layout="vertical" margin={{ left: 8, right: 16 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#eef1f5" horizontal={false} />
                <XAxis type="number" tick={{ fontSize: 11 }} tickFormatter={(v) => `₹${(v / 1000).toFixed(0)}k`} />
                <YAxis type="category" dataKey="provider_name" tick={{ fontSize: 11.5 }} width={130} />
                <Tooltip formatter={(v: any) => inr(Number(v))} contentStyle={{ fontSize: 12.5, borderRadius: 8 }} />
                <Bar dataKey="revenue" radius={[0, 6, 6, 0]} fill={PALETTE[1]} />
              </BarChart>
            </ResponsiveContainer>
            <div style={{ overflowX: 'auto', marginTop: 14 }}>
              <table className="data-table">
                <thead><tr><th>Provider</th><th>ID</th><th>Bookings</th><th>Revenue</th></tr></thead>
                <tbody>
                  {dash.revenue_by_provider.slice(0, 10).map((p) => (
                    <tr key={p.provider_id}>
                      <td>{p.provider_name}</td>
                      <td>{p.display_id}</td>
                      <td>{p.bookings}</td>
                      <td style={{ fontWeight: 600 }}>{inr(p.revenue)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        )}
      </div>

      <div className="card" style={{ padding: 20, marginBottom: 20 }}>
        <h3 style={{ margin: '0 0 4px', fontSize: 15, fontWeight: 700 }}>Where people are signing up from</h3>
        <p style={{ margin: '0 0 16px', fontSize: 13, color: 'var(--color-text-muted)' }}>
          Every registration reports the city its phone was in. People outside the service area
          keep their account and wait, so these rows are demand Sathiyaa has not served yet —
          which is the case for where to open next.
          {places && ` Serving ${places.serviceArea.city} within ${places.serviceArea.radiusKm} km.`}
        </p>

        {placesError ? <ErrorState message={placesError} />
          : !places ? <div className="skeleton" style={{ height: 200 }} />
          : places.places.length === 0 ? (
            <NoData
              height={180}
              title="Nothing reported yet"
              description="Sign-up locations are collected by the apps from the next release onwards. Nobody has registered since."
            />
          ) : (
          <>
            <div style={{ overflowX: 'auto' }}>
              <table className="table" style={{ width: '100%' }}>
                <thead>
                  <tr>
                    <th>City</th>
                    <th style={{ textAlign: 'right' }}>Families</th>
                    <th style={{ textAlign: 'right' }}>Carers</th>
                    <th style={{ textAlign: 'right' }}>Total</th>
                    <th>Served</th>
                  </tr>
                </thead>
                <tbody>
                  {places.places.map((p) => {
                    const served = p.customersInside + p.providersInside > 0;
                    return (
                      <tr key={`${p.city}|${p.state}`}>
                        <td>
                          <div style={{ fontWeight: 600 }}>{p.city}</div>
                          {p.state && (
                            <div style={{ fontSize: 12, color: 'var(--color-text-muted)' }}>{p.state}</div>
                          )}
                        </td>
                        <td style={{ textAlign: 'right', fontVariantNumeric: 'tabular-nums' }}>{p.customers}</td>
                        <td style={{ textAlign: 'right', fontVariantNumeric: 'tabular-nums' }}>{p.providers}</td>
                        <td style={{ textAlign: 'right', fontVariantNumeric: 'tabular-nums', fontWeight: 700 }}>
                          {p.customers + p.providers}
                        </td>
                        <td>
                          <span className={`badge ${served ? 'badge-green' : 'badge-amber'}`}>
                            {served ? 'In the service area' : 'Waiting'}
                          </span>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
            {(places.notReported.customers > 0 || places.notReported.providers > 0) && (
              <p style={{ margin: '14px 0 0', fontSize: 12.5, color: 'var(--color-text-muted)' }}>
                {places.notReported.customers} families and {places.notReported.providers} carers
                never reported a location — they registered before this existed, or refused the
                prompt. Every figure above is a floor, not a total.
              </p>
            )}
          </>
        )}
      </div>

      <div className="card" style={{ padding: 20 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14, flexWrap: 'wrap', gap: 10 }}>
          <h3 style={{ margin: 0, fontSize: 15, fontWeight: 700 }}>New Customers &amp; Providers</h3>
          <div className="tabs" style={{ borderBottom: 'none' }}>
            {PERIODS.map((p) => (
              <button key={p.value} className={`tab-btn ${period === p.value ? 'active' : ''}`} onClick={() => setPeriod(p.value)} style={{ marginRight: 16 }}>
                {p.label}
              </button>
            ))}
          </div>
        </div>
        {growthError ? <ErrorState message={growthError} />
          : !growth ? <div className="skeleton" style={{ height: 260 }} />
          : growth.points.length === 0 ? (
            <NoData
              height={260}
              title="Nothing to chart yet"
              description="Sign-ups are counted per period. Nobody has registered in the range this period covers."
            />
          ) : (
          <ResponsiveContainer width="100%" height={280}>
            <LineChart data={growth.points} margin={{ left: 0, right: 16 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#eef1f5" vertical={false} />
              <XAxis dataKey="period_label" tick={{ fontSize: 11 }} interval="preserveStartEnd" />
              <YAxis tick={{ fontSize: 11 }} width={32} allowDecimals={false} />
              <Tooltip contentStyle={{ fontSize: 12.5, borderRadius: 8 }} />
              <Legend wrapperStyle={{ fontSize: 12 }} />
              <Line type="monotone" dataKey="new_customers" name="New customers" stroke={PALETTE[0]} strokeWidth={2.5} dot={false} />
              <Line type="monotone" dataKey="new_providers" name="New providers" stroke={PALETTE[1]} strokeWidth={2.5} dot={false} />
            </LineChart>
          </ResponsiveContainer>
        )}
      </div>
    </div>
  );
}
