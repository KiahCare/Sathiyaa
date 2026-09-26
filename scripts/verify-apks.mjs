// Checks that the APKs in this folder were built from the current source.
//
// This exists because of a real mistake: source was edited, only the web build
// was rebuilt, and the APK installed on the phone was the previous one. Nothing
// about a stale APK looks wrong — it opens, it works, it is simply last week's
// app — so the only way to be sure is to look inside it for a string that only
// the current code contains.
//
// One trap worth knowing. A release APK compiles Dart ahead of time and stores
// pure-ASCII strings one byte per character, but any string containing a
// character outside Latin-1 — an em dash, a rupee sign, a curly quote — is
// stored as UTF-16. Searching the file for plain ASCII bytes therefore reports
// "missing" for a string that is sitting right there. This checks both.
//
// Run:  node verify-apks.mjs        (or verify-apks.ps1, which finds node for you)

import { readFileSync, existsSync, statSync, readdirSync } from 'node:fs';
import { inflateRawSync } from 'node:zlib';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));

/// Where the Flutter source lives, for the freshness check.
const SRC = 'C:\\Only Forward\\Sathiyaa\\Sathiyaa Flutter\\Sathiyaa Flutter';

// Strings that should only exist in the current build. Update these when the
// copy changes — a check that never fails is not a check.
const EXPECT = {
  'sathiyaa-customer.apk': [
    'My regular carers',
    'Still needed',
    'Send the code',
    'YOUR CODE — NO SMS IS SENT YET',
    'Healthy range',
    'Sister Grace',
    'Add a second address',
    // The four features added on 19 September. Without a string from each, a
    // stale APK still passes every check above it.
    'Who is this for',            // booking for a dependent
    'Write a message',            // messaging
    'Raising the alert…',         // SOS that actually raises one
    'Kamala Devi',                // the seeded dependent
    // The app no longer opens already signed in. This is the string on the
    // welcome screen's one-tap way into the demo account; if it is missing,
    // the build predates the change and opens straight into somebody's
    // profile.
    'Open the demo account',
    'Booking Journey',            // the stepper on the four booking screens
    // Picking several carers to ask at once. Two strings, because the bar and
    // the waiting screen are the two halves of the feature and a build with
    // only one of them is a build worth catching.
    'Only they will be asked',
    'First to accept takes it',
    // 24 September: the website's teal, the real brand mark, the two-mode
    // carer picker, Nurse and Physiotherapy shown but not bookable, and the
    // language change that offers a restart.
    'Ask several',                // the pick-one / pick-several control
    'Coming soon',                // Nurse and Physiotherapy, greyed
    'Restart the app?',           // the offer after changing language
    'Finding your address…',      // reverse geocoding on "use my location"
    'बुकिंग',                      // Hindi actually shipped, not just wired
    'બુકિંગ',                      // and Gujarati
  ],
  'sathiyaa-provider.apk': [
    'Your carers',
    'This device',
    'Stop allocating work to them',
    'How the team is doing',
    'Take these days off?',
    'Expiring',
    'You are visiting',           // the dependent on the job sheet
    'Write a message',            // messaging
    'Booked by',                  // who paid, when it is not who is visited
    // Same as the customer app: a first run shows the welcome screen, and this
    // is the button that still gets you in without registering.
    'look around with the demo account',
    // The rebuilt document step in registration.
    'Tap to photograph it or pick a file',
    // 24 September: navy on cream, the real brand mark, a registration path
    // that treats an organisation as one, per-day working hours, the approval
    // gate on going on duty, and carer verification.
    'Register your organisation',
    'Different hours on some days',
    'You cannot go on duty yet',
    'Their verification',
    'YOUR CARERS',
    'काम',                         // Hindi actually shipped
    'કામ',                         // and Gujarati
  ],
};

/// The same checks, for the APKs that point at the live server. These are the
/// ones anybody installs; leaving them unchecked meant the only APKs being
/// verified were the two nobody uses.
EXPECT['sathiyaa-customer-cloud.apk'] = EXPECT['sathiyaa-customer.apk'];
EXPECT['sathiyaa-provider-cloud.apk'] = EXPECT['sathiyaa-provider.apk'];

/// Which app each APK is built from, so its freshness can be judged against
/// the source rather than against a list somebody has to remember to update.
const SOURCE_OF = {
  'sathiyaa-customer.apk': 'customer_app',
  'sathiyaa-customer-cloud.apk': 'customer_app',
  'sathiyaa-provider.apk': 'provider_app',
  'sathiyaa-provider-cloud.apk': 'provider_app',
};

const GREEN = '\x1b[32m';
const RED = '\x1b[31m';
const CYAN = '\x1b[36m';
const DIM = '\x1b[2m';
const OFF = '\x1b[0m';

function contains(buf, needle) {
  // Latin-1 rather than ASCII: Dart stores anything up to U+00FF one byte per
  // character, so "₹" is two-byte but "é" would not be.
  const oneByte = Buffer.from(needle, 'latin1');
  const twoByte = Buffer.from(needle, 'utf16le');
  return buf.includes(oneByte) || buf.includes(twoByte);
}

/// Reads the entries of a zip whose names match `wanted`, without writing
/// anything to disk.
///
/// Extracting an APK on Windows is not an option: it collides over names that
/// differ only in case (9n.9.png against 9N.9.png). Shelling out to `unzip` is
/// not either — it is a Git Bash tool and the bundled toolchain has no such
/// thing. So walk the central directory ourselves; it is a short format.
function* zipEntries(buf, wanted) {
  // End of central directory: signature, then scan back over the comment.
  let eocd = -1;
  for (let i = buf.length - 22; i >= 0 && i > buf.length - 66000; i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) return;

  let count = buf.readUInt16LE(eocd + 10);
  let p = buf.readUInt32LE(eocd + 16);

  for (let n = 0; n < count; n++) {
    if (buf.readUInt32LE(p) !== 0x02014b50) return;
    const method = buf.readUInt16LE(p + 10);
    const compressed = buf.readUInt32LE(p + 20);
    const nameLen = buf.readUInt16LE(p + 28);
    const extraLen = buf.readUInt16LE(p + 30);
    const commentLen = buf.readUInt16LE(p + 32);
    const localAt = buf.readUInt32LE(p + 42);
    const name = buf.toString('latin1', p + 46, p + 46 + nameLen);
    p += 46 + nameLen + extraLen + commentLen;

    if (!wanted(name)) continue;

    // The local header repeats the name and carries its own extra field, whose
    // length can differ from the central one — read it, do not assume.
    const lNameLen = buf.readUInt16LE(localAt + 26);
    const lExtraLen = buf.readUInt16LE(localAt + 28);
    const start = localAt + 30 + lNameLen + lExtraLen;
    const raw = buf.subarray(start, start + compressed);

    try {
      yield method === 0 ? raw : inflateRawSync(raw);
    } catch {
      // A corrupt or unexpectedly encoded entry is not worth failing over.
    }
  }
}

/// A LAN server is plain http, so the app needs cleartext traffic allowed or
/// every request fails with a bare "connection closed" and nothing explains
/// why. Release builds rename resources — network_security_config.xml becomes
/// something like res/8G.xml — so look for the setting, not the filename. The
/// entry is deflated, so scanning the APK's own bytes finds nothing.
function hasCleartextConfig(buf) {
  const wanted = (n) => n.startsWith('res/') && n.endsWith('.xml');
  for (const entry of zipEntries(buf, wanted)) {
    // Binary AXML keeps its string pool in UTF-8 or UTF-16 depending on the
    // build tools, so check both.
    if (contains(entry, 'cleartextTrafficPermitted')) return true;
  }
  return false;
}

/// The newest file under a directory, recursively.
///
/// A list of expected strings only catches what somebody remembered to add to
/// it. This catches everything: if any source file is newer than the APK, the
/// APK was not built from it.
function newestUnder(dir) {
  let newest = 0;
  let newestFile = '';
  const walk = (d) => {
    for (const e of readdirSync(d, { withFileTypes: true })) {
      const p = join(d, e.name);
      if (e.isDirectory()) { walk(p); continue; }
      const m = statSync(p).mtimeMs;
      if (m > newest) { newest = m; newestFile = p; }
    }
  };
  if (existsSync(dir)) walk(dir);
  return { at: newest, file: newestFile };
}

/// Whether the APK carries the assets pubspec.yaml declares.
function declaredAssets(appDir) {
  const pubspec = join(appDir, 'pubspec.yaml');
  if (!existsSync(pubspec)) return [];
  return [...readFileSync(pubspec, 'utf8').matchAll(/^\s+-\s+(assets\/\S+)$/gm)].map((m) => m[1]);
}

let failed = 0;

for (const [apk, needles] of Object.entries(EXPECT)) {
  const path = join(here, apk);
  console.log(`\n${CYAN}== ${apk}${OFF}`);

  if (!existsSync(path)) {
    console.log(`   ${RED}MISSING${OFF} — nothing to check`);
    failed++;
    continue;
  }

  const info = statSync(path);
  const mins = Math.round((Date.now() - info.mtimeMs) / 60000);
  console.log(
    `   ${DIM}${(info.size / 1048576).toFixed(0)} MB, built ${info.mtime.toLocaleString()} ` +
      `(${mins} min ago)${OFF}`,
  );

  // Stale by the clock, before a single string is looked at.
  const app = SOURCE_OF[apk];
  if (app) {
    const appDir = join(SRC, app);
    const newest = newestUnder(join(appDir, 'lib'));
    if (newest.at > info.mtimeMs) {
      const behind = Math.round((newest.at - info.mtimeMs) / 60000);
      console.log(
        `   ${RED}STALE${OFF}   built ${behind} min before ${newest.file.replace(SRC, '')} was last edited`,
      );
      failed++;
    } else {
      console.log(`   ${GREEN}ok${OFF}      newer than every file in ${app}/lib`);
    }
  }

  const buf = readFileSync(path);

  // Declared assets have to be inside. A build that dropped the brand mark
  // would otherwise pass every string check in this file.
  if (app) {
    for (const asset of declaredAssets(join(SRC, app))) {
      const wanted = (n) => n === `assets/flutter_assets/${asset}`;
      let found = false;
      for (const _ of zipEntries(buf, wanted)) { found = true; break; }
      if (found) {
        console.log(`   ${GREEN}ok${OFF}      ${asset}`);
      } else {
        console.log(`   ${RED}MISSING${OFF} ${asset} — declared in pubspec.yaml, not in the APK`);
        failed++;
      }
    }
  }

  for (const needle of needles) {
    if (contains(buf, needle)) {
      console.log(`   ${GREEN}ok${OFF}      ${needle}`);
    } else {
      console.log(`   ${RED}STALE${OFF}   ${needle}`);
      failed++;
    }
  }

  const cleartext = hasCleartextConfig(buf);
  if (cleartext) {
    console.log(`   ${GREEN}ok${OFF}      cleartext traffic allowed`);
  } else {
    console.log(`   ${RED}MISSING${OFF} cleartext config — phones cannot reach a LAN server`);
    failed++;
  }
}

console.log('');
if (failed === 0) {
  console.log(`${GREEN}All ${Object.keys(EXPECT).length} APKs are current.${OFF}`);
} else {
  console.log(`${RED}${failed} check(s) failed — rebuild with rebuild-apks.ps1${OFF}`);
  process.exit(1);
}
