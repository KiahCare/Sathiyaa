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

export function randomVirtualNumber() {
  // Fake Indian-format virtual number for the call-masking stub.
  const rand = Math.floor(1000000000 + Math.random() * 8999999999);
  return `+91${String(rand).slice(0, 10)}`;
}
