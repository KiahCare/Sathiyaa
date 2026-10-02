/** display_id generators: e.g. CUST-000001, SP-000001, BP-000001 */
export function displayId(prefix, numericId) {
  return `${prefix}-${String(numericId).padStart(6, '0')}`;
}

/** Booking display id: BKG-<yyyymmdd>-<seq> */
export function bookingDisplayId(numericId) {
  return `BKG-${String(numericId).padStart(8, '0')}`;
}

export function randomReferralCode(entityName = '') {
  const slug = entityName
    .replace(/[^a-zA-Z]/g, '')
    .toUpperCase()
    .slice(0, 4)
    .padEnd(4, 'X');
  const rand = Math.floor(1000 + Math.random() * 9000);
  return `${slug}${rand}`;
}

