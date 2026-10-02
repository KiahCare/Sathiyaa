/**
 * Copy the publishable part of this project into the repositories under
 * `_repos\`, and refuse to copy anything that must not be published.
 *
 * WHY THIS EXISTS RATHER THAN `git init` AT THE PROJECT ROOT
 *
 * The working tree holds things that must never reach GitHub, and they are not
 * all obvious: a folder of AWS access keys, a `.env` with the live database
 * password, hundreds of uploaded documents, four APKs -- two of which have the
 * live API access key compiled into them -- and a built admin console whose
 * JavaScript bundle contains that same key in clear text. A `.gitignore` is one
 * edit away from letting any of those through, and once a secret is in a commit
 * it is in the history for good.
 *
 * So each repository is a separate folder that nothing but this script writes
 * to, and this script works from an allowlist: a file is copied because a rule
 * names it, never because nothing excluded it. Then every copied file is
 * scanned for the actual live secret values -- read at run time from
 * `AWS\ec2.env`, never hardcoded here -- and the sync aborts on a hit before
 * anything is staged, let alone pushed.
 *
 * It also reports what changed, file by file, so a commit message can say what
 * a commit actually did.
 *
 * THREE TARGETS, AND WHICH ONE IS LIVE
 *
 *   monorepo           _github\  -- KiahCare/Sathiyaa, everything in one tree.
 *                      THIS IS THE LIVE ONE, and the default.
 *   apps               the two Flutter apps, staged for a split
 *   platform           the API, console, tests and deployment, staged likewise
 *
 * The split exists because the two halves ship on completely different clocks:
 * an APK goes through store review and a user may be versions behind for a
 * month, while the API and the console go out together in an afternoon. Holding
 * both on one history means releasing either one drags the other along, and
 * "what changed in the provider app this month" has to be answered by reading
 * past everything else.
 *
 * It is not done yet -- the two repositories do not exist on GitHub, because
 * creating them under the KiahCare organisation needs rights we do not have. So
 * the monorepo is what is kept current and what this script writes by default.
 * `--only=apps` and `--only=platform` write the staged copies, and `--all`
 * writes all three. When the repositories appear, the default flips and the
 * monorepo target is deleted from this file.
 *
 * The console stays with the backend in that split, deliberately. It talks to
 * exactly one API, is deployed with it, and shares its version number, so a
 * change that spans both is one commit and one review rather than two that have
 * to be landed in the right order.
 *
 * USAGE
 *
 *   node sync-to-github.mjs                 sync the live monorepo, then report
 *   node sync-to-github.mjs --all           that plus both staged repositories
 *   node sync-to-github.mjs --only=apps     one of them (monorepo|apps|platform)
 *   node sync-to-github.mjs --dry-run       report what would change, write nothing
 *
 * The layout it produces is deliberately not the layout on this laptop. Here
 * the Flutter apps live under `Sathiyaa Flutter\Sathiyaa Flutter\` and the
 * backend under `sathiyaa-full-project - Flutter Web version\` -- names that
 * describe the history of the project rather than its contents, and that a
 * reviewer would have to decode.
 */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const ROOT = path.resolve(import.meta.dirname, '..');
const REPOS_DIR = path.join(ROOT, '_repos');
const DRY = process.argv.includes('--dry-run');
const ALL = process.argv.includes('--all');
const ONLY = (process.argv.find((a) => a.startsWith('--only=')) || '').split('=')[1] || null;

const FLUTTER = path.join(ROOT, 'Sathiyaa Flutter', 'Sathiyaa Flutter');
const WEB = path.join(ROOT, 'sathiyaa-full-project - Flutter Web version');

// --------------------------------------------------------------- the repos
//
// `dir` is where the working copy lives; it is also what the GitHub repository
// is named, so the two never have to be mapped onto each other in somebody's
// head.
const REPOS = {
  monorepo: {
    dir: path.join(ROOT, '_github'),
    what: 'KiahCare/Sathiyaa -- everything, and the one that is live',
  },
  apps: {
    dir: path.join(REPOS_DIR, 'sathiyaa-apps'),
    what: 'Flutter customer and provider apps (staged for the split)',
  },
  platform: {
    dir: path.join(REPOS_DIR, 'sathiyaa-platform'),
    what: 'API, admin console, integration suite and deployment (staged)',
  },
};

/** What a bare invocation writes. The live repository, and nothing else. */
const DEFAULT_TARGETS = ['monorepo'];

// ---------------------------------------------------------------- the rules
//
// `repo` names which repository the rule writes into. `from` is relative to the
// project root, `to` to that repository's root. `only` is an allowlist of
// top-level entries to walk; when absent the whole folder is walked. `skip` is
// matched against the path relative to `from`, with forward slashes, and is
// applied to directories as well as files, so excluding `build` prunes the walk
// rather than filtering 30,000 results.
const FLUTTER_ONLY = ['lib', 'test', 'assets', 'web', 'android', 'pubspec.yaml',
  'pubspec.lock', 'analysis_options.yaml', '.gitignore'];
const FLUTTER_SKIP = [/^build($|\/)/, /^\.dart_tool($|\/)/, /^\.idea($|\/)/, /\.iml$/,
  /^android\/local\.properties$/, /^android\/\.gradle($|\/)/,
  /^android\/gradlew(\.bat)?$/, /^\.packages$/, /\.flutter-plugins/];

const RULES = [
  // ---- sathiyaa-apps ----------------------------------------------------
  {
    repo: 'apps',
    what: 'customer app (Flutter)',
    from: path.relative(ROOT, path.join(FLUTTER, 'customer_app')),
    to: 'apps/customer_app',
    only: FLUTTER_ONLY,
    skip: FLUTTER_SKIP,
  },
  {
    repo: 'apps',
    what: 'provider app (Flutter)',
    from: path.relative(ROOT, path.join(FLUTTER, 'provider_app')),
    to: 'apps/provider_app',
    only: FLUTTER_ONLY,
    skip: FLUTTER_SKIP,
  },
  {
    repo: 'apps',
    what: 'app build scripts',
    from: '_builds',
    to: 'scripts',
    only: ['rebuild-apks.ps1', 'rebuild-apks.cmd', 'sync-design.ps1',
      'verify-apks.mjs', 'verify-apks.ps1', 'start-web-apps.ps1',
      'phone-connection-info.ps1', 'phone-connection-info.cmd', 'static-server.mjs'],
    skip: [],
  },
  {
    repo: 'apps',
    what: 'app documentation',
    from: '_builds',
    to: 'docs',
    only: ['TESTING-ON-PHONES.md'],
    skip: [],
  },
  {
    repo: 'apps',
    what: 'authored documentation',
    from: '_docs/apps',
    to: '.',
    only: null,
    skip: [],
  },

  // ---- sathiyaa-platform -------------------------------------------------
  {
    repo: 'platform',
    what: 'backend API (Node/Express/MySQL)',
    from: path.relative(ROOT, path.join(WEB, 'backend')),
    to: 'backend',
    only: ['src', 'scripts', 'package.json', 'package-lock.json',
      '.env.example', 'README.md', '.gitignore'],
    // `.env` holds the live database password. `uploads/` is hundreds of files
    // of documents people uploaded. Neither is a judgement call.
    skip: [/^node_modules($|\/)/, /^\.env$/, /^uploads($|\/)/],
  },
  {
    repo: 'platform',
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
    repo: 'platform',
    what: 'specification and schema',
    from: path.relative(ROOT, path.join(WEB, 'docs')),
    to: 'docs',
    only: ['api-contract.md', 'schema.sql', 'coverage-matrix.md', 'erd.mmd',
      'erd.png', 'erd.html', 'sql-update-delete-queries.md',
      'AWS-REKOGNITION.md', 'Sathiyaa MVP Requirements.docx',
      // How to switch each integration on. No keys, no account numbers --
      // these are the steps, which are the same for anybody. The one file that
      // does name our own instances and buckets is
      // AWS\NEW-ACCOUNT-AND-MIGRATION.md, and the whole AWS folder is outside
      // every rule here.
      'setup',
      'client-feedback-2026-09-29.md'],
    skip: [],
  },
  {
    repo: 'platform',
    what: 'integration test suite',
    from: '_tests',
    to: 'tests',
    only: null,
    skip: [],
  },
  {
    repo: 'platform',
    what: 'build and deployment scripts',
    from: '_builds',
    to: 'scripts',
    only: ['build-for-cloud.ps1', 'package-for-ec2.ps1', 'ec2-setup.sh',
      'make-deploy-secrets.ps1', 'start-backend.ps1', 'start-everything.ps1',
      'start-everything.cmd', 'stop-everything.ps1', 'stop-everything.cmd',
      'static-server.mjs', 'sync-to-github.mjs', 'sync-to-github.ps1'],
    // redeploy.ps1 and DEPLOY-AWS.md carry the CloudFront distribution id, the
    // S3 bucket name and the instance's hostname. Those stay on the laptop.
    skip: [],
  },
  {
    repo: 'platform',
    what: 'test plans, audits and the deployment runbook',
    from: '_builds',
    to: 'docs',
    only: ['AUDIT.md', 'WHAT-TO-TEST.md', 'THE-PRACTICAL.md', 'DEPLOY-AWS.md'],
    skip: [],
  },
  {
    repo: 'platform',
    what: 'authored documentation',
    from: '_docs/platform',
    to: '.',
    only: null,
    skip: [],
  },

  // ---- monorepo (the live one) -------------------------------------------
  //
  // The same sources, in the layout KiahCare/Sathiyaa already has, so the split
  // is a move rather than a rewrite. Everything below reuses the `from` paths
  // and allowlists above; only `to` differs, and the scripts and docs folders
  // take the union of both halves rather than being divided between them.
  {
    repo: 'monorepo',
    what: 'customer app (Flutter)',
    from: path.relative(ROOT, path.join(FLUTTER, 'customer_app')),
    to: 'apps/customer_app',
    only: FLUTTER_ONLY,
    skip: FLUTTER_SKIP,
  },
  {
    repo: 'monorepo',
    what: 'provider app (Flutter)',
    from: path.relative(ROOT, path.join(FLUTTER, 'provider_app')),
    to: 'apps/provider_app',
    only: FLUTTER_ONLY,
    skip: FLUTTER_SKIP,
  },
  {
    repo: 'monorepo',
    what: 'backend API (Node/Express/MySQL)',
    from: path.relative(ROOT, path.join(WEB, 'backend')),
    to: 'backend',
    only: ['src', 'scripts', 'package.json', 'package-lock.json',
      '.env.example', 'README.md', '.gitignore'],
    skip: [/^node_modules($|\/)/, /^\.env$/, /^uploads($|\/)/],
  },
  {
    repo: 'monorepo',
    what: 'admin console (React + TypeScript)',
    from: path.relative(ROOT, path.join(WEB, 'admin-portal')),
    to: 'admin-portal',
    only: ['src', 'public', 'index.html', 'package.json', 'package-lock.json',
      'tsconfig.json', 'tsconfig.app.json', 'tsconfig.node.json',
      'vite.config.ts', '.oxlintrc.json', '.env.example', 'README.md',
      'build-single-file.mjs', '.gitignore'],
    skip: [/^node_modules($|\/)/, /^dist($|\/)/, /^dist-cloud($|\/)/,
      /^dist-demo($|\/)/, /^dist-live($|\/)/],
  },
  {
    repo: 'monorepo',
    what: 'specification and schema',
    from: path.relative(ROOT, path.join(WEB, 'docs')),
    to: 'docs',
    only: ['api-contract.md', 'schema.sql', 'coverage-matrix.md', 'erd.mmd',
      'erd.png', 'erd.html', 'sql-update-delete-queries.md',
      'AWS-REKOGNITION.md', 'Sathiyaa MVP Requirements.docx',
      'setup', 'client-feedback-2026-09-29.md'],
    skip: [],
  },
  {
    repo: 'monorepo',
    what: 'integration test suite',
    from: '_tests',
    to: 'tests',
    only: null,
    skip: [],
  },
  {
    repo: 'monorepo',
    what: 'build, deployment and app scripts',
    from: '_builds',
    to: 'scripts',
    only: ['build-for-cloud.ps1', 'rebuild-apks.ps1', 'rebuild-apks.cmd',
      'sync-design.ps1', 'sync-to-build.ps1', 'verify-apks.mjs',
      'verify-apks.ps1', 'package-for-ec2.ps1', 'ec2-setup.sh',
      'make-deploy-secrets.ps1', 'start-backend.ps1', 'start-everything.ps1',
      'start-everything.cmd', 'start-web-apps.ps1', 'stop-everything.ps1',
      'stop-everything.cmd', 'static-server.mjs', 'phone-connection-info.ps1',
      'phone-connection-info.cmd', 'sync-to-github.mjs', 'sync-to-github.ps1'],
    skip: [],
  },
  {
    repo: 'monorepo',
    what: 'test plans, audits and the deployment runbook',
    from: '_builds',
    to: 'docs',
    only: ['AUDIT.md', 'WHAT-TO-TEST.md', 'THE-PRACTICAL.md',
      'TESTING-ON-PHONES.md', 'DEPLOY-AWS.md'],
    skip: [],
  },
  {
    repo: 'monorepo',
    what: 'authored documentation',
    from: '_docs/monorepo',
    to: '.',
    only: null,
    skip: [],
  },
  // SECURITY.md and the two architecture docs are not rewritten for this
  // layout, they are the same files the split repositories use -- one copy, so
  // the two layouts cannot drift while both exist. Only the apps architecture
  // needs a different name here, because in a single tree two files both called
  // ARCHITECTURE.md would be one file.
  {
    repo: 'monorepo',
    what: 'security notes',
    from: '_docs/platform',
    to: '.',
    only: ['SECURITY.md'],
    skip: [],
  },
  {
    repo: 'monorepo',
    what: 'platform architecture',
    from: '_docs/platform/docs',
    to: 'docs',
    only: ['ARCHITECTURE.md'],
    skip: [],
  },
  {
    repo: 'monorepo',
    what: 'apps architecture',
    from: '_docs/apps/docs',
    to: 'docs',
    only: ['ARCHITECTURE.md'],
    rename: { 'ARCHITECTURE.md': 'ARCHITECTURE-APPS.md' },
    skip: [],
  },
];

// Files written by hand inside a repository, which no rule may clobber and
// which the sync must not delete.
//
// This list is deliberately short. Everything a human writes -- READMEs,
// CHANGELOG, CONTRIBUTING, SECURITY -- lives under `_docs\` on the laptop and
// is copied in by the rules above, so there is exactly one copy of each and the
// rule in the project's own documentation ("edit the local copy, then sync")
// has no exceptions to remember. What is left here is the two files git itself
// reads, which are per-repository and have no meaning outside one.
//
// Leaving `.gitattributes` off this list once cost a round: the sync saw a file
// in the repository that no rule claimed, decided it was no longer part of the
// project, and deleted it.
const AUTHORED = ['.gitignore', '.gitattributes', 'LICENSE'];

// --------------------------------------------------------------- the walker
function walk(absDir, rel, skip, out) {
  for (const e of fs.readdirSync(absDir, { withFileTypes: true })) {
    const childRel = rel ? `${rel}/${e.name}` : e.name;
    if (skip.some((re) => re.test(childRel))) continue;
    const abs = path.join(absDir, e.name);
    if (e.isDirectory()) {
      // Never walk into another repository. A clone sitting inside this one is
      // not part of it, and the `removed` pass deletes everything it finds that
      // no rule claims -- which for a nested clone means the checkout and its
      // .git with it.
      if (fs.existsSync(path.join(abs, '.git'))) continue;
      walk(abs, childRel, skip, out);
    } else if (e.isFile()) out.push(childRel);
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

if (ONLY && !REPOS[ONLY]) {
  console.error(`--only must name one of: ${Object.keys(REPOS).join(', ')}`);
  process.exit(2);
}
const targets = ONLY ? [ONLY] : (ALL ? Object.keys(REPOS) : DEFAULT_TARGETS);
if (!ONLY && !ALL) {
  console.log(`Writing the live repository only. --all also writes the staged `
    + `${Object.keys(REPOS).filter((k) => k !== 'monorepo').join(' and ')} copies.\n`);
}

// Plan every repository before writing to any of them, so a secret found in the
// second one stops the first from being written too. A half-done sync is the
// one state that is harder to reason about than either end of it.
const plans = new Map(); // repo key -> Map(repo-relative path -> absolute source)
for (const key of targets) plans.set(key, new Map());

console.log('Sources');
for (const rule of RULES) {
  if (!plans.has(rule.repo)) continue;
  const { base, files, missing } = filesFor(rule);
  if (missing) {
    console.log(`  !  ${rule.from} does not exist -- skipped (${rule.what})`);
    continue;
  }
  const planned = plans.get(rule.repo);
  for (const f of files) {
    // A rule may publish a file under a different name. The one use of this is
    // the apps architecture doc, which is docs/ARCHITECTURE.md in its own
    // repository and docs/ARCHITECTURE-APPS.md in the monorepo, where the
    // platform's doc already holds that name.
    const name = rule.rename?.[f] ?? f;
    const dest = rule.to && rule.to !== '.' ? `${rule.to}/${name}` : name;
    if (AUTHORED.includes(dest)) continue; // written by hand, not copied
    planned.set(dest, path.join(base, f));
  }
  console.log(`  ${String(files.length).padStart(4)}  ${rule.repo.padEnd(9)} ${String(rule.to).padEnd(22)} ${rule.what}`);
}

const secrets = liveSecrets();
const totalPlanned = [...plans.values()].reduce((n, m) => n + m.size, 0);
console.log(`\nChecking ${totalPlanned} files against ${secrets.length} live secret values `
  + `and ${SECRET_PATTERNS.length} patterns...`);
const refused = [];
for (const [key, planned] of plans) {
  for (const [dest, src] of planned) {
    const problems = inspect(src, dest, secrets);
    if (problems.length) refused.push({ dest: `${key}/${dest}`, problems });
  }
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

let anyChange = false;
for (const key of targets) {
  const repo = REPOS[key];
  const planned = plans.get(key);

  const existing = new Set();
  if (fs.existsSync(repo.dir)) {
    walk(repo.dir, '', [/^\.git($|\/)/], []).forEach((f) => existing.add(f));
  }
  const authoredPresent = new Set(AUTHORED.filter((a) => existing.has(a)));

  const added = [];
  const changed = [];
  for (const [dest, src] of planned) {
    const destAbs = path.join(repo.dir, dest);
    if (!existing.has(dest)) added.push(dest);
    else if (sha(fs.readFileSync(src)) !== sha(fs.readFileSync(destAbs))) changed.push(dest);
  }
  const removed = [...existing]
    .filter((f) => !planned.has(f) && !authoredPresent.has(f))
    .sort();

  if (!DRY) {
    for (const [dest, src] of planned) {
      const destAbs = path.join(repo.dir, dest);
      // Only write when the bytes differ, so unchanged files keep their
      // timestamps and `git status` stays quiet about them.
      if (existing.has(dest) && sha(fs.readFileSync(src)) === sha(fs.readFileSync(destAbs))) continue;
      fs.mkdirSync(path.dirname(destAbs), { recursive: true });
      fs.copyFileSync(src, destAbs);
    }
    for (const f of removed) fs.rmSync(path.join(repo.dir, f), { force: true });
  }

  const show = (label, list) => {
    if (!list.length) return;
    console.log(`\n  ${label} (${list.length})`);
    list.sort().forEach((f) => console.log(`      ${f}`));
  };

  console.log(`\n${'='.repeat(70)}`);
  console.log(`${DRY ? 'Would sync' : 'Synced'} ${planned.size} files -> ${path.basename(repo.dir)}`);
  console.log(`  ${repo.what}`);
  show('added', added);
  show('changed', changed);
  show('removed (no longer part of the project)', removed);
  if (!added.length && !changed.length && !removed.length) console.log('\n  already current.');
  else anyChange = true;
}

if (!DRY && anyChange) {
  console.log(`\n${'='.repeat(70)}`);
  console.log('Next: review the lists above, then commit each repository in GitHub Desktop.');
  console.log('Record what changed in that repository\'s CHANGELOG.md before you commit.');
}
