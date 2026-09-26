import { query } from '../db/pool.js';

export async function getConfig(key, fallback = null) {
  const rows = await query('SELECT config_value FROM app_configuration WHERE config_key = ?', [key]);
  return rows[0] ? rows[0].config_value : fallback;
}

export async function getConfigNumber(key, fallback = 0) {
  const v = await getConfig(key, null);
  if (v === null) return fallback;

  // A stored value that is not a number used to come back as NaN, and NaN
  // travels: it went into booking_charge_amount, into a payment total, into a
  // row in the database. The admin console cannot validate what is already in
  // the table, and older rows predate the validation on the way in, so the
  // read side refuses to hand out a number that is not one.
  const n = Number(v);
  if (!Number.isFinite(n)) {
    console.warn(`[config] ${key} is ${JSON.stringify(v)}, which is not a number. Using ${fallback}.`);
    return fallback;
  }
  return n;
}

export async function getAllConfig() {
  const rows = await query('SELECT config_key, config_value, description, updated_at FROM app_configuration ORDER BY config_key');
  return rows;
}

export async function setConfig(key, value, adminId, description = null) {
  await query(
    `INSERT INTO app_configuration (config_key, config_value, description, updated_by)
     VALUES (?, ?, ?, ?)
     ON DUPLICATE KEY UPDATE config_value = VALUES(config_value),
       description = COALESCE(VALUES(description), description),
       updated_by = VALUES(updated_by)`,
    [key, String(value), description, adminId]
  );
}
