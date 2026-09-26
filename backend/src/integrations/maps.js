/**
 * Maps: geocoding, distance and directions.
 *
 * `MAPS_PROVIDER` chooses the implementation; the default stub returns
 * straight-line distance and an ETA from an assumed average speed, which is
 * enough to exercise every screen without a billing account.
 *
 * Note that `distanceKm` stays haversine even with Google enabled: it runs
 * once per candidate provider on every search, and billing that would be
 * indefensible. Only the single route a provider actually drives is fetched.
 */
import { env } from '../config/env.js';
import * as stub from './providers/mapsStub.js';
import * as google from './providers/googleMaps.js';
import * as osm from './providers/osm.js';

// `osm` is the free option: real geocoding and real road routing from
// OpenStreetMap, with no account and no key. `google` adds live traffic and
// heavier coverage, and needs billing enabled.
const impl = env.integrations.maps === 'google' ? google : env.integrations.maps === 'osm' ? osm : stub;

export const providerName = ['google', 'osm'].includes(env.integrations.maps) ? env.integrations.maps : 'stub';
export const isLive = providerName !== 'stub';

export const geocode = (...args) => impl.geocode(...args);
export const distanceKm = (...args) => impl.distanceKm(...args);
export const getDirections = (...args) => impl.getDirections(...args);
