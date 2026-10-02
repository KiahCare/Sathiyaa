/**
 * Where Sathiyaa currently operates, and whether a given place is inside it.
 *
 * Sathiyaa launched in Ahmedabad and now also serves Gandhinagar. The apps ask
 * the phone where it is once, at registration, and this decides what that means.
 *
 * The decision is made HERE, not in the app. An app that scores itself is an
 * app that can be made to say yes by anyone who edits a request, and — more
 * mundanely — an app that has to be rebuilt and re-reviewed every time the
 * business opens a new city. The numbers live in app_configuration so opening
 * Surat is a value typed into the console.
 *
 * Two ways to be inside, and either is enough:
 *
 *   by name      the geocoder named one of the configured cities
 *   by distance  the coordinates are within the radius of the centre
 *
 * Deliberately lenient. A false "we are not in your city" loses a customer
 * permanently and they never tell you why; a false "yes" costs one search
 * that finds nobody close. Those are not remotely the same mistake, so the
 * cheap one is the one this errs towards — a phone indoors with a bad fix,
 * an unusual spelling, or a geocoder that names the district rather than the
 * city all still get in.
 */
import { query } from '../db/pool.js';
import { getConfig, getConfigNumber } from './appConfig.js';
import { haversineKm } from '../utils/haversine.js';

/** The built-in fallback, used only if the configuration rows are missing. */
const FALLBACK = {
  enabled: true,
  city: 'Ahmedabad, Gandhinagar',
  state: 'Gujarat',
  lat: 23.0225,
  lng: 72.5714,
  radiusKm: 35,
};

/**
 * The configured city value, as a list.
 *
 * `service_area_city` started as one city because Sathiyaa launched in one.
 * It now holds a comma-separated list, because the twin-city case arrived
 * immediately: Gandhinagar is 25 km from Ahmedabad, inside the radius, and
 * full of people a carer can reach -- but a phone there whose geocoder says
 * "Gandhinagar" and whose GPS was refused matched no city name and was turned
 * away at registration.
 *
 * A plain string stays valid, so nothing that wrote one value breaks.
 */
function cityList(value) {
  return String(value || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
}

/** The live service area, as the console has it. */
export async function getServiceArea() {
  const [enabled, city, state, lat, lng, radiusKm] = await Promise.all([
    getConfig('service_area_enabled', String(FALLBACK.enabled)),
    getConfig('service_area_city', FALLBACK.city),
    getConfig('service_area_state', FALLBACK.state),
    getConfigNumber('service_area_lat', FALLBACK.lat),
    getConfigNumber('service_area_lng', FALLBACK.lng),
    getConfigNumber('service_area_radius_km', FALLBACK.radiusKm),
  ]);
  const cities = cityList(city);
  return {
    enabled: String(enabled).toLowerCase() !== 'false',
    // `city` stays a string for every existing caller -- the console field,
    // the apps' "we do not serve your city yet" message, the audit trail.
    city: city || FALLBACK.city,
    // `cities` is the parsed form, for matching.
    cities: cities.length ? cities : cityList(FALLBACK.city),
    state: state || FALLBACK.state,
    lat,
    lng,
    radiusKm,
  };
}

/**
 * Loose city matching.
 *
 * Geocoders are not consistent about Indian cities: the same coordinates come
 * back as "Ahmedabad", "Ahmadabad", "Ahmedabad City", "Ahmedabad District" or
 * "અમદાવાદ" depending on the language header and the zoom level. Comparing
 * exact strings would turn a correct answer into a rejection, so this strips
 * everything that is not a letter and asks whether one contains the other.
 */
function sameCity(a, b) {
  const clean = (s) => String(s || '').toLowerCase().replace(/[^a-z]/g, '');
  const x = clean(a);
  const y = clean(b);
  if (!x || !y) return false;
  if (x === y) return true;
  // "ahmedabaddistrict" and "ahmedabadcity" both START WITH "ahmedabad".
  //
  // Anchored at the front rather than matched anywhere, which is what this
  // did before there was more than one city to match against. "nagar" is a
  // substring of "gandhinagar" and is also the name of half the localities in
  // Gujarat, so an unanchored check would have let a locality in Surat
  // register as Gandhinagar. Every case the leniency was written for is a
  // suffix on the city name, so the front is where the anchor belongs.
  if (x.startsWith(y) || y.startsWith(x)) return true;
  // Ahmedabad / Ahmadabad differ by one vowel, and both are in daily use.
  return x.replace(/[aeiou]/g, '') === y.replace(/[aeiou]/g, '');
}

/**
 * Whether a reported place is somewhere Sathiyaa serves.
 *
 * Returns `{ inside, reason, area }`. `reason` is for the audit trail and the
 * console, never for the person — being told you failed a radius check is not
 * an explanation anybody wants.
 */
export async function isInServiceArea({ lat, lng, city, state }) {
  const area = await getServiceArea();
  if (!area.enabled) return { inside: true, reason: 'gate_off', area };

  if (area.cities.some((c) => sameCity(city, c))) return { inside: true, reason: 'city_name', area };

  // Null Island is not a place anybody registered from.
  //
  // `Number(null)` is 0, so a missing coordinate used to pass Number.isFinite
  // and be measured as a point off the coast of Ghana -- six thousand
  // kilometres out, comfortably "outside", and a phone that simply refused
  // the location prompt was locked out of the app for it.
  const nums = [lat, lng].map((v) => (v === null || v === undefined || v === '' ? NaN : Number(v)));
  const hasFix = nums.every(Number.isFinite) && !(nums[0] === 0 && nums[1] === 0);
  if (hasFix) {
    const km = haversineKm(nums[0], nums[1], area.lat, area.lng);
    if (km <= area.radiusKm) return { inside: true, reason: 'within_radius', area, km };
    // A fix that is a long way out and a city name that disagrees is the one
    // case we are confident about.
    return { inside: false, reason: 'outside_radius', area, km };
  }

  // No coordinates and a city that does not match. If the geocoder gave us
  // nothing at all we cannot say they are outside — only that we do not know,
  // and "do not know" must not lock somebody out of the app.
  if (!city && !state) return { inside: true, reason: 'unknown_place', area };

  return { inside: false, reason: 'city_mismatch', area };
}

/**
 * Records where somebody registered from, and returns the verdict.
 *
 * Called once, from the app, straight after registration. It stores the raw
 * place as reported — coordinates, and whatever the geocoder made of them —
 * alongside the verdict this server reached, so a later change to the radius
 * does not rewrite history and the console can still count who asked from
 * where.
 *
 * `table` and `idColumn` are never user input: both call sites pass literals.
 */
export async function recordSignupPlace({ table, idColumn, id, place }) {
  const lat = Number.isFinite(Number(place.latitude)) ? Number(place.latitude) : null;
  const lng = Number.isFinite(Number(place.longitude)) ? Number(place.longitude) : null;
  const city = place.city ? String(place.city).slice(0, 100) : null;
  const state = place.state ? String(place.state).slice(0, 100) : null;
  const pincode = place.pincode ? String(place.pincode).slice(0, 12) : null;

  const verdict = await isInServiceArea({ lat, lng, city, state });

  await query(
    `UPDATE ${table}
        SET signup_latitude = ?, signup_longitude = ?, signup_city = ?,
            signup_state = ?, signup_pincode = ?, signup_in_service_area = ?,
            signup_place_at = NOW()
      WHERE ${idColumn} = ?`,
    [lat, lng, city, state, pincode, verdict.inside ? 1 : 0, id]
  );

  return verdict;
}
