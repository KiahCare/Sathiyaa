# Sathiyaa API Contract (v1)

Base URL: `/api/v1`. All requests/responses JSON. Auth via short-lived JWT
in `Authorization: Bearer <token>` obtained from the login endpoints below.
All write endpoints emit an `audit_log` row (form_name, action, device_id,
location_id) automatically via middleware.

Stubbed integrations (mocked now, real SDK swapped in later — each stub
lives in `backend/src/integrations/*` with a single exported function so
swapping providers touches one file):
- **Payment gateway** (`integrations/payment.js`) — `createOrder`, `verifyPayment`. Currently returns a mock "success" after a short delay. Swap in Razorpay/Stripe here.
- **SMS/OTP delivery** (`integrations/sms.js`) — `sendOtp`. Currently logs the OTP to the server console/response (`devOtp` field) instead of sending an SMS. Swap in MSG91/Twilio here.
- **Facial recognition** (`integrations/faceMatch.js`) — `verifyFace(selfieUrl, referencePhotoUrl)`. Currently always returns `{ match: true, confidence: 0.99 }`. Swap in AWS Rekognition/Azure Face here.
- **Maps/geocoding & directions** (`integrations/maps.js`) — `geocode`, `getDirections`, `distanceKm`. Currently returns straight-line (haversine) distance and a stub polyline. Swap in Google Maps Platform here.
- **Live location push** — `provider_location_log` is written on each `PATCH /providers/me/location` call; a real deployment adds a WebSocket/Socket.io channel (see `backend/src/realtime/`) for live map updates. This session ships the REST polling version.

## Auth
| Method | Path | Notes |
|---|---|---|
| POST | `/auth/customer/register` | name, mobile, → sends OTP |
| POST | `/auth/customer/verify-otp` | mobile, otp → sets OTP as password-equivalent, issues JWT |
| POST | `/auth/customer/login` | mobile → sends OTP |
| POST | `/auth/customer/reset-otp` | mobile → re-sends new OTP |
| POST | `/auth/provider/register` | full provider payload (see Providers) → creates pending record |
| POST | `/auth/provider/login` | mobile + 6-digit PIN → JWT (rejects if `device_id` bound to a different device) |
| POST | `/auth/provider/reset-pin-otp` | mobile → OTP to reset PIN |
| POST | `/auth/business-agent/login` | user id + password OR mobile + OTP |
| POST | `/auth/business-agent/reset-otp` | |
| POST | `/auth/admin/login` | email + password |

## Customers
| Method | Path | Notes |
|---|---|---|
| GET/PUT | `/customers/me` | profile incl. computed BMI |
| PUT | `/customers/me/addresses` | primary/secondary, lat/lng |
| GET/POST/PUT/DELETE | `/customers/me/vitals` | filter `?type=&from=&to=` for graphing; soft delete |
| GET/POST/PUT/DELETE | `/customers/me/medications` | with prescription file upload; soft delete |
| GET/POST/PUT/DELETE | `/customers/me/surgeries` | soft delete |
| GET/POST/PUT/DELETE | `/customers/me/allergies` | soft delete |
| GET/POST | `/customers/me/insurance` | |
| GET/POST/PUT/DELETE | `/customers/me/family` | min 1 active required; soft delete |
| POST | `/customers/me/registration-payment` | → `integrations/payment.createOrder` |
| POST | `/customers/me/accept-terms` | body `{accepted:true}` → stamps `terms_privacy_accepted_at`; app gates the registration "Continue" button on this |
| GET/POST/DELETE | `/customers/me/linked-providers` | favorite/regular caretakers, capped at 10 (`DATA_LIMIT` 422 at the cap, `ALREADY_LINKED` 409 on dup); POST body `{providerId}` |
| POST | `/providers/me/bookings/:id/rate-customer` *(provider-side, listed here for symmetry)* | provider rates the customer 1-5 + comments after service starts; one rating per booking (`ALREADY_RATED` 409) — feeds `customers.rating_avg/rating_count` |

Every add/edit/delete on the five profile sections above (vitals, medications,
surgeries, allergies, family) writes one `audit_log` row via `req.audit(...)`
— device id, user name, and transaction timestamp — and deletes are soft
(`deleted_at`, row kept). See `docs/sql-update-delete-queries.md` for the
exact SQL per section.

## Provider Search & Booking (Customer side)
| Method | Path | Notes |
|---|---|---|
| GET | `/providers/search` | q: service_type, date_from, date_to, time_from, time_to, lat, lng, radius_km, gender, language → ranked list respecting work-hours & calendar blocks |
| GET | `/providers/:id` | public profile: name, gender, rating, expertise, hourly_rate |
| POST | `/bookings` | creates booking + fans out `booking_requests` to matching providers |
| GET | `/bookings/:id` | status incl. which provider accepted |
| POST | `/bookings/:id/pay` | 15-min payment window enforced server-side (cron in `backend/src/jobs/expireUnpaidBookings.js`) |
| GET | `/bookings?scope=past\|current\|future` | |
| POST | `/bookings/:id/cancel` | server computes fee: 0% if ≥24h before start... "no refund <24h, 50% fee 24-36h" per spec, encoded in `backend/src/services/cancellationPolicy.js` |
| GET | `/bookings/:id/track` | provider's last known lat/lng + ETA (haversine-based stub) |
| POST | `/bookings/:id/rating` | 1–5 + comment |
| GET | `/bookings/:id/otp` | customer's session-start OTP (issued once provider passes face+geofence check) |

## Providers (Service Provider app)
| Method | Path | Notes |
|---|---|---|
| GET/PUT | `/providers/me` | |
| PUT | `/providers/me/work-hours` | per-day start/end |
| GET/POST/DELETE | `/providers/me/calendar-blocks` | GET takes optional `?from=&to=` and returns `{calendarBlocks:[{id, blockStart, blockEnd, reason, createdAt}]}`; with no window it returns everything from today onwards. POST echoes the created row back, not just its id. |
| PATCH | `/providers/me/location` | `{lat,lng}` — writes `provider_location_log`, requires `location_on=true` to accept requests |
| GET | `/providers/me/requests` | pending `booking_requests` |
| POST | `/providers/me/requests/:bookingId/accept` | first accept wins → invalidates sibling requests |
| POST | `/providers/me/requests/:bookingId/reject` | |
| POST | `/providers/me/bookings/:id/transfer` | to another provider_id → creates `booking_transfers` |
| POST | `/providers/me/transfers/:id/respond` | accept/reject (receiving provider) |
| POST | `/providers/me/bookings/:id/start` | body: selfieUrl → `integrations/faceMatch.verifyFace` + geofence check → issues customer OTP |
| POST | `/providers/me/bookings/:id/verify-start-otp` | customer relays OTP verbally → begins session timer |
| POST | `/providers/me/bookings/:id/end` | computes hours/amount, appends across multi-day bookings |
| POST | `/providers/me/bookings/:id/running-late` | body: minutes (10/15/30) → notifies customer |
| GET | `/providers/me/bookings/:id/directions` | → `integrations/maps.getDirections` |
| GET | `/providers/me/appointments?scope=past\|future` | |
| GET | `/providers/me/dashboard` | revenue & appointment counts by day/week/month/quarter/year (org head sees per-employee breakdown) |
| GET | `/providers/me/schedule-overview?date=` | org head only: all employees' schedules |
| POST | `/providers/employees` | org head adds employee (photo, name, gender, mobile, address, work prefs, distance prefs) |
| GET | `/providers/employees` | org head lists own employees (incl. address, status, rating) |
| PUT | `/providers/employees/:id` | org head edits an employee's photo/name/gender/mobile/address/work-hours/distance prefs |
| PATCH | `/providers/employees/:id/status` | org head marks an employee `active`\|`blocked` (org-scoped — distinct from platform-admin block) |
| POST | `/providers/me/bookings/:id/allocate` | org head assigns one employee (`assignedEmployeeId`) to a booking the org accepted — *simplification: one employee per whole booking, not per-day/hours* |
| POST | `/providers/me/bookings/:id/reallocate` | org head reassigns to a different employee, immediate (no employee accept/reject, unlike `/transfer`) |
| POST | `/providers/me/bookings/:id/org-cancel` | org-initiated cancel; same fee-tier logic as customer cancel, `cancelled_by_type='provider'` |
| GET | `/providers/me/utilization` | org head only: per-employee appointments, business done, employee earning, rating avg, pending payment from customers |
| GET | `/providers/me/time-bank` | No-Fees providers: total donated hours + points earned + per-session ledger |
| POST | `/providers/me/bookings/:id/payments` | body `{amount, paymentType:'full'\|'part', note?}` → records a manual/cash payment, updates `amount_received`/`payment_status` |
| POST | `/providers/me/bookings/:id/payment-reminder` | notifies customer of the remaining balance (stub); 409 `ALREADY_PAID` once fully paid |

Provider profile (`GET/PUT /providers/me`) additionally carries: `hourlyRate` +
`noFees` (donated service — hours credit Time Bank instead of billing),
`policeVerificationUrl/ValidFrom/ValidTo`, `medicalCertificateUrl/ValidFrom/ValidTo`,
and `allocateViaOrg` (organization accounts only — when true, search shows the
organization instead of its individual employees; see below).

### "Allocate via org" search routing
When an organization sets `allocateViaOrg=true`, `GET /providers/search` and
the booking fan-out exclude that org's `org_employee` rows and surface the
organization itself instead (matched if *any* approved/active employee has
the right expertise + work-hours for the requested day/time — calendar
blocks and per-employee conflicts are intentionally not checked at search
time, since the org admin allocates a specific, actually-available employee
only after the request is accepted; documented simplification). The org then
accepts the request as itself and calls `/allocate` to assign an employee.

### Organization billing
Requirement: "if Sathiyaa says 20% of service amount of 100/hr then it will
show as INR 120." Distinct from the freelancer deduction-based
`revenue_sharing_config`: an org sets its own per-service fee
(`organization_service_fees`, falling back to the employee's own
`hourlyRate` if unset), and Sathiyaa's cut is an **additive** markup
(`org_revenue_share_percent`, admin-configured, see Admin below) on top for
the customer-facing amount — the org/employee keeps the full fee, no
deduction. Computed in `services/pricing.js#computeOrgBilling`, applied in
`providerSelfController.endService` when the acting provider is an
`org_employee`.

### Time Bank
Requirement: donated ("No Fees") providers' hours convert to points instead
of being billed. `admin/time-bank-config` sets points-per-hour per
service_type per calendar year; `providerSelfController.endService` credits
`time_bank_ledger` at session end when `provider.no_fees` is true (customer
is billed nothing for that session). See `services/pricing.js#creditTimeBank`.

## Business Agents
| Method | Path | Notes |
|---|---|---|
| GET/PUT | `/business-agents/me` | |
| POST | `/business-agents/me/referrals` | customer name/gender/service/duration/time/mobile/address → generates `referral_code` |
| GET | `/business-agents/me/referrals` | |
| GET | `/business-agents/me/revenue` | Σ (hours used × flat rate per service) per referral, from `revenue_sharing_config` |

## Admin
| Method | Path | Notes |
|---|---|---|
| GET | `/admin/providers?status=pending` | approval queue |
| POST | `/admin/providers/:id/approve` \| `/hold` \| `/reject` | |
| POST | `/admin/providers/:id/block` \| `/unblock` | blocked provider cannot log in |
| GET | `/admin/customers?status=` | directory for the Admin Customers screen |
| POST | `/admin/customers/:id/block` \| `/unblock` | blocked customer cannot log in |
| GET/POST | `/admin/business-agents` | register new Business Partner |
| PUT | `/admin/business-agents/:id` | `{ status: 'active' \| 'blocked' }` — blocked Business Partner cannot log in |
| GET/PUT | `/admin/config` | booking amount, customer/provider annual fees (new vs existing), plus `org_revenue_share_percent` — Sathiyaa's additive markup on organization bookings (see Providers) |
| GET/PUT | `/admin/revenue-sharing` | per service_type: customer rate, provider rate, business-partner flat rate (freelancers only) |
| GET/PUT | `/admin/time-bank-config` | per service_type + application_year: points credited per donated hour (e.g. Companion 250 pts/hr, 2026); PUT body `{items:[...]}`, batch upsert |
| POST | `/admin/broadcast` | title, message, image, audience → fan-out (stub notification) |
| GET | `/admin/tracking/providers` | all providers' last known lat/lng for the live map |
| GET | `/admin/reports/dashboard` | revenue by city / service type / provider |
| GET | `/admin/reports/growth` | new customers & providers per day/week/month/quarter/year |
| GET | `/admin/audit-log` | filterable audit trail |

## Uploads

Every "upload" in the requirements doc — customer photo, prescription, provider photo, Aadhar,
police verification, work certificate, medical certificate, broadcast image — is the same
operation, so there is one endpoint rather than eight. It stores the file and returns a URL; the
caller then writes that URL into whichever `*_url` column it belongs in.

| Method | Path | Notes |
|---|---|---|
| POST | `/uploads` | `multipart/form-data` with the file in the `file` field and a `category` (query param or form field). Any signed-in role. Returns `{url, path, category, contentType, bytes}`. |
| GET | `/uploads/<category>/<file>` | The stored file, served statically (not under `/api/v1`). Sent with `X-Content-Type-Options: nosniff`. |

- **Categories**: `photo`, `prescription`, `aadhar`, `police-verification`, `work-certificate`,
  `medical-certificate`, `broadcast`, `selfie`. An unknown one is a 400.
- **Accepted types**: JPEG, PNG, WebP, HEIC, PDF. Anything else is a 422 `UNSUPPORTED_TYPE`.
- **Size limit**: 8 MB, over which the response is a 422 `LIMIT_FILE_SIZE`.
- Stored filenames are random, so nothing about the name reveals whose file it is.
- Files land in `backend/uploads/<category>/` by default; set `UPLOAD_DIR` to move that. Swapping
  the storage for S3/Azure Blob is a change inside `controllers/uploadController.js` only — no
  caller is affected, since they all just receive a URL.

## Errors
Standard envelope: `{ "error": { "code": "BOOKING_EXPIRED", "message": "..." } }`, HTTP status matches semantics (400/401/403/404/409/422/500).
