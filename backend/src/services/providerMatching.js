import { query } from '../db/pool.js';
import { haversineSqlExpr } from '../utils/haversine.js';
import { Errors } from '../utils/apiError.js';

const DOW = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];

/**
 * The weekday a calendar date falls on, as stored in
 * service_provider_work_hours.day_of_week.
 *
 * Parsed at local midnight rather than as a UTC instant, so the answer is the
 * weekday a person reading a calendar would give, whatever timezone the server
 * runs in. A date-only string is what the apps send; anything longer (a full
 * ISO timestamp, say) is trimmed to its date part first. An unparseable date
 * throws: the alternative is a query that joins on `undefined`, matches no
 * work-hours row, and quietly reports that nobody is available.
 */
export function dayOfWeekFromDate(dateStr) {
  const datePart = String(dateStr ?? '').trim().slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(datePart)) {
    throw Errors.unprocessable('INVALID_DATE', `Invalid date: ${dateStr}. Expected YYYY-MM-DD.`);
  }
  const dow = DOW[new Date(`${datePart}T00:00:00`).getDay()];
  if (!dow) {
    throw Errors.unprocessable('INVALID_DATE', `Invalid date: ${dateStr}. Expected YYYY-MM-DD.`);
  }
  return dow;
}

/**
 * Finds providers available for a booking request / search.
 * Respects: approval + active status, service-type expertise, work-hours
 * for the start date's day-of-week, calendar blocks overlapping the
 * requested date range, existing confirmed/in_progress bookings that
 * overlap the requested date range, gender preference, language
 * preference, and (if lat/lng given) a radius filter via haversine
 * distance from the provider's home address.
 *
 * "Allocate Employee" organizations (requirement: "If Allocate Employee
 * option is selected then only Organization Name will be displayed...
 * Employees of the service organization will not be displayed in search,
 * just organization name") are matched separately: their org_employee
 * rows are excluded from the individual-provider result set, and the
 * organization itself is surfaced instead whenever at least one of its
 * employees could plausibly serve the request. MVP simplification
 * (documented in the coverage matrix): the org-row check only looks at
 * employee service-type expertise and work-hours for the day/time
 * requested — not calendar blocks or already-booked employees, gender,
 * or language — since the org admin picks (and can see true availability
 * for) a specific employee only after the booking request is allocated.
 *
 * NOTE (MVP simplification): multi-day work-hours/day-of-week matching
 * is checked against the *start date* only, not every day in the range.
 * Documented in README as a known simplification.
 */
export async function findMatchingProviders({
  serviceType,
  dateFrom,
  dateTo,
  timeFrom,
  timeTo,
  lat,
  lng,
  radiusKm,
  gender,
  language,
  excludeProviderIds = [],
}) {
  if (!serviceType || !dateFrom) {
    throw new Error('serviceType and dateFrom are required for matching');
  }
  // A caller that names no hours wants anyone working that day, so the
  // work-hours comparison is dropped rather than run against a 00:00-23:59
  // window - which asks for providers on duty all twenty-four hours, and
  // matches nobody. Calendar blocks and existing bookings are still checked,
  // across the whole day.
  const hasTimeWindow = Boolean(timeFrom && timeTo);
  const rangeStartTime = timeFrom || '00:00:00';
  const rangeEndTime = timeTo || '23:59:59';
  const effectiveDateTo = dateTo || dateFrom;
  const dow = dayOfWeekFromDate(dateFrom);
  const hasGeo = lat !== undefined && lat !== null && lng !== undefined && lng !== null;
  const distanceExpr = hasGeo ? haversineSqlExpr('addr.latitude', 'addr.longitude') : 'NULL';

  const sql = `
    SELECT sp.*, se.years_experience,
      addr.latitude AS addr_lat, addr.longitude AS addr_lng,
      ${distanceExpr} AS distance_km
    FROM service_providers sp
    JOIN service_provider_expertise se ON se.provider_id = sp.provider_id AND se.service_type = ?
    JOIN service_provider_work_hours wh ON wh.provider_id = sp.provider_id AND wh.day_of_week = ?
    LEFT JOIN service_provider_addresses addr ON addr.provider_id = sp.provider_id AND addr.address_type = 'home'
    WHERE sp.approval_status = 'approved'
      AND sp.status = 'active'
      -- An organisation is not an individual carer.
      --
      -- Organisations are surfaced by the second query below, on the strength
      -- of the carers they can actually send. This query used to return them
      -- as well, whenever the org's own row happened to have expertise and
      -- work-hours -- so an agency came back TWICE, and the booking then
      -- inserted two booking_requests rows with the same (booking_id,
      -- provider_id). That unique key is there for good reason, and the
      -- duplicate insert surfaced as 409 "Record already exists" on the
      -- customer's booking screen. Every booking within range of that agency
      -- failed, for everybody.
      AND sp.provider_kind <> 'organization'
      ${hasTimeWindow ? 'AND wh.start_time <= ? AND wh.end_time >= ?' : ''}
      AND NOT (sp.provider_kind = 'org_employee' AND EXISTS (
        SELECT 1 FROM service_providers org WHERE org.provider_id = sp.organization_id AND org.allocate_via_org = TRUE
      ))
      ${gender ? 'AND sp.gender = ?' : ''}
      ${language ? "AND JSON_CONTAINS(sp.languages, JSON_QUOTE(?))" : ''}
      ${excludeProviderIds.length ? `AND sp.provider_id NOT IN (${excludeProviderIds.map(() => '?').join(',')})` : ''}
      AND NOT EXISTS (
        SELECT 1 FROM service_provider_calendar_blocks cb
        WHERE cb.provider_id = sp.provider_id
          AND cb.block_start < ? AND cb.block_end > ?
      )
      AND NOT EXISTS (
        SELECT 1 FROM bookings bk
        WHERE bk.confirmed_provider_id = sp.provider_id
          AND bk.status IN ('confirmed', 'in_progress')
          AND bk.start_date <= ? AND bk.end_date >= ?
      )
    ${hasGeo && radiusKm ? 'HAVING distance_km <= ?' : ''}
    ORDER BY ${hasGeo ? 'distance_km ASC,' : ''} sp.rating_avg DESC
  `;

  // Params must be supplied in the exact textual (left-to-right) order
  // the placeholders appear in the compiled SQL above.
  const fullParams = [];
  if (hasGeo) fullParams.push(lat, lng, lat); // SELECT ... distanceExpr
  fullParams.push(serviceType, dow); // JOIN expertise / work_hours
  if (hasTimeWindow) fullParams.push(timeFrom, timeTo); // wh.start_time <= timeFrom AND wh.end_time >= timeTo
  if (gender) fullParams.push(gender);
  if (language) fullParams.push(language);
  if (excludeProviderIds.length) fullParams.push(...excludeProviderIds);
  fullParams.push(`${effectiveDateTo} ${rangeEndTime}`, `${dateFrom} ${rangeStartTime}`); // calendar block overlap
  fullParams.push(effectiveDateTo, dateFrom); // existing booking overlap
  if (hasGeo && radiusKm) fullParams.push(radiusKm); // HAVING

  const rows = await query(sql, fullParams);

  const orgDistanceExpr = hasGeo ? haversineSqlExpr('addr.latitude', 'addr.longitude') : 'NULL';
  const orgSql = `
    SELECT DISTINCT org.*, NULL AS years_experience,
      addr.latitude AS addr_lat, addr.longitude AS addr_lng,
      ${orgDistanceExpr} AS distance_km
    FROM service_providers org
    JOIN service_providers emp ON emp.organization_id = org.provider_id AND emp.provider_kind = 'org_employee'
      AND emp.approval_status = 'approved' AND emp.status = 'active'
    JOIN service_provider_expertise se ON se.provider_id = emp.provider_id AND se.service_type = ?
    JOIN service_provider_work_hours wh ON wh.provider_id = emp.provider_id AND wh.day_of_week = ?
    LEFT JOIN service_provider_addresses addr ON addr.provider_id = org.provider_id AND addr.address_type = 'home'
    WHERE org.provider_kind = 'organization'
      AND org.allocate_via_org = TRUE
      AND org.approval_status = 'approved'
      AND org.status = 'active'
      ${hasTimeWindow ? 'AND wh.start_time <= ? AND wh.end_time >= ?' : ''}
    ${hasGeo && radiusKm ? 'HAVING distance_km <= ?' : ''}
  `;
  const orgParams = [];
  if (hasGeo) orgParams.push(lat, lng, lat);
  orgParams.push(serviceType, dow);
  if (hasTimeWindow) orgParams.push(timeFrom, timeTo);
  if (hasGeo && radiusKm) orgParams.push(radiusKm);
  const orgRows = await query(orgSql, orgParams);

  // One row per provider, whatever the two queries between them produced.
  //
  // The caller inserts a booking_requests row per candidate, and that table
  // has a UNIQUE (booking_id, provider_id) -- so a duplicate here is not a
  // cosmetic problem, it is a booking that fails with "Record already
  // exists". The WHERE clause above is what stops it happening; this is what
  // stops it ever mattering again.
  const seen = new Set();
  const unique = [...rows, ...orgRows].filter((p) => {
    const id = Number(p.provider_id);
    if (seen.has(id)) return false;
    seen.add(id);
    return true;
  });

  return unique.sort((a, b) => {
    if (hasGeo && a.distance_km !== null && b.distance_km !== null && a.distance_km !== b.distance_km) {
      return a.distance_km - b.distance_km;
    }
    return Number(b.rating_avg) - Number(a.rating_avg);
  });
}
