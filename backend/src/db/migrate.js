/**
 * Idempotent migration runner. Applies every .sql file in
 * src/db/migrations/ in filename order. Safe to re-run: CREATE TABLE
 * statements that hit an already-exists table are skipped, and DDL
 * uses IF NOT EXISTS where MySQL/MariaDB syntax allows it.
 *
 * Usage: npm run migrate
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import mysql from 'mysql2/promise';
import { env } from '../config/env.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const MIGRATIONS_DIR = path.join(__dirname, 'migrations');

// Re-running must be safe. The runner has no ledger of what it has applied, so
// "already there" has to be indistinguishable from "just did it" — and the way
// MySQL says "already there" depends on what you were adding.
//
// The list below grew because a re-run genuinely broke: migration 009 adds a
// named foreign key, and the second run failed on ER_FK_DUP_NAME rather than
// skipping. On a laptop that is an annoyance. On a deployment where somebody
// runs `npm run migrate` twice to be sure, it is a failed deploy.
const ALREADY_EXISTS_CODES = new Set([
  'ER_TABLE_EXISTS_ERROR', // 1050 CREATE TABLE
  'ER_DUP_FIELDNAME', // 1060 ADD COLUMN
  'ER_DUP_KEYNAME', // 1061 ADD INDEX / ADD KEY
  'ER_FK_DUP_NAME', // 1826 ADD CONSTRAINT ... FOREIGN KEY
  'ER_DUP_ENTRY', // 1062 an INSERT of seed/reference rows that are already in
  'ER_CANT_CREATE_TABLE', // 1005 in practice: the FK already exists under InnoDB
]);

function splitStatements(sqlText) {
  // Strip full-line SQL comments first so a leading comment block above a
  // statement doesn't cause the whole statement to be mistaken for a
  // comment-only chunk and dropped.
  const withoutComments = sqlText
    .split('\n')
    .filter((line) => !line.trim().startsWith('--'))
    .join('\n');

  return withoutComments
    .split(/;\s*(?:\r?\n|$)/g)
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

async function run() {
  console.log(`[migrate] connecting to ${env.db.host}:${env.db.port}/${env.db.database} as ${env.db.user}`);
  const conn = await mysql.createConnection({
    host: env.db.host,
    port: env.db.port,
    user: env.db.user,
    password: env.db.password,
    ssl: env.db.ssl,
    multipleStatements: false,
  });

  // Create database if it doesn't exist yet, then switch to it.
  await conn.query(`CREATE DATABASE IF NOT EXISTS \`${env.db.database}\` CHARACTER SET utf8mb4`);
  await conn.changeUser({ database: env.db.database });

  const files = fs
    .readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort();

  for (const file of files) {
    const full = path.join(MIGRATIONS_DIR, file);
    const text = fs.readFileSync(full, 'utf8');
    const statements = splitStatements(text);
    console.log(`[migrate] applying ${file} (${statements.length} statements)`);
    for (const stmt of statements) {
      try {
        await conn.query(stmt);
      } catch (err) {
        if (ALREADY_EXISTS_CODES.has(err.code)) {
          // benign on re-run
          continue;
        }
        console.error(`[migrate] FAILED on statement in ${file}:\n${stmt.slice(0, 200)}...`);
        throw err;
      }
    }
  }

  console.log('[migrate] done.');
  await conn.end();
}

run().catch((err) => {
  console.error('[migrate] error:', err);
  process.exit(1);
});
