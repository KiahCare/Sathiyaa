/**
 * OpenStreetMap — geocoding via Nominatim, road routing via OSRM.
 *
 * A genuinely free alternative to Google Maps: no account, no API key, no
 * billing. Turn it on with `MAPS_PROVIDER=osm` and it works immediately.
 *
 * What you get versus Google:
 *  - Real geocoding and real road distances/durations, not straight lines.
 *  - No live traffic. OSRM returns free-flow driving times, so an ETA in rush
 *    hour will be optimistic.
 *  - Coverage in India is good for cities and main roads, thinner for very
 *    new developments than Google's.
 *
 * **Fair use matters here.** These are volunteer-funded public endpoints, not
 * a paid service. Nominatim's policy allows at most one request per second and
 * requires a genuine User-Agent identifying the application, both of which
 * this file honours. That is fine for testing and light use; before real
 * traffic, either self-host (both are open source and run in Docker) or move
 * to `MAPS_PROVIDER=google`.
 */
import { haversineKm } from '../../utils/haversine.js';
import { httpJson } from './_shared.js';

const NOMINATIM = process.env.NOMINATIM_URL || 'https://nominatim.openstreetmap.org';
const OSRM = process.env.OSRM_URL || 'https://router.project-osrm.org';

// Nominatim asks for a real contact point so they can get in touch about a
// misbehaving client rather than simply blocking it.
const USER_AGENT = process.env.OSM_USER_AGENT || 'SathiyaaHomeCare/1.0 (self-hosted deployment; contact via app admin)';

/** Serialises calls to at most one per second, as Nominatim's policy requires. */
let lastCall = 0;
async function rateLimit() {
  const since = Date.now() - lastCall;
  if (since < 1100) await new Promise((r) => setTimeout(r, 1100 - since));
  lastCall = Date.now();
}

export async function geocode(addressText) {
  if (!addressText || !addressText.trim()) {
    return { formattedAddress: addressText, latitude: null, longitude: null };
  }
  await rateLimit();

  const url = new URL(`${NOMINATIM}/search`);
  url.searchParams.set('q', addressText);
  url.searchParams.set('format', 'json');
  url.searchParams.set('limit', '1');
  url.searchParams.set('countrycodes', 'in'); // India is the only market so far
  url.searchParams.set('addressdetails', '1');

  const results = await httpJson('OpenStreetMap', url.toString(), {
    headers: { 'User-Agent': USER_AGENT },
  });

  const best = Array.isArray(results) ? results[0] : null;
  if (!best) {
    return { formattedAddress: addressText, latitude: null, longitude: null, status: 'ZERO_RESULTS' };
  }
  return {
    formattedAddress: best.display_name,
    latitude: Number(best.lat),
    longitude: Number(best.lon),
    placeId: `osm:${best.osm_type}/${best.osm_id}`,
  };
}

/**
 * Straight-line distance, deliberately not a routed one: this runs once per
 * candidate on every provider search, and hammering a free public router with
 * that volume would be an abuse of it. Only the single route a provider
 * actually drives is routed, below.
 */
export function distanceKm(lat1, lon1, lat2, lon2) {
  return haversineKm(lat1, lon1, lat2, lon2);
}

export async function getDirections({ fromLat, fromLng, toLat, toLng }) {
  const straightLine = haversineKm(fromLat, fromLng, toLat, toLng);

  if ([fromLat, fromLng, toLat, toLng].some((v) => v === null || v === undefined)) {
    return {
      distanceKm: straightLine,
      etaMinutes: straightLine == null ? null : Math.max(1, Math.round((straightLine / 25) * 60)),
      polyline: null,
      origin: { lat: fromLat, lng: fromLng },
      destination: { lat: toLat, lng: toLng },
      status: 'MISSING_COORDINATES',
    };
  }

  try {
    // OSRM takes lng,lat — the opposite order to almost everything else.
    const url =
      `${OSRM}/route/v1/driving/${fromLng},${fromLat};${toLng},${toLat}` +
      `?overview=full&geometries=polyline&alternatives=false&steps=false`;
    const res = await httpJson('OpenStreetMap', url, { headers: { 'User-Agent': USER_AGENT } });
    const route = res?.routes?.[0];
    if (!route) throw new Error(res?.message || 'no route');

    return {
      distanceKm: Math.round((route.distance / 1000) * 10) / 10,
      etaMinutes: Math.max(1, Math.round(route.duration / 60)),
      polyline: route.geometry ?? null,
      origin: { lat: fromLat, lng: fromLng },
      destination: { lat: toLat, lng: toLng },
      // Said plainly so nobody reads this ETA as traffic-aware.
      note: 'Free-flow driving time from OpenStreetMap; does not account for traffic.',
    };
  } catch (err) {
    // A free public router being busy must not break "Show direction"; fall
    // back to the straight line rather than failing the request.
    console.warn(`[OpenStreetMap] routing failed, falling back to straight line: ${err.message}`);
    return {
      distanceKm: straightLine,
      etaMinutes: straightLine == null ? null : Math.max(1, Math.round((straightLine / 25) * 60)),
      polyline: null,
      origin: { lat: fromLat, lng: fromLng },
      destination: { lat: toLat, lng: toLng },
      status: 'ROUTING_UNAVAILABLE',
    };
  }
}
