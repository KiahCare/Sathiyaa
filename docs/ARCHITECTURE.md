# Architecture — Sathiyaa platform

Read this first. It explains how a booking actually travels through the system,
which is the shape everything else is built around.
[`api-contract.md`](api-contract.md) is the endpoint reference;
[`erd.html`](erd.html) is the schema.

## The pieces

```
  Customer app  ─┐
  Provider app  ─┤                   ┌─ MySQL 8  (39 tables)
                 ├─► CloudFront ─► EC2: Node/Express ─┤
  Admin console ─┘       TLS         (one process)    └─ disk: uploads/
       (S3 + CloudFront)                                  (identity documents)

                                     └─ integrations/ ─► SMS · payment · maps
                                        (one seam,         face match · push
                                         stub or real)
```

One process, one database, one instance. That is the right size for this
system today and the places where it stops being right are named below.

## How a request is handled

`src/app.js` builds the stack in an order that matters:

1. **`trust proxy`** — a hop count, not `true`. Behind CloudFront the caller's
   address arrives in `X-Forwarded-For`; trusting it blindly lets anyone walk
   around the rate limiter one fake address at a time.
2. **Helmet, CORS, JSON body limit, request log, audit context.**
3. **`GET /health`** — unauthenticated, answers with the version and build.
4. **General rate limit.**
5. **`/uploads`** — static files. Deliberately above the access-key check; see
   `SECURITY.md` §3 for why, and what that costs.
6. **`/api/v1` access key** — one shared key, so an unauthenticated scanner
   gets 401 on every path rather than a working registration flow.
7. **`/api/v1/auth` tighter rate limit** — the endpoints that hand something
   back for free.
8. **The routes.**
9. **Multer and general error handlers**, which turn a thrown `ApiError` into
   `{error: {code, message}}` and a MySQL foreign-key refusal into a sentence.

### The layers below a route

```
routes/*.routes.js     one line per endpoint; auth is declared here, nowhere else
  controllers/*.js     reads the request, decides, writes the response
    services/*.js      the rules — pricing, matching, policy, area, accounts
      db/pool.js       query() and withTransaction()
```

A controller may call several services; a service never calls a controller and
never touches `req` or `res`. Anything that could be asked as a question about
the business — "is this address in the service area", "what does this booking
cost", "who can take this job", "what goes in a provider row" — belongs in
`services/`, because that is how it ends up written once rather than three
times.

`utils/` is for things with no business meaning: ids, dates, JWTs, haversine,
the error classes.

## The booking lifecycle

This is the core of the product. Statuses are the `bookings.status` enum.

```
  searching ──► pending_payment ──► confirmed ──► in_progress ──► completed
      │                │                │              │
      │                │ 15 min          │              │
      ▼                ▼                 ▼              ▼
  cancelled         expired          cancelled      cancelled
```

1. **`searching`** — the customer asks for a service, a date, a time window and
   a place. `services/providerMatching.js` finds the candidates and a
   `booking_requests` row is written for each. They are notified.
2. A provider accepts. Everybody else's request becomes `invalidated`. The
   booking becomes **`pending_payment`** with a `payment_deadline_at` 15 minutes
   out.
3. The customer pays the booking charge → **`confirmed`**. If they do not,
   `jobs/expireUnpaidBookings.js` sweeps it to **`expired`** every 60 seconds
   and the provider is released.
4. On the day, the provider starts the visit: a geofence check, an OTP the
   customer reads out, and a face match (stubbed — see `SECURITY.md` §8).
   **`in_progress`**.
5. They end it. Hours are computed, `booking_service_sessions` is written, and
   the money is split by `services/revenueSharing.js` — or, when the provider
   gave their time free, credited to the Time Bank by `services/pricing.js`.
   **`completed`**.
6. A cancellation at any point goes through `services/cancellationPolicy.js`,
   which decides the fee and the refund from how many hours were left.

An organisation is different in one place: when `allocate_via_org` is on, the
booking is confirmed against the *agency*, and the agency then names one of its
carers in `assigned_employee_id`.

## Provider matching, and the four ways to be invisible

`services/providerMatching.js` is the hardest query in the system and the one
most worth reading. It is also where most "the app says there are no carers"
reports come from, because a provider can be missing from it for four reasons
that all look like nothing being wrong:

| Why | What it looks like |
|---|---|
| no `service_provider_expertise` row | INNER JOIN; provider matches nothing, ever |
| no `service_provider_work_hours` row | INNER JOIN; same |
| no latitude on the home address | `HAVING distance_km <= ?` is NULL ≤ 35, which is not true |
| `gender` is NULL | excluded from every search where a family asked for a man or a woman |

In every case the console shows the provider as approved and healthy. This is
why `POST /admin/providers` requires coordinates, at least one service and (for
a freelancer) at least one working day, and why an organisation that names no
days is given all seven rather than none.

The query runs twice and unions: once for individual carers, once for agencies
on the strength of the carers they could send. Organisations are excluded from
the first pass — they used to be returned by both, which inserted two
`booking_requests` rows with the same `(booking_id, provider_id)` and surfaced
to the customer as "Record already exists".

## Creating a provider

Three callers need to write a `service_providers` row:

- `/auth/provider/register` — the app
- `/providers/employees` — an agency adding a carer
- `/admin/providers` — the office

They share one INSERT, in `services/providerAccounts.js`. They do **not** share
validation, and that is deliberate: the registration endpoint has to keep
accepting whatever an APK already on somebody's handset sends, while the
console is served fresh on every page load and can be strict. The predicates
themselves (mobile format, PIN strength, rate band, GST shape) live in that one
module so the rules are written once; which of them to enforce is each
caller's decision.

An `org_employee` always starts `pending`, whatever the agency's own status. An
agency being approved says nothing about the person it is about to send into
somebody's home.

## The integrations seam

`src/integrations/` — payment, SMS, maps, face match, push, masked calls. Each
is one interface with a working stub and at least one real implementation
beside it, chosen by an environment variable:

```
integrations/sms.js           ──► providers/smsStub.js    (default)
                              └─► providers/sms.js        (real)
integrations/maps.js          ──► providers/mapsStub.js
                              ├─► providers/osm.js        (default, live)
                              └─► providers/googleMaps.js
```

Nothing above this layer knows which is in use. Switching one on is an
environment variable and a restart, never a code change — and the startup
banner prints which of them are live, so a deployment cannot quietly be running
on stubs.

Maps is the one currently live, on OpenStreetMap: real geocoding and real road
routing, no account, no key. It is rate-limited to one request a second in
`providers/osm.js` because those are volunteer-funded public endpoints.

## The admin console

React 19 + TypeScript + Vite, a static bundle on S3 behind its own CloudFront
distribution. It is a pure client of the API and has no server of its own.

```
src/api/client.ts      axios instance: token, access key, error translation
src/api/services.ts    one function per operation; EVERY one branches on USE_MOCK
src/api/mockStore.ts   an in-memory clone of mockData, so demo-mode actions persist
src/pages/admin/*      Sathiyaa's own staff
src/pages/partner/*    business partners, who see only their own referrals
src/types/index.ts     mirrors the API's shapes
```

**`USE_MOCK` is the thing to understand.** The console runs with no backend at
all, against a full in-memory dataset, so it can be demonstrated on a plane.
That means every new operation needs a mock branch as well as a real one, or
demo mode loses a screen — and demo mode is what gets shown to people.

Read endpoints hand back **database rows as they are** (`provider_id`,
`approval_status`); write endpoints take **camelCase JSON**, the same shape the
apps send. That inconsistency is the API's, not the console's, and
`types/index.ts` names each field the way the endpoint actually names it so a
reviewer can check one against the other.

`tests/contract-drift.mjs` compares every list endpoint's real response against
those TypeScript types and fails when they diverge.

## Where things are decided, once

If you are about to write a rule, check whether it already exists here:

| Question | Where |
|---|---|
| What does this booking cost? | `services/pricing.js`, `services/revenueSharing.js` |
| Who can take this job? | `services/providerMatching.js` |
| Is this address somewhere we operate? | `services/serviceArea.js` |
| What happens if this is cancelled now? | `services/cancellationPolicy.js` |
| What goes in a new provider row? | `services/providerAccounts.js` |
| What may the console see of a provider? | `PROVIDER_COLUMNS` in `adminController.js` |
| What is a valid enum value? | `utils/enums.js` |
| Is the configuration safe to expose? | `config/preflight.js` |

Every expensive bug in this project's history has been the same shape: one of
these written out in two places, and then one copy changed.

## Where one process stops being enough

Named so nobody has to rediscover them under load:

- **Rate limiting counts in memory**, per process. A second instance doubles
  every limit. Move the store to Redis first.
- **Uploads are written to local disk.** A second instance cannot see the
  first's files. `UPLOAD_DIR` on a mounted volume is the stopgap; S3 is the
  answer, and is also what closes `SECURITY.md` §3.
- **The expiry sweep runs in-process on a 60-second interval.** Two instances
  means two sweeps racing over the same rows. The update is conditional so the
  race is survivable, but it should be a single scheduled job before it matters.
- **Search is `LIKE '%term%'`.** Fine for thousands of rows, useless to an
  index. Revisit at a scale this system is nowhere near.
