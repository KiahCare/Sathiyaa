#!/usr/bin/env node
//
// Sets an admin account's password.
//
// This exists because there was no way to change it. The super-admin password
// is baked into the seed, printed on every seed run, and written down in the
// repository — and no endpoint in the API could change it afterwards. Before
// this server faces the internet that password has to be rotated, and rotating
// it meant hand-writing a bcrypt hash into MySQL.
//
// Usage:
//   node scripts/set-admin-password.mjs admin@sathiyaa.com "a long new password"
//
// Or, so the password never reaches your shell history:
//   ADMIN_EMAIL=admin@sathiyaa.com ADMIN_PASSWORD='...' node scripts/set-admin-password.mjs
//
// Run it on the machine the database is on, or anywhere the backend's .env
// points at the right database.

import bcrypt from 'bcryptjs';

import { pool, query } from '../src/db/pool.js';

const email = process.argv[2] || process.env.ADMIN_EMAIL;
const password = process.argv[3] || process.env.ADMIN_PASSWORD;

function bail(message) {
  console.error(`\n  ${message}\n`);
  process.exit(1);
}

if (!email || !password) {
  bail('Usage: node scripts/set-admin-password.mjs <email> <new password>');
}

// Long beats clever. Three unrelated words are stronger than "P@ssw0rd!" and
// far easier to type on a phone at somebody's door.
if (password.length < 12) {
  bail(`That password is ${password.length} characters. Use at least 12 — a short phrase is fine.`);
}

const WEAK = new Set(['admin@123', 'password', 'sathiyaa123', 'admin1234']);
if (WEAK.has(password.toLowerCase())) {
  bail('That is one of the passwords an attacker tries first. Pick another.');
}

try {
  const [admin] = await query('SELECT admin_id, name FROM admin_users WHERE email = ?', [email]);
  if (!admin) bail(`No admin account with the email ${email}.`);

  const hash = await bcrypt.hash(password, 12);
  await query('UPDATE admin_users SET password_hash = ? WHERE admin_id = ?', [hash, admin.admin_id]);

  console.log(`\n  Password updated for ${admin.name} <${email}>.`);
  console.log('  Existing sign-in tokens stay valid until they expire (JWT_EXPIRES_IN).');
  console.log('  To cut them off now, change JWT_SECRET and restart the API.\n');
} catch (err) {
  bail(`Could not update the password: ${err.message}`);
} finally {
  await pool.end();
}
