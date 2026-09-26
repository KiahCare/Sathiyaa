/**
 * Repairs `*_url` columns that hold something a browser cannot load.
 *
 * Two kinds of damage, from two fixed bugs:
 *
 *   1. An absolute URL built from the request's Host header. Behind CloudFront
 *      that resolved to the origin instance over plain http with no port --
 *      `http://ec2-x-x-x-x.ap-south-1.compute.amazonaws.com/uploads/photo/a.jpg`.
 *      The FILE IS FINE; only the address is wrong, so this rewrites it to the
 *      relative `/uploads/...` that every client now resolves for itself.
 *
 *   2. A path from inside an Android app's sandbox --
 *      `/data/user/0/in.sathiyaa.provider/cache/scaled_1234.jpg`. The upload
 *      was skipped, so no file was ever stored anywhere. Nothing can recover
 *      it; the column is set to NULL so the console shows "not uploaded"
 *      instead of a link to nothing, and the provider can be asked again.
 *
 * Run from the backend folder so it reads the same .env the server does:
 *   node scripts/repair-upload-urls.mjs           # report only
 *   node scripts/repair-upload-urls.mjs --apply   # make the changes
 */
import { query } from '../src/db/pool.js';

const APPLY = process.argv.includes('--apply');

const COLUMNS = [
  ['customers', 'customer_id', 'photo_url'],
  ['service_providers', 'provider_id', 'photo_url'],
  ['service_providers', 'provider_id', 'aadhar_doc_url'],
  ['service_providers', 'provider_id', 'police_verification_url'],
  ['service_providers', 'provider_id', 'work_certificate_url'],
  ['service_providers', 'provider_id', 'medical_certificate_url'],
];

const isServerRef = (v) =>
  v.startsWith('data:') || v.startsWith('/uploads/') ||
  (/^https?:\/\//.test(v) && v.includes('/uploads/'));

let rewrites = 0;
let clears = 0;

for (const [table, pk, col] of COLUMNS) {
  let rows;
  try {
    rows = await query(
      `SELECT ${pk} AS id, ${col} AS v FROM ${table} WHERE ${col} IS NOT NULL AND ${col} <> ''`
    );
  } catch (e) {
    if (e.code === 'ER_BAD_FIELD_ERROR') { console.log(`skip  ${table}.${col} (no such column)`); continue; }
    throw e;
  }

  for (const { id, v } of rows) {
    if (v.startsWith('data:') || v.startsWith('/uploads/')) continue; // already fine

    // An absolute URL that still contains /uploads/: keep the file, drop the host.
    const m = /^https?:\/\/[^/]+(\/uploads\/.*)$/.exec(v);
    if (m) {
      rewrites += 1;
      console.log(`fix   ${table}#${id}.${col}`);
      console.log(`        ${v}`);
      console.log(`     -> ${m[1]}`);
      if (APPLY) await query(`UPDATE ${table} SET ${col} = ? WHERE ${pk} = ?`, [m[1], id]);
      continue;
    }

    if (isServerRef(v)) continue;

    clears += 1;
    console.log(`clear ${table}#${id}.${col}`);
    console.log(`        ${v}`);
    console.log(`     -> NULL  (the file was never uploaded; ask for it again)`);
    if (APPLY) await query(`UPDATE ${table} SET ${col} = NULL WHERE ${pk} = ?`, [id]);
  }
}

console.log(`\n${rewrites} address(es) to rewrite, ${clears} column(s) to clear.`);
console.log(APPLY ? 'Applied.' : 'Nothing changed. Re-run with --apply to make these changes.');
process.exit(0);
