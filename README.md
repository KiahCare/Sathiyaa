# Sathiyaa

Home-healthcare and senior-care booking for India. A family searches for a
carer near them, books a visit, and can see where that carer is on the way;
the carer runs their day from their own app; an agency manages the carers it
employs; and an administrator approves providers, signs new ones up, sets
prices and watches the money.

Launching in Ahmedabad and Gandhinagar, Gujarat. Accounts are accepted from
anywhere and the app then checks where the person actually is — a sign-up
outside the service area is kept and told plainly that we are not there yet,
rather than silently failing to find anybody.

## What is in here

| Folder | Stack | What it is |
|---|---|---|
| `apps/customer_app/` | Flutter / Dart | The family's app. Search, book, pay, track, message, SOS. |
| `apps/provider_app/` | Flutter / Dart | The carer's and the agency's app. One binary, two shapes: a freelance carer sees their own day, an organisation sees its people. |
| `backend/` | Node.js 20+, Express 4, MySQL 8 | The API both apps and the console talk to. 145 endpoints, 39 tables, 17 ordered migrations. |
| `admin-portal/` | React 19, TypeScript, Vite | Two portals in one app, separated by role: Sathiyaa's own administrators, and business partners who see only their own referrals and revenue. |
| `docs/` | — | The architecture, the API contract, the schema, the ERD, the test plans, and the AWS deployment runbook. |
| `tests/` | Node | 29 integration scripts that drive the real API over HTTP. |
| `scripts/` | PowerShell, Node | Build, packaging, deployment and maintenance tooling. |

Three languages throughout: English, Hindi and Gujarati, including the apps'
own screens.

**Start here:** [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) explains how a
booking actually travels through the system, which is the shape everything else
is built around. [`docs/ARCHITECTURE-APPS.md`](docs/ARCHITECTURE-APPS.md) does
the same for the two Flutter apps.

Then [`CONTRIBUTING.md`](CONTRIBUTING.md) — how changes are made here is not
obvious, and getting it wrong looks like it worked.

## Versions

Four things ship from this repository, versioned independently:

| Component | Version | Readable at run time |
|---|---|---|
| Backend API | 1.1.0 | `GET /health` |
| Admin console | 1.1.0 | sidebar footer |
| Customer app | 1.1.0+2 | Server screen |
| Provider app | 1.1.0+2 | Server screen |

Each comes from its own manifest, so no copy can go stale.
[`CHANGELOG.md`](CHANGELOG.md) records every change, however small.

## Running it

Needs MySQL 8, Node 20 or newer, and Flutter 3.19 or newer (Dart SDK
`>=3.3.0`).

```bash
# 1. Database
mysql -u root -e "CREATE DATABASE sathiyaa CHARACTER SET utf8mb4"

# 2. Backend
cd backend
npm ci
cp .env.example .env          # then set DB_PASSWORD and a real JWT_SECRET
npm run migrate               # applies src/db/migrations in order
npm run seed                  # a demo roster, prices and an admin account
npm run dev                   # http://localhost:4000

# 3. Admin console
cd ../admin-portal
npm ci
npm run dev                   # http://localhost:5173
```

The console starts in mock mode, which needs no server at all — set
`VITE_USE_MOCK=false` in `.env` to point it at the backend.

```bash
# 4. Either app
cd ../apps/customer_app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:4000/api/v1
```

Both apps also run with no backend: they fall back to an in-memory
`MockBackend` with a full demo dataset, so every screen is reachable. What
decides it is whether an API address was compiled in — see
`lib/backend.dart`. `10.0.2.2` is how the Android emulator reaches the host
machine; a physical phone needs the machine's LAN address, and there is a
screen in both apps for typing one in.

The server refuses to start on a placeholder `JWT_SECRET`, on one under 32
characters, or on none at all, when `PUBLIC_DEPLOYMENT` is on. That check is
`backend/src/config/preflight.js`, and it is deliberately fatal rather than a
warning: a forgeable token is the whole game, since anyone can sign their own
with `role: "admin"`.

## Testing

```bash
flutter test                                  # in either app folder
node tests/happy-path.mjs --api http://localhost:4000/api/v1
```

`tests/run-all.ps1` builds a throwaway database from the migrations, starts a
server on a spare port, runs every suite against it and drops the database
afterwards. `-Flutter` adds both app suites. `-Api`/`-Key` point the same
suites at a deployed server instead, and `-Only <name>` runs one.

The suites are not unit tests. Each drives the real API over HTTP and checks a
behaviour somebody can describe in a sentence — "an organisation registers as
an organisation", "a second handset is refused", "the console can create a
carer who can then sign in". Several exist because the behaviour was once
wrong in production, and the comment at the top of the file says which.

As of 2 October 2026: all 29 integration suites pass, `flutter analyze` is
clean on both apps, `tsc -b` is silent on the console, and the
`admin-create-provider` suite has been run against the live deployment as well
as locally.

## A split into two repositories is coming

The Flutter apps and the platform ship on completely different clocks — an APK
goes through store review and a user may be versions behind for a month, while
the API and the console go out together in an afternoon. So this will become
`sathiyaa-apps` (both apps) and `sathiyaa-platform` (API, console, tests,
deployment).

Both are prepared and staged locally, waiting on the repositories being created
on GitHub. **Until then this repository is the live one.** See
[`CONTRIBUTING.md`](CONTRIBUTING.md); the move changes no code.

## What is real and what is not

Worth reading before assuming a number on a screen means money moved.

**Real.** Everything else. Provider matching by distance, availability,
service type and language. Bookings, cancellation policy, session billing,
revenue splits, the Time Bank, the referral chain as far as it goes, live
location tracking, in-app messaging, SOS, broadcasts, device registry, audit
log, uploads, the console's configuration, reports and provider sign-up.

**Simulated, behind a deliberate seam.** Payments, SMS and OTP delivery,
face matching and push notification each sit behind one interface with a
working stub and at least one real implementation beside it, chosen by
environment variable — `backend/src/integrations/`. A development OTP is
returned in the API response so a phone is not needed; see
[`SECURITY.md`](SECURITY.md) for what that means and when it stops. No payment
gateway is connected; the app says so on the screen where a card would be
charged.

**Written but not switched on.** AWS Rekognition face matching
(`docs/AWS-REKOGNITION.md`) needs an IAM key pair before it does anything.

**Not built.** Renewal reminders, proration, and any consequence for an
account past its renewal date — a year-old account keeps working and is simply
able to pay again. iOS: the Flutter code is portable but there is no `ios/`
folder and it has never been built or tested on an iPhone.

## Security

[`SECURITY.md`](SECURITY.md) lists what protects this system and **eight
deliberate gaps**, each with why it is there and what closes it. Two of them
are load-bearing for being able to sign in at all today, so none of them should
be "tidied up" without reading why first.

The one to act on: uploaded identity documents are served without
authentication, protected only by an unguessable filename. That should be moved
to pre-signed URLs before the first real customer's documents are stored, and
the seam for it already exists.

## Notes for a reviewer

Comments in this codebase tend to explain *why*, and several record a bug and
the reasoning that fixed it. They are worth more than the code around them in
a few places — `backend/src/services/providerMatching.js`,
`backend/src/services/serviceArea.js`,
`backend/src/services/providerAccounts.js` and
`backend/src/controllers/uploadController.js` in particular.

Three structural things you may otherwise wonder about:

- **Translations are keyed by their English sentence**, not by an identifier.
  Reword the English and the translation silently orphans, so a test walks
  `lib/` and fails on any key no longer present in the source.
- **The two apps share several files verbatim** — theme, widgets, i18n
  plumbing, the service-area gate. `scripts/sync-design.ps1` copies them one
  way, customer to provider, comparing hashes so unchanged files keep their
  timestamps. The palette and the string tables are deliberately excluded,
  because the two apps differ there on purpose.
- **Three callers create a provider** — the app's own registration, an agency
  adding a carer, and the console creating one in the office. They share one
  INSERT, in `services/providerAccounts.js`, because when they did not they
  drifted: one wrote the police-verification dates and the others did not, and
  an organisation with no working-hours rows was invisible to every search
  while the console showed it as approved.

## Licence

None yet — all rights reserved. Do not redistribute without asking.
