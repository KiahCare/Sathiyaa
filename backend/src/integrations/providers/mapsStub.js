/**
 * Maps/geocoding & directions integration stub.
 * Swap in Google Maps Platform here (Geocoding API, Directions API).
 * Currently returns straight-line (haversine) distance and a fake
 * polyline/ETA based on an assumed average travel speed.
 */
import { haversineKm } from '../../utils/haversine.js';

const ASSUMED_SPEED_KMPH = 25;

export async function geocode(addressText) {
  // Stub: cannot really geocode without a real provider; caller should
  // already have lat/lng from the client's map picker in most flows.
  return { formattedAddress: addressText, latitude: null, longitude: null, stub: true };
}

export function distanceKm(lat1, lon1, lat2, lon2) {
  return haversineKm(lat1, lon1, lat2, lon2);
}

export async function getDirections({ fromLat, fromLng, toLat, toLng }) {
  const km = haversineKm(fromLat, fromLng, toLat, toLng);
  const etaMinutes = km == null ? null : Math.max(1, Math.round((km / ASSUMED_SPEED_KMPH) * 60));
  return {
    distanceKm: km,
    etaMinutes,
    polyline: 'stub_polyline_straight_line', // real impl: encoded polyline from Directions API
    origin: { lat: fromLat, lng: fromLng },
    destination: { lat: toLat, lng: toLng },
  };
}
