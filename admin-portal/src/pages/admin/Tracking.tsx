import { useEffect, useMemo, useRef, useState } from 'react';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import type { ProviderTrackingEntry } from '../../types';
import { SERVICE_TYPE_LABELS } from '../../types';
import { getTracking } from '../../api/services';
import { PageHeader, ErrorState, EmptyState, StatCard } from '../../components/ui';

/** Minutes since a position was reported, or null if it never was. */
function ageMinutes(at: string | null | undefined): number | null {
  if (!at) return null;
  // MySQL DATETIME comes back without a zone; the server stores UTC.
  const iso = /[zZ]|[+-]\d{2}:?\d{2}$/.test(at) ? at : `${at.replace(' ', 'T')}Z`;
  const ms = Date.now() - new Date(iso).getTime();
  return Number.isFinite(ms) ? Math.max(0, Math.round(ms / 60000)) : null;
}

/** "just now", "12 min ago", "3 h ago", "2 days ago". */
function ago(minutes: number | null): string {
  if (minutes === null) return 'never reported';
  if (minutes < 2) return 'just now';
  if (minutes < 60) return `${minutes} min ago`;
  if (minutes < 48 * 60) return `${Math.round(minutes / 60)} h ago`;
  return `${Math.round(minutes / (60 * 24))} days ago`;
}

// The app reports every two minutes while sharing is on, so anything past ten
// is either a phone that has lost signal or an app that is no longer running.
// Either way it is a last known position, not a live one, and the difference
// matters to whoever is looking at this map to find somebody.
const STALE_AFTER_MINUTES = 10;

export default function Tracking() {
  const [entries, setEntries] = useState<ProviderTrackingEntry[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<number | null>(null);
  const [autoRefresh, setAutoRefresh] = useState(true);

  async function load() {
    setError(null);
    try {
      setEntries(await getTracking());
    } catch (err: any) {
      setError(err?.message ?? 'Failed to load live tracking.');
    }
  }

  useEffect(() => { load(); }, []);
  useEffect(() => {
    if (!autoRefresh) return;
    const t = setInterval(load, 15000);
    return () => clearInterval(t);
  }, [autoRefresh]);

  const withLocation = useMemo(() => (entries ?? []).filter((e) => e.location_on && e.current_latitude != null && e.current_longitude != null), [entries]);
  const onlineCount = withLocation.length;
  const busyCount = withLocation.filter((e) => e.on_active_booking).length;
  const staleCount = withLocation.filter((e) => {
    const m = ageMinutes(e.current_location_at);
    return m === null || m > STALE_AFTER_MINUTES;
  }).length;

  if (error) return <ErrorState message={error} onRetry={load} />;

  return (
    <div>
      <PageHeader
        title="Live Provider Tracking"
        subtitle="Last known location and location-sharing status for all providers. The app reports every two minutes while sharing is on, so anything older than ten is a last known position rather than a live one."
        actions={
          <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12.5, color: 'var(--color-text-muted)' }}>
            <input type="checkbox" checked={autoRefresh} onChange={(e) => setAutoRefresh(e.target.checked)} />
            Auto-refresh every 15s
          </label>
        }
      />

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: 14, marginBottom: 20 }}>
        <StatCard label="Total active providers" value={entries ? String(entries.length) : '—'} />
        <StatCard label="Location sharing on" value={entries ? String(onlineCount) : '—'} accent="var(--color-success)" />
        <StatCard label="Location sharing off" value={entries ? String(entries.length - onlineCount) : '—'} accent="var(--color-text-muted)" />
        <StatCard label="On active booking" value={entries ? String(busyCount) : '—'} accent="var(--color-accent)" />
        <StatCard
          label="Position older than 10 min"
          value={entries ? String(staleCount) : '—'}
          sub="Sharing is on but nothing is arriving"
          accent={staleCount > 0 ? 'var(--color-warning)' : 'var(--color-text-muted)'}
        />
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'minmax(340px, 1fr) 380px', gap: 18 }} className="tracking-grid">
        <div className="card" style={{ padding: 20 }}>
          <h3 style={{ margin: '0 0 14px', fontSize: 15, fontWeight: 700 }}>Location Map</h3>
          {!entries ? (
            <div className="skeleton" style={{ height: 420 }} />
          ) : withLocation.length === 0 ? (
            <EmptyState icon="📍" title="No providers currently sharing location" />
          ) : (
            <ScatterMap entries={withLocation} selected={selected} onSelect={setSelected} />
          )}
        </div>

        <div className="card" style={{ padding: 0, maxHeight: 560, overflowY: 'auto' }}>
          <h3 style={{ margin: 0, fontSize: 15, fontWeight: 700, padding: '20px 20px 10px' }}>Providers</h3>
          {!entries && <div style={{ padding: 20 }}><div className="skeleton" style={{ height: 300 }} /></div>}
          {entries && entries.length === 0 && <EmptyState icon="🩺" title="No active providers" />}
          {entries && entries.map((e) => (
            <div
              key={e.provider_id}
              onClick={() => e.location_on && setSelected(e.provider_id)}
              style={{
                display: 'flex', alignItems: 'center', gap: 10, padding: '12px 20px',
                borderTop: '1px solid var(--color-border)', cursor: e.location_on ? 'pointer' : 'default',
                background: selected === e.provider_id ? 'var(--color-primary-light)' : 'transparent',
              }}
            >
              <span style={{
                width: 9, height: 9, borderRadius: '50%', flexShrink: 0,
                background: e.location_on ? (e.on_active_booking ? '#2563eb' : '#12b76a') : '#d0d5dd',
                // Hollow rather than solid once the position is old, so a
                // stale pin does not read as somebody standing there now.
                opacity: e.location_on && (() => {
                  const m = ageMinutes(e.current_location_at);
                  return m === null || m > STALE_AFTER_MINUTES;
                })() ? 0.35 : 1,
              }} />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontWeight: 600, fontSize: 13, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{e.name}</div>
                <div style={{ fontSize: 11.5, color: 'var(--color-text-muted)' }}>
                  {e.display_id}{e.service_types?.length ? ` · ${e.service_types.map((s) => SERVICE_TYPE_LABELS[s]).join(', ')}` : ''}
                </div>
              </div>
              <div style={{ textAlign: 'right', fontSize: 11 }}>
                {e.location_on ? (
                  <>
                    <div style={{ color: e.on_active_booking ? 'var(--color-accent)' : 'var(--color-success)', fontWeight: 600 }}>
                      {e.on_active_booking ? 'On booking' : 'Available'}
                    </div>
                    <div style={{ color: 'var(--color-text-muted)' }}>
                      {e.current_latitude?.toFixed(4)}, {e.current_longitude?.toFixed(4)}
                    </div>
                    {(() => {
                      const m = ageMinutes(e.current_location_at);
                      const stale = m === null || m > STALE_AFTER_MINUTES;
                      return (
                        <div style={{
                          color: stale ? 'var(--color-warning)' : 'var(--color-text-muted)',
                          fontWeight: stale ? 600 : 400,
                        }}>
                          {ago(m)}
                        </div>
                      );
                    })()}
                  </>
                ) : (
                  <span className="badge badge-gray">Off</span>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>
      <style>{`@media (max-width: 900px) { .tracking-grid { grid-template-columns: 1fr !important; } }`}</style>
    </div>
  );
}

/**
 * Provider positions on a real map.
 *
 * This was a scatter plot of dots on a blank grid -- technically the right
 * coordinates, but with nothing behind them you could not tell Koramangala
 * from Kolkata. It now draws OpenStreetMap tiles underneath, the same free
 * mapping stack the apps and the server use: no key, no account, no bill.
 *
 * Plain Leaflet rather than a React wrapper, and circle markers rather than
 * Leaflet's default pin -- the default icon loads its image by relative URL
 * and silently breaks under a bundler.
 */
function ScatterMap({
  entries, selected, onSelect,
}: {
  entries: ProviderTrackingEntry[];
  selected: number | null;
  onSelect: (id: number) => void;
}) {
  const hostRef = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<L.Map | null>(null);
  const markersRef = useRef<globalThis.Map<number, L.CircleMarker>>(new globalThis.Map());

  // Created once. Rebuilding the map on every render would throw away the
  // operator's pan and zoom, which is maddening on a page that refreshes
  // itself every fifteen seconds.
  useEffect(() => {
    if (!hostRef.current || mapRef.current) return;
    const map = L.map(hostRef.current, { scrollWheelZoom: true }).setView([12.9716, 77.5946], 12);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      // Required by OpenStreetMap's tile usage policy.
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    }).addTo(map);
    mapRef.current = map;
    return () => {
      map.remove();
      mapRef.current = null;
      markersRef.current.clear();
    };
  }, []);

  // Redraw the pins whenever the tracking data changes.
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;

    markersRef.current.forEach((m) => m.remove());
    markersRef.current.clear();

    const points: L.LatLngTuple[] = [];
    for (const e of entries) {
      const lat = e.current_latitude;
      const lng = e.current_longitude;
      if (lat == null || lng == null) continue;
      points.push([lat, lng]);
      const onJob = e.on_active_booking;
      const marker = L.circleMarker([lat, lng], {
        radius: selected === e.provider_id ? 10 : 7,
        color: '#ffffff',
        weight: 2,
        fillColor: onJob ? '#2563eb' : '#12b76a',
        fillOpacity: 1,
      })
        .addTo(map)
        .bindTooltip(
          `<strong>${e.name}</strong><br>${e.display_id}${onJob ? ' - on a booking' : ' - available'}`,
          { direction: 'top' }
        )
        .on('click', () => onSelect(e.provider_id));
      markersRef.current.set(e.provider_id, marker);
    }

    if (points.length === 1) map.setView(points[0], 14);
    else if (points.length > 1) map.fitBounds(L.latLngBounds(points), { padding: [40, 40] });
  }, [entries, selected, onSelect]);

  // Centre on whoever the operator picked in the list beside the map.
  useEffect(() => {
    const map = mapRef.current;
    if (!map || selected == null) return;
    const e = entries.find((x) => x.provider_id === selected);
    if (e?.current_latitude != null && e.current_longitude != null) {
      map.panTo([e.current_latitude, e.current_longitude]);
      markersRef.current.get(selected)?.openTooltip();
    }
  }, [selected, entries]);

  return (
    <div
      ref={hostRef}
      style={{ height: 420, width: '100%', borderRadius: 10, border: '1px solid var(--color-border)' }}
    />
  );
}
