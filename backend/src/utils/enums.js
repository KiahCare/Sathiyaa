import { Errors } from './apiError.js';

/**
 * Values the database columns accept, checked before they reach MySQL.
 *
 * A value outside an ENUM does not fail politely: MySQL rejects the whole
 * statement with "Data truncated for column ...", which arrives at the app as
 * a 500 and "Something went wrong". That is what happened when the provider
 * registration screen offered "N/A" as a gender -- the column only knows
 * male/female/other, so nobody choosing it could register, and nothing on
 * screen said which field was at fault.
 *
 * Checking here turns that into a sentence naming the field and the values it
 * will take.
 */
const GENDERS = new Set(['male', 'female', 'other']);
const CONTACT_MODES = new Set(['email', 'call', 'sms']);

/**
 * @param {unknown} value
 * @param {{required?: boolean, field?: string}} [opts]
 * @returns {string|null} the lower-cased value, or null when absent and optional
 */
export function normaliseGender(value, { required = false, field = 'gender' } = {}) {
  if (value === undefined || value === null || value === '') {
    if (required) throw Errors.badRequest('VALIDATION', `${field} is required`);
    return null;
  }
  const g = String(value).trim().toLowerCase();
  if (!GENDERS.has(g)) {
    throw Errors.unprocessable(
      'INVALID_GENDER',
      `${field} must be one of: ${[...GENDERS].join(', ')}. Got "${value}".`
    );
  }
  return g;
}

/**
 * Preferred contact modes, as the comma-joined form the SET column stores.
 * Any combination is valid; an empty selection clears the column.
 */
export function normaliseContactModes(value, { field = 'preferredCommMode' } = {}) {
  if (value === undefined) return undefined;
  if (value === null || value === '') return '';
  const parts = String(value)
    .split(',')
    .map((m) => m.trim().toLowerCase())
    .filter(Boolean);
  const bad = parts.filter((m) => !CONTACT_MODES.has(m));
  if (bad.length) {
    throw Errors.unprocessable(
      'INVALID_CONTACT_MODE',
      `${field} must be any of: ${[...CONTACT_MODES].join(', ')}. Not recognised: ${bad.join(', ')}.`
    );
  }
  return [...new Set(parts)].join(',');
}
