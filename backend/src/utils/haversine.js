const EARTH_RADIUS_KM = 6371;

export function haversineKm(lat1, lon1, lat2, lon2) {
  if ([lat1, lon1, lat2, lon2].some((v) => v === null || v === undefined || Number.isNaN(Number(v)))) {
    return null;
  }
  const toRad = (deg) => (deg * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return Math.round(EARTH_RADIUS_KM * c * 1000) / 1000; // 3 decimal places
}

/** MySQL-flavour haversine expression (km), for use inside SQL queries.
 * Placeholders %LAT_COL%/%LNG_COL% are substituted by the caller. */
export function haversineSqlExpr(latCol, lngCol) {
  return `(6371 * ACOS(
      COS(RADIANS(?)) * COS(RADIANS(${latCol})) * COS(RADIANS(${lngCol}) - RADIANS(?))
      + SIN(RADIANS(?)) * SIN(RADIANS(${latCol}))
    ))`;
}
