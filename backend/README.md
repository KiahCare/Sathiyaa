# Sathiyaa Backend

Node.js + Express + MySQL (mysql2, raw parameterized SQL) API for the
Sathiyaa home-healthcare booking platform. Implements the full contract
in `docs/api-contract.md` against the schema in `docs/schema.sql`.

## Stack

- Node.js 20 or newer, ES modules, Express 4
- MySQL 8 / MariaDB 10.11 via `mysql2/promise` (no ORM — plain
  parameterized SQL, see `src/db/pool.js`)
- JWT auth (`jsonwebtoken`) with 4 roles: `customer`, `provider`,
  `business_agent`, `admin`
- `bcryptjs` for OTP/PIN/password hashing

## Setup

```bash
npm install
cp .env.example .env        # edit if your DB creds differ
npm run migrate             # idempotent — applies every file in
                             # src/db/migrations in name order, safe to re-run
npm run seed                # wipes + reloads realistic sample data
npm run dev                 # http://localhost:4000, --watch reload
```

`npm start` runs the same server without `--watch`, for production-ish use.

**Note on `.env` values with `#`**: MySQL passwords containing `#` (like
the provided `SathiyaaApp#2026`) must be quoted in `.env`
(`DB_PASSWORD="SathiyaaApp#2026"`), otherwise `dotenv` treats everything
after `#` as a comment. Already done in `.env.example`.

## Environment variables

See `.env.example`. Key ones: `DB_*` (connection), `JWT_SECRET`/
`JWT_EXPIRES_IN`, `OTP_TTL_MINUTES`, `BOOKING_PAYMENT_WINDOW_MINUTES`
(15 per spec), `BOOKING_REQUEST_STALE_MINUTES` (housekeeping for
never-answered requests), `START_SERVICE_GEOFENCE_KM` (0.5 per spec).

## Project layout

```
src/
  app.js, server.js        Express bootstrap
  config/env.js             .env parsing
  db/pool.js                mysql2 pool + query()/withTransaction() helpers
  db/migrate.js             idempotent migration runner
  db/migrations/            001_schema.sql, then one numbered file per
                             change. Applied in name order; never edited once
                             they have run anywhere.
  db/seed.js                sample data
  config/version.js         the build's version, read from package.json
  config/preflight.js       refuses to start on an unsafe public configuration
  middleware/auth.js         JWT verify + role guard
  middleware/audit.js        req.audit(formName, action, metadata) helper
  middleware/accessKey.js    the shared key every /api/v1 caller must present
  middleware/rateLimit.js    general + tighter sign-in limiter
  middleware/errorHandler.js
  integrations/              payment, sms, faceMatch, maps, push, call — one
                             interface each, with a stub and a real
                             implementation chosen by environment variable
  services/                  the rules: cancellationPolicy, revenueSharing,
                              providerMatching, providerAccounts, pricing,
                              serviceArea, appConfig, broadcastTargeting,
                              registrationFee, messageService, sosService
  jobs/                      expireUnpaidBookings.js, run every 60s
  routes/, controllers/      one pair per API area
```

## What's implemented

- Full auth for all 4 roles: customer (name+mobile → OTP → JWT),
  provider (full-payload register → PIN login, device binding),
  business agent (password or OTP, by user id or mobile), admin
  (email+password).
- Customer profile: addresses, vitals (graphable via `?from=&to=`),
  medications, surgeries, allergies, insurance, family (min-1 enforced
  on delete), BMI is DB-computed (generated column), registration fee
  payment.
- Provider profile: work-hours, calendar blocks, location ping +
  location log, org employee management, registration fee payment.
- Search & booking: haversine-distance + gender/language/work-hours/
  calendar-block/existing-booking filtering, multi-provider fan-out,
  first-accept-wins with sibling-request invalidation, 15-min payment
  window (enforced both inline on `/pay` and by the background job),
  cancellation fee tiers, rating, live tracking (ETA stub).
- Start/end-of-service: face-match stub + haversine geofence check →
  OTP issued → customer relays verbally → provider submits → timer
  starts; end computes hours/amount and accumulates across multi-day
  bookings (`GET .../end` returns `bookingTotals`).
- Transfers (accept/reject by receiving provider), running-late stub,
  directions stub, dashboards (day/week/month/quarter/year via SQL date
  functions, org-head per-employee breakdown), schedule overview.
- Business agent referrals + revenue query (Σ hours × flat rate).
- Admin: approval queue (approve/hold/reject/block/unblock), business
  agent registration, config CRUD, revenue-sharing CRUD, broadcast
  (persist + list), live provider map, reports (by city/service/
  provider, growth by period), audit log with filters.
- Every mutating route writes an `audit_log` row via `req.audit(...)`
  (see `middleware/audit.js`) — device id from `X-Device-Id`, location
  from `X-Location` headers. Verified end-to-end (see below).
- Masked calling: `POST /bookings/:id/masked-call` mints a fake virtual
  number into `masked_call_sessions`, real numbers never returned.

## File uploads

One endpoint covers every upload in the requirements doc — customer photo,
prescription, provider photo, Aadhar, police verification, work certificate,
medical certificate, broadcast image — because they are all the same
operation. It stores the file and returns a URL; the caller writes that URL
into whichever `*_url` column it belongs in.

```bash
curl -X POST "$BASE/uploads?category=photo"   -H "Authorization: Bearer $TOKEN"   -F "file=@/path/to/photo.jpg"
# -> {"url":"/uploads/photo/1789...-a1b2.jpg", "path":"/uploads/photo/...", ...}
#    Relative, deliberately: an absolute URL built from the API's own Host
#    header is the origin's internal name behind CloudFront. Every client
#    resolves it against the API address it already knows.
```

- Categories: `photo`, `prescription`, `aadhar`, `police-verification`,
  `work-certificate`, `medical-certificate`, `broadcast`, `selfie`.
- Accepted: JPEG, PNG, WebP, HEIC, PDF. Anything else is a 422
  `UNSUPPORTED_TYPE`; over 8 MB is a 422 `LIMIT_FILE_SIZE`.
- Stored under `backend/uploads/<category>/` with a random filename, served
  back from `/uploads/...` with `X-Content-Type-Options: nosniff`. Set
  `UPLOAD_DIR` to move that directory.
- `uploads/` is gitignored — these are runtime data, not source.

**Going to production**: local disk is the simplest thing that works while
developing. Swap `controllers/uploadController.js` for an S3/Azure Blob put
and every caller is unaffected, since they only ever receive a URL. Nothing
scans uploads for malware today; add that at the same time.

## Integrations — written, switched off

Every third-party integration has a **real implementation that is finished and
tested**, and a stub that is what actually runs until you say otherwise. So a
fresh checkout works end to end with no accounts, no API keys and no bills,
and going live later is setting environment variables rather than writing
code.

| Integration | Default | Real adapter | Turn on with |
|---|---|---|---|
| Payments | stub — instant success | `providers/razorpay.js` (orders, signature verification, refunds, webhooks) | `PAYMENT_PROVIDER=razorpay` |
| SMS / OTP | stub — logs the OTP, returns it as `devOtp` | `providers/sms.js` (MSG91 and Twilio) | `SMS_PROVIDER=msg91` or `twilio` |
| Face matching | stub — always matches | `providers/azureFace.js` (detect + verify, thresholded) | `FACE_PROVIDER=azure` |
| Maps | stub — haversine + assumed speed | `providers/googleMaps.js` (Geocoding + Directions with live traffic) | `MAPS_PROVIDER=google` |
| Push | stub — logs | `providers/fcm.js` (HTTP v1, service-account JWT) | `PUSH_PROVIDER=fcm` |
| Masked calls | stub — mints a number | `providers/exotel.js` (two-leg bridge) | `CALL_PROVIDER=exotel` |

The server prints which of these are live at startup, and **refuses to start**
if one is selected without its credentials — naming the missing variable. A
half-configured payment gateway should fail at boot, not when a customer taps
Pay.

None of the adapters need an SDK; they all use the providers' REST APIs, so
there is nothing extra to install or keep current. See `.env.example` for the
full set of variables.

**Two of these have a waiting period, not just a signup.** Indian
transactional SMS needs DLT registration of the sender id and every template
(1-2 weeks), and Azure Face verification is a Limited Access feature needing
an approved application. Both are business processes — start them well before
you need them.

### What changed when push arrived

"Running late", payment reminders and admin broadcasts used to be persisted
and then go nowhere. They now go through `integrations/push.js`, which by
default logs — so behaviour is unchanged until `PUSH_PROVIDER=fcm`, but there
is now one place to switch on. Broadcasts fan out to active customers and/or
providers by audience.

The remaining piece of push is a `device_tokens` table: there is nowhere yet
to record which device belongs to which person, so `sendToUser` logs what it
would have sent. That needs the Flutter side (`firebase_messaging`) to have a
token to register in the first place.

## Deviations from the schema / contract (and why)

1. **`service_providers.languages` (additive column, migration 002).**
   The contract's search filter takes a `language` param, but the base
   schema only gives `customers.preferred_languages` — providers had no
   language field at all. Added one JSON column, non-breaking.
2. **Provider PIN reset is one endpoint, two phases.** The contract
   lists only `POST /auth/provider/reset-pin-otp` with no separate
   "confirm" endpoint. `{mobile}` sends an OTP (via `otp_log`,
   `purpose='reset'`); calling the same endpoint again with
   `{mobile, otp, newPin}` verifies and sets the new PIN — keeps to the
   literal one-endpoint contract while remaining fully functional.
3. **`customers`/`service_providers` NOT NULL columns at register time**
   (`photo_url`, `dob`, `gender` on `customers`). The contract's
   customer register endpoint only takes `name`+`mobile`
   (OTP-first, expand/collapse profile UX per the requirements doc), so
   the row is created with neutral placeholders (`dob='1970-01-01'`,
   `gender='other'`, `photo_url=''`) and the customer fills in real
   values later via `PUT /customers/me`. Not enforced as a
   booking-blocker (out of scope for this backend pass).
4. **Single `booking_service_sessions.amount` column, one meaning.**
   The schema has only one `amount` per session row, but the business
   rules describe *two* numbers (what the customer is billed vs. what
   the provider is paid). Per the task's explicit guidance ("provider
   gets a defined rate/hour set by admin"), `amount` = `total_hours ×
   revenue_sharing_config.provider_rate_per_hour` (the admin-configured
   payout) — this is what's summed for provider/org dashboards and also
   what's shown to the customer as the "total amount" for that session,
   since there's no second column to hold a separate customer bill. The
   `customer_rate_per_hour` and `business_partner_flat_per_hour` for
   that session are still returned in the `end-service` response's
   `revenueBreakdown` for transparency, just not persisted per-session.
   Historical rate-at-time isn't preserved either — dashboards use the
   *currently* effective `revenue_sharing_config` row, not the one in
   force when the session actually happened; a production build would
   want a `rate_snapshot` column or similar.
5. **Provider registration issues a JWT immediately** (status stays
   `pending`/`approval_status='pending'`) so a newly-registered provider
   can call `POST /providers/me/registration-payment` before an admin
   has approved them — matches "registration fee → activates post admin
   approval" from the requirements doc (fee comes first, then review).
6. ~~**Org employees auto-inherit the parent org's approval status.**~~
   **Reversed, deliberately.** A carer added by an organisation via
   `POST /providers/employees` now always starts `pending`, whatever the
   agency's own status.

   The original reasoning — that re-vetting each employee was unwarranted
   process for an MVP — did not survive contact with what it actually
   allowed: an agency could add somebody, attach any two photographs, and
   have Sathiyaa tell families that person was verified, with nobody at
   Sathiyaa having looked at them. Holding the documents is the agency's
   job; deciding they are genuine is ours. Each carer now carries their own
   Aadhaar and police verification and goes through the same admin queue as
   a carer who registers alone. See the comment in
   `controllers/providerSelfController.js`.
7. **Work-hours/day matching in provider search & fan-out is checked
   against the booking's *start date* only**, not every day in a
   multi-day range, and calendar-block/existing-booking overlap checks
   are date-level, not time-of-day-level. Documented simplification —
   flagged in `services/providerMatching.js`.
8. **`POST /admin/business-agents/referrals/:id/allocate`** — additive
   endpoint (not in the API contract's table, but described in the MVP
   requirements doc: "allocate provider to Business-Partner-referred
   customer based on calendar availability"). Reuses the same matching
   logic as customer search.
9. **`POST /bookings/:id/masked-call`** — the contract's endpoint list
   doesn't literally enumerate a masked-call route, but the
   `masked_call_sessions` table and the non-functional requirement
   ("phone calls... must not show provider's name/number") both call
   for one, so it's added under `/bookings/:id/masked-call`.

## Verification performed when this was first built (September 2026)

Kept as a record of what was checked at the time. The current state of the
suite is in the repository root's README, and `tests/run-all.ps1` is how it
is re-checked.

```
npm install
npm run migrate   # idempotent, re-ran twice to confirm no errors on re-run
npm run seed       # 10 customers, 8 providers (freelancer/org/org_employee
                    # mix, one left in approval_status='pending'), 3 business
                    # agents with referrals, 9 bookings spanning every status
npm run dev &      # (foreground during dev; started via `node src/server.js`
                    # for this smoke test, then stopped — see below)
```

Full happy-path curl flow (customer register → verify-otp → set address
→ search → book → provider login → accept → pay → start (face+geofence
stub) → customer fetches OTP → provider verify-start-otp → end (hours +
amount computed, `bookingCompleted:true`) → rate) — every step returned
2xx with sane JSON, final booking `status` was `completed`. Then
confirmed with a direct query that `audit_log` had a row for every
mutation in that flow, correctly attributed to the acting
customer/provider (not `system`) — see items 24-36 in a live run:

```sql
SELECT id, user_type, user_id, user_name, form_name, action FROM audit_log ORDER BY id DESC LIMIT 13;
-- CustomerRegister, CustomerVerifyOtp, CustomerAddresses, CreateBooking,
-- ProviderLogin, ProviderUpdateProfile, ProviderLocationPing,
-- ProviderAcceptRequest, PayBooking, ProviderStartService,
-- ProviderVerifyStartOtp, ProviderEndService, RateBooking
```

Also separately verified: admin login/approve-provider/config CRUD/
revenue-sharing CRUD/broadcast/tracking/reports/audit-log; business
agent login (password)/create-referral/list-referrals/revenue query
(Σ hours × flat rate, matched the seeded nurse referral's 4h × ₹80 =
₹320); org-head dashboard (per-employee breakdown) and schedule
overview; device-binding rejection (second login from a different
`deviceId` correctly 403s); full-refund cancellation tier on a booking
>36h out; masked-call stub; and the 15-minute payment-expiry background
job (manually forced a `payment_deadline_at` into the past, called
`expireUnpaidBookings()` directly, booking flipped to `expired` and its
`booking_requests` row to `invalidated`).

The server was stopped (`pkill -f "node src/server.js"`, confirmed via a
follow-up `curl` connection-refused) before finishing this session —
`npm run dev` starts it cleanly from scratch.

## Example curl flow

```bash
BASE=http://localhost:4000/api/v1

# 1. Register (OTP echoed as devOtp outside production)
curl -s -X POST $BASE/auth/customer/register -H 'Content-Type: application/json' \
  -d '{"name":"Test Customer","mobile":"9999911111"}'

# 2. Verify OTP -> JWT
curl -s -X POST $BASE/auth/customer/verify-otp -H 'Content-Type: application/json' \
  -d '{"mobile":"9999911111","otp":"<devOtp from step 1>"}'
CUST_TOKEN=<token from response>

# 3. Set primary address (needed for geo search/booking)
curl -s -X PUT $BASE/customers/me/addresses -H "Authorization: Bearer $CUST_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"primary":{"line1":"123 Test St","city":"Bengaluru","latitude":12.9716,"longitude":77.5946}}'

# 4. Search providers
curl -s "$BASE/providers/search?service_type=companion&date_from=2026-09-05&time_from=09:00:00&time_to=12:00:00&lat=12.9716&lng=77.5946&radius_km=25"

# 5. Create booking (fans out requests to matches)
curl -s -X POST $BASE/bookings -H "Authorization: Bearer $CUST_TOKEN" -H 'Content-Type: application/json' \
  -d '{"serviceType":"companion","startDate":"2026-09-05","endDate":"2026-09-05","timeFrom":"09:00:00","timeTo":"12:00:00","latitude":12.9716,"longitude":77.5946}'
BOOKING_ID=<bookingId from response>

# 6. Provider login (seeded: mobile 9600000000, PIN 123456)
curl -s -X POST $BASE/auth/provider/login -H 'Content-Type: application/json' \
  -d '{"mobile":"9600000000","pin":"123456","deviceId":"demo-device-1"}'
PROV_TOKEN=<token>

# 7. Provider turns location on + pings a location near the booking address
curl -s -X PUT $BASE/providers/me -H "Authorization: Bearer $PROV_TOKEN" -H 'Content-Type: application/json' -d '{"locationOn":true}'
curl -s -X PATCH $BASE/providers/me/location -H "Authorization: Bearer $PROV_TOKEN" -H 'Content-Type: application/json' -d '{"lat":12.9716,"lng":77.5946}'

# 8. Provider accepts (first-accept-wins; siblings auto-invalidated)
curl -s -X POST $BASE/providers/me/requests/$BOOKING_ID/accept -H "Authorization: Bearer $PROV_TOKEN"

# 9. Customer pays within the 15-minute window
curl -s -X POST $BASE/bookings/$BOOKING_ID/pay -H "Authorization: Bearer $CUST_TOKEN" -H 'Content-Type: application/json' -d '{}'

# 10. Provider starts (selfie -> face-match stub + geofence check) -> issues OTP to customer
curl -s -X POST $BASE/providers/me/bookings/$BOOKING_ID/start -H "Authorization: Bearer $PROV_TOKEN" \
  -H 'Content-Type: application/json' -d '{"selfieUrl":"https://example.com/selfie.jpg"}'

# 11. Customer reads the OTP, relays it verbally
curl -s $BASE/bookings/$BOOKING_ID/otp -H "Authorization: Bearer $CUST_TOKEN"

# 12. Provider submits it -> starts the session timer
curl -s -X POST $BASE/providers/me/bookings/$BOOKING_ID/verify-start-otp -H "Authorization: Bearer $PROV_TOKEN" \
  -H 'Content-Type: application/json' -d '{"otp":"<otp from step 11>"}'

# 13. Provider ends -> computes hours/amount (accumulates across multi-day bookings)
curl -s -X POST $BASE/providers/me/bookings/$BOOKING_ID/end -H "Authorization: Bearer $PROV_TOKEN"

# 14. Customer rates
curl -s -X POST $BASE/bookings/$BOOKING_ID/rating -H "Authorization: Bearer $CUST_TOKEN" \
  -H 'Content-Type: application/json' -d '{"rating":5,"comments":"Excellent!"}'
```

## Seeded logins (after `npm run seed`)

- Admin: `admin@sathiyaa.com` / `Admin@123`
- Customer OTP flow: mobile `9700000000` (Anita Rao) — any seeded
  customer mobile works, OTP flow only.
- Freelancer provider: mobile `9600000000` (Meena Krishnan), PIN `123456`
- Org head: mobile `9611122233` (CareWell Health Services), PIN `123456`
- Business agent: identifier `APOL9332` (or mobile `9800000001`),
  password `Partner@123`
