# Sathiyaa

Home-healthcare and senior-care booking for India. A family searches for a
carer near them, books a visit, and can see where that carer is on the way;
the carer runs their day from their own app; an agency manages the carers it
employs; and an administrator approves providers, sets prices and watches the
money.

Launching in Ahmedabad, Gujarat. Accounts are accepted from anywhere and the
app then checks where the person actually is — a sign-up outside the service
area is kept and told plainly that we are not there yet, rather than silently
failing to find anybody.

## What is in here

| Folder | Stack | What it is |
|---|---|---|
| `apps/customer_app/` | Flutter / Dart | The family's app. Search, book, pay, track, message, SOS. |
| `apps/provider_app/` | Flutter / Dart | The carer's and the agency's app. One binary, two shapes: a freelance carer sees their own day, an organisation sees its people. |
| `backend/` | Node.js, Express, MySQL 8 | The API both apps and the console talk to. 143 endpoints, 36 tables, 15 ordered migrations. |
| `admin-portal/` | React 19, TypeScript, Vite | Two portals in one app, separated by role: Sathiyaa's own administrators, and business partners who see only their own referrals and revenue. |
| `docs/` | — | The API contract, the schema, the ERD, the test plans, and the AWS deployment runbook. |
| `tests/` | Node | 28 integration scripts that drive the real API over HTTP. |
| `scripts/` | PowerShell, Node | Build, packaging and maintenance tooling. |

Three languages throughout: English, Hindi and Gujarati, including the apps'
own screens.

## Running it

Needs MySQL 8, Node 20 or newer, and Flutter 3.19 or newer (Dart SDK `>=3.3.0`).

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
`backend/src/config/preflight.js`.

## Testing

```bash
flutter test                                  # in either app folder
node tests/happy-path.mjs --api http://localhost:4000/api/v1
```

`tests/run-all.ps1` builds a throwaway database from the migrations, starts a
server on a spare port, runs every suite against it and drops the database
afterwards. `-Flutter` adds both app suites. `-Api`/`-Key` point the same
suites at a deployed server instead.

As of 26 September 2026: backend 27/27, customer app 62/62, provider app
66/66, and both configuration suites passing against the live server.
`flutter analyze` is clean on both apps and `tsc -b` on the console.

## What is real and what is not

Worth reading before assuming a number on a screen means money moved.

**Real.** Everything else. Provider matching by distance, availability,
service type and language. Bookings, cancellation policy, session billing,
revenue splits, the Time Bank, the referral chain as far as it goes, live
location tracking, in-app messaging, SOS, broadcasts, device registry, audit
log, uploads, the admin console's configuration and reports.

**Simulated, behind a deliberate seam.** Payments, SMS and OTP delivery,
face matching and push notification each sit behind one interface with a
working stub and at least one real implementation beside it, chosen by
environment variable — `backend/src/integrations/`. A development OTP is
returned in the API response so a phone is not needed. No payment gateway is
connected; the app says so on the screen where a card would be charged.

**Written but not switched on.** AWS Rekognition face matching
(`docs/AWS-REKOGNITION.md`) needs an IAM key pair before it does anything.

**Not built.** Renewal reminders, proration, and any consequence for an
account past its renewal date — a year-old account keeps working and is simply
able to pay again. iOS: the Flutter code is portable but there is no `ios/`
folder and it has never been built or tested on an iPhone.

## Notes for a reviewer

Comments in this codebase tend to explain *why*, and several record a bug and
the reasoning that fixed it. They are worth more than the code around them in
a few places — `backend/src/services/providerMatching.js`,
`backend/src/services/serviceArea.js` and
`backend/src/controllers/uploadController.js` in particular.

Two structural things you may otherwise wonder about:

- **Translations are keyed by their English sentence**, not by an identifier.
  Reword the English and the translation silently orphans, so a test walks
  `lib/` and fails on any key no longer present in the source.
- **The two apps share several files verbatim** — theme, widgets, i18n
  plumbing, the service-area gate. `scripts/sync-design.ps1` copies them one
  way, customer to provider, comparing hashes so unchanged files keep their
  timestamps. The palette and the string tables are deliberately excluded,
  because the two apps differ there on purpose.

## Licence

None yet — all rights reserved. Do not redistribute without asking.
