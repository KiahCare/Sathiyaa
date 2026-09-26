/**
 * Google Maps Platform — geocoding and directions.
 *
 * Written and ready, but only used when `MAPS_PROVIDER=google`.
 *
 *   MAPS_PROVIDER=google
 *   GOOGLE_MAPS_API_KEY=...
 *
 * The key needs the **Geocoding API** and **Directions API** enabled, and
 * billing switched on — Google will not answer without a billing account even
 * inside the free tier. Restrict the key to those two APIs and to your
 * server's IP; a leaked unrestricted key gets expensive fast.
 *
 * The Flutter apps do not use this key. They show a placeholder panel instead
 * of an embedded map, so there is no key shipped inside an APK where anyone
 * could pull it out. Distance and ETA come from here, server-side.
 */
import { env } from '../../config/env.js';
import { haversineKm } from '../../utils/haversine.js';
import { httpJson, requireConfig } from './_shared.js';

function key() {
  requireConfig('Google Maps', { GOOGLE_MAPS_API_KEY: env.googleMaps.apiKey });
  return env.googleMaps.apiKey;
}

export async function geocode(addressText) {
  const url = new URL('https://maps.googleapis.com/maps/api/geocode/json');
  url.searchParams.set('address', addressText);
  url.searchParams.set('key', key());
  // Bias results to India, which is the only market so far.
  url.searchParams.set('region', 'in');

  const res = await httpJson('Google Maps', url.toString());
  const best = res?.results?.[0];
  if (!best) {
    return { formattedAddress: addressText, latitude: null, longitude: null, status: res?.status };
  }
  return {
    formattedAddress: best.formatted_address,
    latitude: best.geometry?.location?.lat ?? null,
    longitude: best.geometry?.location?.lng ?? null,
    placeId: best.place_id,
  };
}

/**
 * Straight-line distance. Deliberately still haversine even with a real key:
 * it is used inside the provider-search query for every candidate, and paying
 * Google per candidate per search would be absurd. Road distance is only
 * fetched for the one route a provider is actually driving.
 */
export function distanceKm(lat1, lon1, lat2, lon2) {
  return haversineKm(lat1, lon1, lat2, lon2);
}

export async function getDirections({ fromLat, fromLng, toLat, toLng }) {
  const url = new URL('https://maps.googleapis.com/maps/api/directions/json');
  url.searchParams.set('origin', `${fromLat},${fromLng}`);
  url.searchParams.set('destination', `${toLat},${toLng}`);
  url.searchParams.set('mode', 'driving');
  url.searchParams.set('departure_time', 'now'); // live traffic in the ETA
  url.searchParams.set('key', key());

  const res = await httpJson('Google Maps', url.toString());
  const leg = res?.routes?.[0]?.legs?.[0];
  if (!leg) {
    // No route (wrong side of water, bad coordinates) — fall back to the
    // straight line rather than failing the whole request.
    const km = haversineKm(fromLat, fromLng, toLat, toLng);
    return {
      distanceKm: km,
      etaMinutes: km == null ? null : Math.max(1, Math.round((km / 25) * 60)),
      polyline: null,
      origin: { lat: fromLat, lng: fromLng },
      destination: { lat: toLat, lng: toLng },
      status: res?.status || 'NO_ROUTE',
    };
  }

  const seconds = leg.duration_in_traffic?.value ?? leg.duration?.value ?? 0;
  return {
    distanceKm: Math.round((leg.distance.value / 1000) * 10) / 10,
    etaMinutes: Math.max(1, Math.round(seconds / 60)),
    polyline: res.routes[0].overview_polyline?.points ?? null,
    origin: { lat: fromLat, lng: fromLng, address: leg.start_address },
    destination: { lat: toLat, lng: toLng, address: leg.end_address },
  };
}
