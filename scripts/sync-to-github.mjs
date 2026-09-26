/**
 * Copy the publishable part of this project into `_github\`, and refuse to
 * copy anything that must not be published.
 *
 * WHY THIS EXISTS RATHER THAN `git init` AT THE PROJECT ROOT
 *
 * The working tree holds things that must never reach GitHub, and they are not
 * all obvious: a folder of AWS access keys, a `.env` with the live database
 * password, 445 uploaded documents, four APKs -- two of which have the live API
 * access key compiled into them -- and a built admin console whose JavaScript
 * bundle contains that same key in clear text. A `.gitignore` is one edit away
 * from letting any of those through, and once a secret is in a commit it is in
 * the history for good.
 *
 * So the repository is a separate folder that nothing but this script writes
 * to, and this script works from an allowlist: a file is copied because a rule
 * names it, never because nothing excluded it. Then every copied file is
 * scanned for the actual live secret values -- read at run time from
 * `AWS\ec2.env`, never hardcoded here -- and the sync aborts on a hit before
 * anything is staged, let alone pushed.
 *
 * It also reports what changed, file by file, so a commit message can say what
 * a commit actually did.
 *
 * USAGE
 *
 *   node sync-to-github.mjs             sync, then report
 *   node sync-to-github.mjs --dry-run   report what would change, write nothing
 *
 * The layout it produces is deliberately not the layout on this laptop. Here
 * the Flutter apps live under `Sathiyaa Flutter\Sathiyaa Flutter\` and the
 * backend under `sathiyaa-full-project - Flutter Web version\` -- names that
 * describe the history of the project rather than its contents, and that a
 * reviewer would have to decode. In the repository they are `apps/` and
 * `backend/`.
 */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const ROOT = path.resolve(import.meta.dirname, '..');
const REPO = path.join(ROOT, '_github');
const DRY = process.argv.includes('--dry-run');

const FLUTTER = path.join(ROOT, 'Sathiyaa Flutter', 'Sathiyaa Flutter');
const WEB = path.join(ROOT, 'sathiyaa-full-project - Flutter Web version');

// ---------------------------------------------------------------- the rules
//
// `from` is relative to the project root, `to` to the repository root.
// `only` is an allowlist of top-level entries to walk; when absent the whole
// folder is walked. `skip` is matched against the path relative to `from`,
// with forward slashes, and is applied to directories as well as files, so
// excluding `build` prunes the walk rather than filtering 30,000 results.
const RULES = [
  {
    what: 'customer app (Flutter)',
    from: path.relative(ROOT, path.join(FLUTTER, 'customer_app')),
    to: 'apps/customer_app',
    only: ['lib', 'test', 'assets', 'web', 'android', 'pubspec.yaml',
           'pubspec.lock', 'analysis_options.yaml', '.gitignore'],
    skip: [/^build($|\/)/, /^\.dart_tool($|\/)/, /^\.idea($|\/)/, /\.iml$/,
           /^android\/local\.properties$/, /^android\/\.gradle($|\/)/,
           /^android\/gradlew(\.bat)?$/, /^\.packages$/, /\.flutter-plugins/],
  },
  {
    what: 'provider app (Flutter)',
    from: path.relative(ROOT, path.join(FLUTTER, 'provider_app')),
    to: 'apps/provider_app',
    only: ['lib', 'test', 'assets', 'web', 'android', 'pubspec.yaml',
           'pubspec.lock', 'analysis_options.yaml', '.gitignore'],
    skip: [/^build($|\/)/, /^\.dart_tool($|\/)/, /^\.idea($|\/)/, /\.iml$/,
           /^android\/local\.properties$/, /^android\/\.gradle($|\/)/,
           /^android\/gradlew(\.bat)?$/, /^\.packages$/, /\.flutter-plugins/],
  },
  {
    what: 'backend API (Node/Express/MySQL)',
    from: path.relative(ROOT, path.join(WEB, 'backend')),
    to: 'backend',
    only: ['src', 'scripts', 'package.json', 'package-lock.json',
           '.env.example', 'README.md', '.gitignore'],
    // `.env` holds the live database password. `uploads/` is 445 files of
    // documents people uploaded. Neither is a judgement call.
    skip: [/^node_modules($|\/)/, /^\.env$/, /^uploads($|\/)/],
  },
  {
    what: 'admin console (React + TypeScript)',
    from: path.relative(ROOT, path.join(WEB, 'admin-portal')),
    to: 'admin-portal',
    only: ['src', 'public', 'index.html', 'package.json', 'package-lock.json',
           'tsconfig.json', 'tsconfig.app.json', 'tsconfig.node.json',
           'vite.config.ts', '.oxlintrc.json', '.env.example', 'README.md',
           'build-single-file.mjs', '.gitignore'],
    // dist-cloud's bundle has the live API access key baked into it by Vite.
    skip: [/^node_modules($|\/)/, /^dist($|\/)/, /^dist-cloud($|\/)/,
           /^dist-demo($|\/)/, /^dist-live($|\/)/],
  },
  {
    what: 'specification and schema',
    from: path.relative(ROOT, path.join(WEB, 'docs')),
    to: 'docs',
    only: ['api-contract.md', 'schema.sql', 'coverage-matrix.md', 'erd.mmd',
           'erd.png', 'erd.html', 'sql-update-delete-queries.md',
           'AWS-REKOGNITION.md', 'Sathiyaa MVP Requirements.docx'],
    skip: [],
  },
  {
    what: 'integration test suite',
    from: '_tests',
    to: 'tests',
    only: null,
    skip: [],
  },
  {
    what: 'build and maintenance scripts',
    from: '_builds',
    to: 'scripts',
    only: ['build-for-cloud.ps1', 'rebuild-apks.ps1', 'rebuild-apks.cmd',
           'sync-design.ps1', 'sync-to-build.ps1', 'verify-apks.mjs',
           'verify-apks.ps1', 'package-for-ec2.ps1', 'ec2-setup.sh',
           'make-deploy-secrets.ps1', 'start-backend.ps1', 'start-everything.ps1',
           'start-everything.cmd', 'start-web-apps.ps1', 'stop-everything.ps1',
           'stop-everything.cmd', 'static-server.mjs', 'phone-connection-info.ps1',
           'phone-connection-info.cmd', 'sync-to-github.mjs', 'sync-to-github.ps1'],
    // redeploy.ps1 and DEPLOY-AWS.md carry the CloudFront distribution id, the
    // S3 bucket name and the instance's hostname. Those stay on the laptop;
    // docs/deployment.md describes the same procedure without them.
    skip: [],
  },
  {
    what: 'server-side maintenance scripts',
    from: 'backend-scripts',
    to: 'scripts/backend',
    only: null,
    skip: [],
  },
  {
    what: 'test plans, audits and the deployment runbook',
    from: '_builds',
    to: 'docs',
    only: ['AUDIT.md', 'WHAT-TO-TEST.md', 'THE-PRACTICAL.md', 'TESTING-ON-PHONES.md',
           'DEPLOY-AWS.md'],
    skip: [],
  },
];

// Files written by hand at the repository root, which no source rule may
// clobber and which `removed` must not offer to delete.
const AUTHORED = ['README.md', '.gitignore'];

// --------------------------------------------------------------- the walker
function walk(absDir, rel, skip, out) {
  for (const e of fs.readdirSync(absDir, { withFileTypes: true })) {
    const childRel = rel ? `${rel}/${e.name}` : e.name;
    if (skip.some((re) => re.test(childRel))) continue;
    const abs = path.join(absDir, e.name);
    if (e.isDirectory()) walk(abs, childRel, skip, out);
    else if (e.isFile()) out.push(childRel);
  }
  return out;
}

function filesFor(rule) {
  const base = path.join(ROOT, rule.from);
  if (!fs.existsSync(base)) return { base, files: [], missing: true };
  const entries = rule.only
    ? rule.only.filter((n) => fs.existsSync(path.join(base, n)))
    : fs.readdirSync(base);
  const files = [];
  for (const name of entries) {
    if (rule.skip.some((re) => re.test(name))) continue;
    const abs = path.join(base, name);
    const st = fs.statSync(abs);
    if (st.isDirectory()) walk(abs, name, rule.skip, files);
    else files.push(name);
  }
  return { base, files, missing: false };
}

// ------------------------------------------------------- the refusal checks
//
// Read the live values at run time so this file never contains one. A short
// value is ignored: `DB_PORT=3306` would match half the source tree.
function liveSecrets() {
  const p = path.join(ROOT, 'AWS', 'ec2.env');
  if (!fs.existsSync(p)) return [];
  const out = [];
  for (const line of fs.readFileSync(p, 'utf8').split(/\r?\n/)) {
    const m = /^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/.exec(line);
    if (!m) continue;
    const [, k, rawV] = m;
    const v = rawV.trim().replace(/^["']|["']$/g, '');
    if (v.length >= 12 && /KEY|PASSWORD|SECRET|TOKEN/.test(k)) out.push({ key: k, value: v });
  }
  return out;
}

const SECRET_PATTERNS = [
  { name: 'AWS access key id', re: /\bA(?:KIA|SIA)[0-9A-Z]{16}\b/ },
  // A real key has a body: the header is followed by a long run of base64.
  // Matching the header alone flagged two comments that document the SHAPE of
  // an FCM service-account key -- `BEGIN PRIVATE KEY-----\nMII...\n-----END` --
  // which is a description of a key, not a key. A check that cries wolf on
  // documentation is a check somebody eventually runs with --force.
  {
    name: 'private key block',
    re: /-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----[\r\n\s]*[A-Za-z0-9+/]{64,}/,
  },
  { name: 'Razorpay live key', re: /\brzp_live_[0-9A-Za-z]{10,}/ },
  { name: 'Stripe live key', re: /\bsk_live_[0-9A-Za-z]{20,}/ },
  { name: 'Google API key', re: /\bAIza[0-9A-Za-z_-]{35}\b/ },
  { name: 'GitHub token', re: /\bgh[pousr]_[0-9A-Za-z]{36,}\b/ },
  { name: 'Slack token', re: /\bxox[baprs]-[0-9A-Za-z-]{10,}/ },
];

const MAX_BYTES = 5 * 1024 * 1024;
const BINARY_OK = /\.(png|jpg|jpeg|svg|ico|pdf|docx|ttf|otf|woff2?|mp4|webp)$/i;

function inspect(abs, rel, secrets) {
  const problems = [];
  const size = fs.statSync(abs).size;
  if (size > MAX_BYTES) {
    problems.push(`${(size / 1048576).toFixed(1)} MB exceeds the ${MAX_BYTES / 1048576} MB limit`);
  }
  if (BINARY_OK.test(rel)) return problems; // not text; nothing to scan for
  let text;
  try {
    text = fs.readFileSync(abs, 'utf8');
  } catch {
    return problems;
  }
  for (const s of secrets) {
    if (text.includes(s.value)) problems.push(`contains the live ${s.key}`);
  }
  for (const p of SECRET_PATTERNS) {
    const m = p.re.exec(text);
    if (m) {
      const line = text.slice(0, m.index).split('\n').length;
      problems.push(`looks like a ${p.name} at line ${line}`);
    }
  }
  return problems;
}

// ------------------------------------------------------------------ the run
const sha = (buf) => crypto.createHash('sha256').update(buf).digest('hex');

const planned = new Map(); // repo-relative path -> absolute source path
const notes = [];

for (const rule of RULES) {
  const { base, files, missing } = filesFor(rule);
  if (missing) {
    notes.push(`  !  ${rule.from} does not exist -- skipped (${rule.what})`);
    continue;
  }
  for (const f of files) {
    const dest = rule.to ? `${rule.to}/${f}` : f;
    if (AUTHORED.includes(dest)) continue; // written by hand, not copied
    planned.set(dest, path.join(base, f));
  }
  notes.push(`  ${String(files.length).padStart(4)}  ${rule.to.padEnd(22)} ${rule.what}`);
}

console.log('Sources');
notes.forEach((n) => console.log(n));

// Refuse before writing anything.
const secrets = liveSecrets();
console.log(`\nChecking ${planned.size} files against ${secrets.length} live secret values `
  + `and ${SECRET_PATTERNS.length} patterns...`);
const refused = [];
for (const [dest, src] of planned) {
  const problems = inspect(src, dest, secrets);
  if (problems.length) refused.push({ dest, problems });
}
if (refused.length) {
  console.error('\nREFUSED -- nothing was copied.\n');
  for (const r of refused) {
    console.error(`  ${r.dest}`);
    r.problems.forEach((p) => console.error(`      ${p}`));
  }
  console.error('\nFix the source, or add an exclusion to RULES if the file does not belong'
    + '\nin the repository at all. Do not weaken the check to get past it.');
  process.exit(1);
}
console.log('  clean.');

// What changed, before touching anything.
const existing = new Set();
if (fs.existsSync(REPO)) {
  const skipGit = [/^\.git($|\/)/];
  walk(REPO, '', skipGit, []).forEach((f) => existing.add(f));
}
const authoredPresent = new Set(AUTHORED.filter((a) => existing.has(a)));

const added = [];
const changed = [];
for (const [dest, src] of planned) {
  const destAbs = path.join(REPO, dest);
  if (!existing.has(dest)) {
    added.push(dest);
  } else if (sha(fs.readFileSync(src)) !== sha(fs.readFileSync(destAbs))) {
    changed.push(dest);
  }
}
const removed = [...existing]
  .filter((f) => !planned.has(f) && !authoredPresent.has(f))
  .sort();

if (!DRY) {
  for (const [dest, src] of planned) {
    const destAbs = path.join(REPO, dest);
    // Only write when the bytes differ, so unchanged files keep their
    // timestamps and `git status` stays quiet about them.
    if (existing.has(dest) && sha(fs.readFileSync(src)) === sha(fs.readFileSync(destAbs))) continue;
    fs.mkdirSync(path.dirname(destAbs), { recursive: true });
    fs.copyFileSync(src, destAbs);
  }
  for (const f of removed) fs.rmSync(path.join(REPO, f), { force: true });
}

const show = (label, list) => {
  if (!list.length) return;
  console.log(`\n${label} (${list.length})`);
  list.sort().forEach((f) => console.log(`    ${f}`));
};

console.log(`\n${DRY ? 'Would sync' : 'Synced'} ${planned.size} files -> ${REPO}`);
show('added', added);
show('changed', changed);
show('removed (no longer part of the project)', removed);
if (!added.length && !changed.length && !removed.length) console.log('\nNothing to do -- already current.');

if (!DRY && (added.length || changed.length || removed.length)) {
  console.log('\nNext: review the list above, then commit in GitHub Desktop.');
}
