# Changelog — Sathiyaa

Every change to any part of this project, newest first. Format follows
[Keep a Changelog][kac]; versions follow [semantic versioning][semver].

Four things ship from this repository and they version independently, so each
release heading names the versions it covers:

| Component | Version | Defined in |
|---|---|---|
| Backend API | 1.1.0 | `backend/package.json` |
| Admin console | 1.1.0 | `admin-portal/package.json` |
| Customer app | 1.1.0+2 | `apps/customer_app/pubspec.yaml` |
| Provider app | 1.1.0+2 | `apps/provider_app/pubspec.yaml` |

The API and the console share one version and deploy together — the console
talks to exactly one API and is a client of it. Each app has its own, with a
`+build` number that increases on **every** build that leaves the machine,
because that is the number a crash report carries.

Nothing is too small to record. If a change was worth making it is worth one
line here, and "no visible change" is itself useful to a reader working out why
a build behaves differently.

[kac]: https://keepachangelog.com/en/1.1.0/
[semver]: https://semver.org/

## [Unreleased]

Nothing yet.

## 2026-10-02 — API & console 1.1.0 · both apps 1.1.0+2

**The API and console are deployed to production.** Verified on the live stack
rather than assumed: the full `admin-create-provider` suite was run against the
CloudFront API — 50 checks, including a carer created through the API, signing
in from a handset the server had never seen, and being returned by a customer
search — and the rows it created were deleted afterwards. `GET /health` now
reports the version, so "which build is answering" is a question with an answer.

Providers can now be signed up from the admin console. Most of Sathiyaa's
carers and every agency are taken on in person, and until now the only way to
get either into the system was to borrow the provider's handset and drive the
app's registration form on it — which, done on an office phone, bound the
account to the office phone so the provider could never sign in from their own.

### Added

**Backend**

- **`POST /admin/providers`** — create a freelance carer or an organisation
  with everything the app's five-step registration collects: document uploads,
  document validity dates, work hours, services, languages, the donated-time
  flag, and an organisation's registration certificate, GST number and contact
  person. `org_employee` is deliberately refused: a carer who works for an
  agency is added by that agency in the provider app, so their own Aadhaar and
  police verification are collected from them rather than inherited from the
  agency's approval.
- The endpoint requires three things `/auth/provider/register` does not,
  because an account missing any of them is silently unbookable rather than
  visibly broken: coordinates on the address, at least one service, and for a
  freelancer at least one working day. An organisation that names no days is
  given all seven.
- The PIN the office sets is validated against the same three rules the app's
  own PIN step applies, hashed with bcrypt, never returned in any response, and
  never written to the audit log. The audit entry records `pinSetByAdmin: true`
  so there is a note saying the account's first credential did not come from
  the provider. `device_id` is left null so the provider's own handset claims
  the account on first sign-in.
- **`GET /admin/geocode?q=`** — coordinates for a typed address, proxied
  through whichever `MAPS_PROVIDER` is configured. The console has no GPS to
  ask, and the provider-matching query filters on `HAVING distance_km <= ?`,
  which is NULL without coordinates. Proxied rather than called from the
  browser so the provider's fair-use rate limit is enforced in one place and a
  paid provider's key never reaches the bundle.
- **Field-level validation errors.** A `422 VALIDATION` may now carry a
  `fields` map keyed by the submitting form's own field names, so every problem
  in a long form is reported in one round trip and lands next to the box it is
  about. Present only on validation refusals, so every existing client sees the
  same two-key error shape it always did.
- **`GET /health` reports the build** — `version` from `package.json`, plus
  `buildSha` and `builtAt` when the deployment sets them.

**Admin console**

- **"Add provider"** on the Service Providers page — a five-step form named and
  ordered exactly like the provider app's own registration, so staff reading a
  provider's answers off a paper form are asked for the same things in the same
  order. Document upload with validity dates, a Leaflet map with address lookup
  and a draggable pin, a language picker, and a PIN generator.
- **Confirmation panel** showing the new provider's display id, mobile number
  and PIN, with the PIN readable once and a note saying so. The server never
  sends the PIN back; the panel shows the value the form submitted.
- **"Still outstanding"** on that panel — approval not yet given, registration
  fee not recorded as paid, an organisation with no registration certificate.
  Said at the point of creation rather than discovered later.

**Apps**

- **Both apps: the build's version is visible**, on the Server screen, under a
  new "This app" heading, alongside the handset's make, model and OS. That
  screen is where somebody already is when being helped over the phone, and the
  first question is always which version they are on.

  Nothing new is collected. `DeviceInfo` has read the version from the package
  metadata since the device registry was added — it goes out as the
  `X-App-Version` header on every request — and there was simply nowhere in
  either app to see it. The `summary` getter beside it carried a comment saying
  it was "for the Server screen" and had never been called from anywhere.

**Tests**

- **`tests/admin-create-provider.mjs`** — 50 checks covering the whole path:
  an administrator uploads documents, creates a carer, that carer signs in from
  a handset nobody has seen, a second handset is refused, their profile shows
  what the console entered, a customer search actually returns them, an
  organisation is created and carries what an organisation has, and fourteen
  refusals hold. Registered in `run-all.ps1`.

### Fixed

- **Organisation registration certificates were never stored.** The provider
  app has uploaded them under the category `org-registration` since the
  organisation path was built, and the upload endpoint's category allowlist did
  not contain it — so the request failed with a 400, registration swallowed the
  failure on purpose so that a bad upload could not lose the account, and the
  only sign was a line in the debug console. Every organisation that registered
  through the app did so with its registration certificate silently dropped.
- **Registration dropped seven fields it was sent.** `/auth/provider/register`
  predated the police-verification validity dates, the medical certificate and
  its dates, the donated-time flag and the allocate-via-org flag, and its INSERT
  was never extended — the app papered over it by following registration with a
  `PUT /providers/me`. Anything that registered without making that second call
  — an older build, a test, a script — stored a provider with no document dates
  and no No-Fees flag. All seven are now written by the registration call
  itself; the app's follow-up call is redundant rather than load-bearing, and
  can be removed from the app once the oldest supported build has caught up.
- **The console's provider list and detail now come from one SELECT.** The new
  create endpoint originally answered with the row its own INSERT read back,
  which is a `SELECT *` and therefore included the provider's `pin_hash` — a
  credential the console has no use for, and one the list query had already been
  rewritten to stop leaking. Caught by the new integration test before it
  shipped. Both paths now share `CONSOLE_PROVIDER_SELECT`.
- **Uploaded documents were cached as `public` for a week.** Identity papers,
  police verifications and medical certificates were served
  `Cache-Control: public, max-age=604800`, which permits CloudFront and any
  corporate proxy in between to keep a copy. Now `private`, with
  `X-Robots-Tag: noindex, nofollow`. The path is still unauthenticated — see
  `SECURITY.md` §3, which is the most significant open item and says what
  closes it.
- **A long console form could be thrown away by a stray click.** `Modal` closed
  on any click outside its panel, and the panel's height changes from step to
  step, so the gap beside it moves under the pointer between one click and the
  next. The add-provider form and the PIN confirmation panel now pass
  `dismissOnBackdrop={false}`; every other dialog is unchanged.
- **Choosing one document cleared another.** The console's document field was a
  component declared inside the dialog, so it was a different component on every
  render: attaching one file re-rendered the dialog, which remounted every file
  input, which cleared the file chosen in another one — and typing in a validity
  date lost focus after each character. Hoisted to module scope.
- **The console reported the wrong version.** The sidebar read `v1.0`, typed in
  by hand. It now comes from `package.json` through a Vite `define`.
- **The linter was reading the built bundles.** `oxlint` had no ignore list, so
  it walked `dist/`, `dist-cloud/`, `dist-demo/` and `dist-live/` and reported
  hundreds of warnings about minified vendor code — which is the same as
  reporting none, because nobody reads that output. It now lints `src/` only:
  no errors, and ten known advisories listed in `CONTRIBUTING.md`.
- **`tests/console-routes.mjs` called a working endpoint broken.** It counted
  any status `>= 400` as unreachable, and sends no query string — so the first
  endpoint with a required parameter, `/admin/geocode?q=`, answered 400 "say
  what to look up" and was reported as reachable by nobody. A 400 means the role
  got past authentication *and* the handler ran; only 401, 403 and 404 now count
  as denied.
- **A provider-app doc comment listed the wrong upload categories.**
  `backend.dart` named five of the six the server accepts and omitted
  `org-registration` — the one the organisation path actually sends.
  Documentation only; no behaviour change in the app.

### Changed

- **One INSERT creates a provider, in `backend/src/services/providerAccounts.js`.**
  Three callers need one — the app's registration, an agency adding a carer, and
  the console — and when they were three separate INSERTs they drifted, which is
  where the dropped-fields bug above came from. The validation rules stay with
  each caller, because they genuinely differ: `/auth/provider/register` must
  keep accepting whatever an APK already on somebody's handset sends, while the
  console is served fresh on every page load and is strict.
- **Versions.** The API moves 1.0.0 → 1.1.0. The console moves 0.0.0 → 1.1.0:
  it had never been versioned at all (Vite's default), and ships in lockstep
  with the API, so it takes the same version line from here on. Both apps move
  1.0.0+1 → 1.1.0+2.
- `docs/api-contract.md` documents both new endpoints, the `fields` error shape
  and the `org-registration` upload category.
- **`backend/README.md` had drifted from the code in three places**, one of them
  the opposite of the truth: it still described org employees as inheriting
  their agency's approval status, which was deliberately reversed because it let
  an agency have Sathiyaa tell families somebody was verified when nobody had
  looked at them. Struck through with the reasoning rather than deleted, because
  the reversal is the interesting part. Also corrected: the uploads example
  showed the absolute URL that was removed for being wrong behind a CDN, the
  migration note claimed "one additive migration" when there are seventeen, and
  a section headed "this session" is now dated.
- **`admin-portal/README.md`** documents the new Add provider form, the Devices
  page it had never mentioned, and the snake_case-read / camelCase-write
  convention its types follow.

### Removed

Dead code found by reading every file. Nothing here was reachable:

- `backend/src/utils/ids.js` — `randomVirtualNumber()`, superseded by
  `integrations/call.js virtualNumber()`, which is what `callController`
  actually calls.
- `backend/src/middleware/deviceRegistry.js` — `trackDevice()`, a middleware
  that was never mounted. Every sign-in handler calls `recordDevice()` directly.
- `admin-portal` — `getProvider()`, never called because the list endpoint
  already returns each provider's full detail; and the `ApiError` and
  `Paginated<T>` types, the first duplicating the `ApiRequestError` class the
  client actually throws, the second describing pagination nothing does.

`integrations/providers/fcm.js` keeps `sendToToken()`, which also looks
unreferenced and is not dead: it is the finished half of push notification,
waiting on a `device_tokens` table. That is now said in the file.

### Documentation

New, and written to be read by somebody who has never seen this project:

- `CONTRIBUTING.md` — how changes are made here, which is not obvious: nothing
  in this repository is edited directly.
- `SECURITY.md` — what protects the system, and **eight deliberate gaps**, each
  with why it is there and what closes it. Two of them are load-bearing for
  being able to sign in at all today, so they should not be "tidied up" without
  reading why first.
- `docs/ARCHITECTURE.md` — how a booking travels through the system, the four
  ways a provider becomes silently invisible to search, and where each decision
  lives exactly once.
- `docs/ARCHITECTURE-APPS.md` — the same for the two Flutter apps, including
  the one-way design sync that reverts edits made in the wrong app.

### Repository

- **A split into two repositories is prepared but not yet done.** The Flutter
  apps and the platform ship on completely different clocks — an APK goes
  through store review and a user may be versions behind for a month, while the
  API and the console go out together in an afternoon — so holding both on one
  history means releasing either one drags the other along.

  `scripts/sync-to-github.mjs` can already write `sathiyaa-apps` and
  `sathiyaa-platform`, and both are staged locally with their own READMEs and
  changelogs. They are **parked** until the repositories exist on GitHub; until
  then this repository is the one that is kept current, and `--only=monorepo`
  is what the sync does by default. See `CONTRIBUTING.md`.

## 1.0.0 — 2026-09-29

The state of the project when versioning began: 143 endpoints, 39 tables, 17
migrations, 28 integration suites, 47 Dart files in the customer app and 43 in
the provider app, three languages throughout, both app suites passing and
`flutter analyze` clean.
