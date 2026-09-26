---
name: sathiyaa-coverage-matrix
description: Requirement-by-requirement coverage matrix for the Sathiyaa MVP build produced 2026-08-31 (backend, admin portal, customer/provider app prototypes) against Sathiyaa MVP Requirements.docx, updated 2026-08-31 for Admin-block + 5-record-limit, and updated 2026-09-09 for linking/provider-documents/No-Fees+Time-Bank/manual-payments/feedback-on-customer/organization-employee-management/org-service-fees/admin-revenue-share+Time-Bank-config plus the finalized Terms & Conditions / Privacy Policy documents.
sources: [cowork]
---

# Sathiyaa — Implementation Coverage (2026-08-31 build, updated 2026-09-09)

Full annotated Word doc and all source code were delivered to the user directly in the conversation (this file mirrors that doc's coverage matrix for project record-keeping — the Projects doc-write tool rejected binary .docx/.pdf uploads in this session).

**Update (same day, later pass):** the user re-uploaded `Sathiyaa MVP Requirements.docx` with two additional requirements not present in the version this matrix was originally built against. Both are now implemented and verified, and are reflected below:
1. **Admin can block a Customer, Service Provider, or Business Partner; a blocked user of any of the three cannot log in.** (Previously only Customer and Service Provider blocking existed — Business Partner blocking was added in this pass.)
2. **Data limit of 5 records for Vitals, Medication, Surgery, and Allergy.** (Vitals: 5 total across all vital types combined, not 5 per type — confirmed with the user. Add forms block once the cap is reached until a record is deleted, matching the existing Family-contacts cap pattern.)

**Update (2026-09-09 pass):** the user supplied a further batch of ~20 requirements (linking, provider documents/dates, No Fees + Time Bank, manual payment tracking, feedback-on-customer, organization employee management + request allocation, organization service fees, admin revenue-share % and Time Bank config) plus the finalized Terms & Conditions / Privacy Policy documents. All are implemented end-to-end (schema → backend → all three app prototypes) and are reflected in the sections below, replacing the previous per-section entries where they overlap. See the "2026-09-09 pass" subsection under each role for the new bullets and the summary count update.

**Update (2026-09-10 pass — Flutter build):** the two mobile apps now exist as real Flutter/Dart
projects (`Sathiyaa Flutter/customer_app`, `Sathiyaa Flutter/provider_app`) and build to installable
release APKs (`_builds/sathiyaa-customer.apk`, `_builds/sathiyaa-provider.apk`). This closes the two
NOT COVERED tech-stack rows and the PARTIAL platform-level row. The gaps that remained between the
Flutter apps and the React prototypes were also closed in this pass — see the "2026-09-10 pass"
section at the end. Both apps still run on in-memory seeded data; wiring them to the Express API is
the next pass.

**Summary:** 10 PARTIAL · 0 NOT COVERED · 93 COVERED · 4 STUBBED (107 total)

## Overall / Platform-level requirements

- **[COVERED]** Mobile app for Customer and Service Provider (freelancer & organization) + Web Portal for Business Partners and Admin — **Updated 2026-09-10:** the two mobile apps are now real Flutter/Dart builds shipping as installable APKs; the React prototypes remain as the browser-reviewable reference. Original note follows — Admin + Business Partner web portal built in React+TS (admin-portal/). Customer and Service Provider apps built as clickable React web prototypes (customer-app-web/, provider-app-web/) reproducing every screen and flow from this document — real Flutter/Dart builds were not produced in this pass (this environment has no mobile emulator to demo one), per the scoping decision made before this build started. Both prototypes are structured 1:1 against the shared API contract so a Flutter build can follow the same spec directly.
- **[NOT COVERED]** Data encrypted at rest and in motion — Not implemented in application code this pass. In transit: standard practice is HTTPS/TLS termination at the hosting layer once deployed — not something local dev code configures. At rest: enable via managed MySQL on Azure/AWS (Azure Database for MySQL and AWS RDS both support encryption-at-rest natively as a deployment setting). No field-level application encryption was added for sensitive columns (documents, vitals, etc.) in this pass.
- **[COVERED]** Technology stack — Customer App: Flutter + Dart — `Sathiyaa Flutter/customer_app`, Flutter 3.47 / Dart 3.13, `flutter analyze` clean, builds to `in.sathiyaa.customer` (minSdk 24, targetSdk 36).
- **[COVERED]** Technology stack — Caretaker App: Flutter + Dart — `Sathiyaa Flutter/provider_app`, same toolchain, builds to `in.sathiyaa.provider`.
- **[COVERED]** Technology stack — Admin Website: React.js + TypeScript — admin-portal/ — Vite + React + TypeScript, builds with zero type errors.
- **[COVERED]** Technology stack — Backend/API: Node.js + Express.js — backend/ — Express + mysql2, layered routes/controllers/services/middleware.
- **[COVERED]** Technology stack — Database: MySQL — docs/schema.sql — 29 tables, loaded and validated against a live MySQL 10.11 (MariaDB) instance.
- **[COVERED]** Downloadable database schema — docs/schema.sql
- **[COVERED]** Downloadable Entity Relationship Diagram — docs/erd.png and docs/erd.pdf, generated from the live schema.
- **[COVERED]** Application and APIs designed to be downloaded and later hosted on Azure or AWS — All four codebases are packaged as standalone zips. The backend is a stateless, env-configured Express app; both React apps build to static assets. Nothing is tied to a specific cloud provider.

## Customer

- **[COVERED]** Customer registration using Name, Mobile Number, Set OTP — Backend: POST /auth/customer/register. Prototype: Register screen.
- **[COVERED]** Customer login using set OTP — POST /auth/customer/login + verify-otp; verified end-to-end.
- **[COVERED]** Reset OTP provision — POST /auth/customer/reset-otp; prototype has a Reset OTP link.
- **[COVERED]** Customer ID (incrementally auto-generated) — mandatory — customers.display_id, e.g. CUST-000013 (confirmed live).
- **[COVERED]** Name — mandatory
- **[COVERED]** Upload Photo — mandatory — Upload + preview in the prototype; photo_url field on the backend.
- **[COVERED]** Age (date-picker) — mandatory
- **[COVERED]** Gender (drop-down) — mandatory
- **[COVERED]** Blood Group (drop-down)
- **[PARTIAL]** Address with Google mapping, Primary & Secondary, at least one mandatory — Address form + lat/lng fields + a primary/secondary distinction are fully modeled and enforced (schema + UI). The map itself is a static placeholder pin rather than a live embedded Google Maps widget (see integrations/maps.js stub) — no Maps API key was wired in this pass.
- **[COVERED]** Email id and Contact Number (captured during registration)
- **[COVERED]** Preferred Language/s (drop-down)
- **[COVERED]** Height, Weight, BMI (calculated field) — BMI is a MySQL generated column, and live-calculated in the prototype UI as you type.
- **[COVERED]** Preferred mode of communication (Email/Call/SMS) with timeframe
- **[COVERED]** Vitals — BP + date, SpO2, Pulse, Blood Glucose, with a graph over a selectable duration — customer_vitals table; prototype has a recharts trend graph with 7/30/90-day windows, plus a full tabular Add/Edit/Delete view (edit and delete were added in a follow-up pass — see the Non-functional row below). Capped at 5 records **total across all vital types combined** (confirmed with the user) — the Add form disables and shows a "5/5" counter once reached; deleting a record frees a slot.
- **[COVERED]** Medication details — Name, Frequency, prescription upload — Tabular Add/Edit/Delete view added in a follow-up pass (previously add-only). Capped at 5 records; Add form blocks at the cap until a record is deleted.
- **[COVERED]** Surgery details — Name, Date — Tabular Add/Edit/Delete view added in a follow-up pass (previously add-only). Capped at 5 records; same block-until-delete behavior.
- **[COVERED]** Allergy details — Name, Onset Date, Active/Inactive — Tabular Add/Edit/Delete view added in a follow-up pass (previously add-only). Capped at 5 records; same block-until-delete behavior.
- **[COVERED]** Insurance details — Insured With, Policy Number, Start/End Date
- **[COVERED]** Family Details — Name, Relationship, Contact; at least 3 slots, at least 1 mandatory — Minimum-1 validation implemented and visible in the UI; tabular Add/Edit/Delete added in a follow-up pass (delete now soft, still enforcing the ≥1-active-member rule). Already capped at 5 records — the new data-limit requirement below is consistent with this pre-existing cap.
- **[COVERED]** *(added requirement)* Data limit of 5 records for Vitals, Medication, Surgery, and Allergy — Enforced identically on both ends: the backend rejects a 6th insert per section with a 422 `DATA_LIMIT` error (`backend/src/controllers/customerController.js`, `assertUnderRecordLimit`, counting only non-deleted rows), and the customer app's Add forms disable themselves at the cap with a matching on-screen message, re-enabling the moment a record is deleted. Verified via curl against the live backend (6th add rejected, add succeeds again after a delete) and via `npm run build` for the UI changes.
- **[STUBBED]** Registration Payment via Payment Gateway — integrations/payment.js — mock success response. Real Razorpay/Stripe integration is a one-file swap.
- **[COVERED]** Expand/Collapse Insurance, Family, Allergy, Surgery, Medication, Vital sections
- **[COVERED]** Search for Companion / Medical Companion / Nurse / Physiotherapy by date duration, time, location
- **[COVERED]** Provider results filtered by location, date/time duration, gender, language — Haversine distance + work-hours + calendar-block + gender/language filtering implemented server-side and verified.
- **[COVERED]** List of available providers shown
- **[COVERED]** View provider details — Name, Gender, Rating, Expertise, Rate/hour
- **[COVERED]** Request goes to multiple providers; link inactivates as soon as one confirms — First-accept-wins with automatic sibling-request invalidation — verified end-to-end.
- **[COVERED]** Customer pays booking charge before confirmation; slot released if unpaid after 15 minutes — 15-minute window enforced both inline and by a background sweep job — verified.
- **[PARTIAL]** Track service provider's current location and ETA — Location is logged (provider_location_log) and exposed via a track endpoint / tracking screen using REST polling. A live WebSocket push channel for real-time updates was not built this pass (documented as a follow-up in docs/api-contract.md).
- **[COVERED]** Enter Reference Code received from a Business Partner
- **[STUBBED]** Facial recognition checks provider location + face before OTP is sent to the customer — integrations/faceMatch.js always returns a match (mock). The geofence/location check is real (haversine distance against the booking address).
- **[COVERED]** Customer receives OTP as soon as provider starts service; timer starts post-verification — Verified end-to-end against the live backend.
- **[COVERED]** Service completion message to customer — total amount, start/end time, total hours; multi-day amounts accumulate — Verified, including the multi-day accumulation case.
- **[COVERED]** Cancellation — no refund if cancelled <24h before start; 50% fee if cancelled 24–36h before start — backend/src/services/cancellationPolicy.js — verified against all three tiers (full refund / 50% fee / no refund).
- **[COVERED]** View all Past, Current and Future appointments
- **[COVERED]** Rate Service Provider and enter comments — Verified end-to-end.

### 2026-09-09 pass
- **[COVERED]** Link to Terms & Conditions and Privacy Policy, with an "I agree" checkbox gating the registration "Continue" button — Backend: `POST /customers/me/accept-terms` stamps `terms_privacy_accepted_at`. The actual client-supplied T&C/Privacy Policy .docx content is extracted and rendered as in-app screens (`customer-app-web/src/data/legalContent.ts` + `LegalContent.tsx`), linked from the agree step; Continue is disabled until checked.
- **[COVERED]** Provision to link a Customer with a Service Provider, up to 10 — `customer_provider_links` table, `GET/POST/DELETE /customers/me/linked-providers`, capped at 10 (422 `DATA_LIMIT`) with a 409 on a duplicate link. Prototype: "My Providers" section on Profile + an add/remove toggle on the Provider Detail screen, showing an n/10 counter.

## Service Provider

- **[PARTIAL]** Register with ID (auto), Freelancer/Organization, Name/Org Name, Photo, Gender, DOB, Mobile, Email, Address+map, Work Days, per-day preferred time, Hourly rate, Aadhar/Police/Work-Certificate upload, Set 6-digit PIN — Every field is captured except the map itself is a placeholder (same caveat as the customer address requirement above) — everything else in this bullet is fully implemented and verified, including the document uploads and 6-digit PIN.
- **[COVERED]** Login using 6-digit PIN — Device-binding is also enforced — a login from a second device is rejected (verified).
- **[COVERED]** Reset OTP provision
- **[COVERED]** Registration fee payment → account activation after Admin approval — Full flow modeled: pay (stub) → pending → Admin approves → active. Payment itself is stubbed (see integrations/payment.js).
- **[COVERED]** Accept service request — Verified end-to-end.
- **[COVERED]** Transfer accepted request to another provider, with accept/reject for the receiver
- **[COVERED]** Calendar updates automatically on accept or transfer
- **[COVERED]** Block calendar so blocked time is hidden from customer search — Verified — search excludes blocked slots.
- **[COVERED]** View calendar of appointments and free slots
- **[COVERED]** Start and end service (daily or multi-day), computing fee amount — Verified, including multi-day amount accumulation.
- **[PARTIAL]** Send customer a "running late — 10/15/30 minutes" message — The message is persisted and delivered to the customer's booking record. No real push-notification channel was wired (it's a clear integration point, not a mocked function, since the requirement doesn't need a 3rd-party API — just a notification transport).
- **[STUBBED]** "Show Direction" button — provider location → customer location — integrations/maps.js stub; UI shows a placeholder route. Real Google Maps Platform integration is a one-file swap.
- **[COVERED]** Provider linked to a unique mobile device identifier; one account cannot be open on two mobiles — device_id binding enforced at login — verified a mismatched-device login is rejected.
- **[COVERED]** Appointments section — past and future
- **[COVERED]** Provider can accept a request only when location is "on" — Verified.
- **[COVERED]** Dashboard — Appointments by Employee; Total Revenue by Employee; Pending Amount by Employee (Today/Week/Month/Quarter/Annual) — Organization accounts see the full per-employee breakdown with a period selector; freelancer accounts see the equivalent personal view.
- **[COVERED]** Schedule Overview page — Organization Head views all employees' schedules by date, with transfer capability
- **[PARTIAL]** Organization: add Employees — Photo, Name, Gender, Mobile, Address+map, Work day/time preference, Distance-from-home preference, Distance-from-office preference — All fields covered except the map is a placeholder, same caveat as above.

### 2026-09-09 pass
- **[COVERED]** Upload Police Verification with Effective From – To Date — `service_providers.police_verification_url/_valid_from/_valid_to`; editable via `PUT /providers/me`.
- **[COVERED]** Upload Medical Certificate with Effective From – To Date — `service_providers.medical_certificate_url/_valid_from/_valid_to`; new document type, editable the same way.
- **[COVERED]** Hourly rate — set a rate, or mark "No Fees" (donated/volunteer service) — `service_providers.no_fees` boolean; the app greys out the rate field when No Fees is on.
- **[COVERED]** Time Bank — provider views their total donated hours — `GET /providers/me/time-bank` returns total hours, total points, and a per-session ledger (`time_bank_ledger`); new Time Bank screen in the prototype.
- **[COVERED]** Payment — mark Receive Full Amount or Part Payment, enter the amount, with the remaining amount shown alongside — `POST /providers/me/bookings/:id/payments`, body `{amount, paymentType}`; `bookings.amount_due/amount_received/payment_status` computed server-side, remaining amount returned and displayed live in the app.
- **[PARTIAL]** Payment — send a reminder to the Customer for the remaining amount — `POST /providers/me/bookings/:id/payment-reminder` records the reminder timestamp and returns the remaining amount; delivery is a stub notification (same integration-point caveat as "running late" above — a real deployment wires push/SMS here).
- **[COVERED]** Feedback on Customer — rating + comments — `customer_ratings` table (mirrors the existing provider-ratings table with roles reversed), `POST /providers/me/bookings/:id/rate-customer`, one rating per booking (409 `ALREADY_RATED`), rolled up into `customers.rating_avg/rating_count`.
- **[COVERED]** Organization: "Allocate Employee" option — when on, only the organization's name is shown in customer search/results and the request routes to the organization; individual employees are hidden — `service_providers.allocate_via_org`; `services/providerMatching.js` excludes that org's `org_employee` rows and surfaces the org itself (matched when any approved/active employee has the right expertise + work-hours for the requested day/time — verified live: employee hidden, org shown, in both `allocate_via_org=false` and `=true` states).
- **[PARTIAL]** Organization: allocate a request to an employee for hours, multiple days, multiple dates with specific hours — `POST /providers/me/bookings/:id/allocate` assigns one employee (`bookings.assigned_employee_id`) to the whole booking; a per-day/per-hours breakdown within one booking was not modeled (documented simplification, consistent with the rest of this build's booking model, which is date-range + one time window per booking, not a per-day schedule).
- **[COVERED]** Organization: transfer a request from one employee to another — `POST /providers/me/bookings/:id/reallocate`; immediate (no accept/reject step, unlike a cross-provider `/transfer`), since it's entirely within the org admin's own authority.
- **[COVERED]** Organization: cancel a request — `POST /providers/me/bookings/:id/org-cancel`; same cancellation-fee-tier logic as the customer-initiated cancel, recorded with `cancelled_by_type='provider'`.
- **[COVERED]** Organization: check utilization of employees — business done, customer rating, pending payment from customer, per employee — `GET /providers/me/utilization`; verified against live seeded/booked data.
- **[COVERED]** *(req. #31)* Organization: set a Service Fee per service, overriding each employee's own hourly rate, at the organization level — `organization_service_fees` table (per org + service_type); `services/pricing.js#computeOrgBilling` uses the org's fee when set, else falls back to the employee's own `hourly_rate`.
- **[COVERED]** Organization: mark an employee Active or Blocked — `PATCH /providers/employees/:id/status`, org-scoped (distinct from the platform Admin's own block/unblock) — verified live.
- **[COVERED]** Organization: edit an employee's Photo, Name, Gender, Mobile, Address, Work day/time preference, Distance-from-home/-office preference — `PUT /providers/employees/:id`.

## Business Agent

- **[COVERED]** Admin registers a Business Agent — ID (auto), Entity Name, Partner Name, 2 Contact Numbers, Email, Address, Set OTP
- **[PARTIAL]** Business Partner login using User ID/Password or set OTP — Password login is fully wired in the Admin/Business Partner portal UI. The backend also implements OTP login per the API contract, but the portal's login screen doesn't yet expose the OTP option — noted in admin-portal/README.md.
- **[COVERED]** Reset OTP provision — Implemented on the backend.
- **[COVERED]** Business Partner refers a Customer — Name, Gender, Service type, Duration (start/end), Time (from/to), Mobile, Address — Verified end-to-end, including generation of a referral code.
- **[COVERED]** Business Partner revenue = flat rate/hour (per service type, set by Admin) × hours used by the referred customer — Verified against the worked example in the requirements doc (₹20/hr Companion × 20 hours = ₹400).
- **[COVERED]** Business Partner views own references and revenue earned

## Admin (Web Portal)

- **[COVERED]** Register Service Provider (same field set as provider self-registration) with Blocked/Active status
- **[COVERED]** Approval process — provider visible in customer search only after Admin approval; can be marked "Hold" if incomplete/incorrect — Verified end-to-end.
- **[COVERED]** *(added requirement)* Provision for Admin to block a Customer, Service Provider, or Business Partner; a blocked user of any of the three cannot log in — Customer and Service Provider blocking already existed; **Business Partner block/unblock was added in this pass** (`PUT /admin/business-agents/:id`, `{status: 'active'|'blocked'}`, audited as `AdminBusinessAgentBlock`/`AdminBusinessAgentUnblock`). All three login controllers reject a blocked user with a 403 `FORBIDDEN` error. Verified end-to-end: backend via curl for all three roles (block → login rejected → unblock → login succeeds again, each with a correct audit_log row), and the admin-portal UI specifically for the new Business Partner case (Block/Unblock buttons on the Business Partners screen, confirmed against the live backend).
- **[PARTIAL]** Allocate a Service Provider to a Business-Partner-referred customer based on calendar availability, duration and time set by the Business Partner — Referral capture and revenue calculation are fully implemented. A dedicated "Admin allocates a specific provider to this referral" screen was not built — today the referred customer still goes through the normal search-and-book flow. Flagging this as a genuine gap worth a follow-up if the intent is for Admin (not the customer) to pick the provider.
- **[COVERED]** Configuration — Customer booking amount, Customer annual registration fee, Service Provider annual registration fee
- **[COVERED]** Configuration — Revenue sharing with Service Providers (freelancers), e.g. ₹200/hr charged → provider gets ₹160/hr — Live example calculation shown inline in the Configuration screen as Admin edits the numbers.
- **[COVERED]** Configuration — Business Partner revenue sharing, flat amount per service type
- **[COVERED]** Provision to add Physiotherapy service later — Physiotherapy is already modeled as a first-class 4th service type throughout the schema, API and configuration screens — not deferred.
- **[PARTIAL]** Track the location and movement of all Service Providers — Last-known location is tracked and shown on an Admin "Live Tracking" list/scatter view (provider_location_log). Historical movement is logged in the database but not yet visualized as a trail/path in the UI.
- **[COVERED]** Broadcast Message — create and send mass messages with a picture to Customers and/or Service Providers
- **[COVERED]** Reports — Admin Dashboard: Revenue by City, by Service Type, by Provider — Verified against live seeded data.
- **[COVERED]** Reports — Annual Customer subscription fee split New vs Existing (same-or-different, reflected in renewal)
- **[PARTIAL]** Reports — Annual Provider subscription fee split New vs Existing, depending on number of users they define — The New-vs-Existing split is implemented. A separate fee tier keyed specifically to "number of users" (headcount-based pricing) was not modeled as its own structure — flagged in case that's meant as more than the New/Existing split.
- **[COVERED]** Reports — count of Customers and Service Providers added per day/week/month/quarter/year, plus revenue by city/service/provider — Verified against live seeded data, with a period selector and trend chart.

### 2026-09-09 pass
- **[COVERED]** Organization revenue sharing — Admin sets Sathiyaa's % markup on top of an organization's own per-service fee (e.g. INR 100/hr + 20% shows as INR 120/hr to the customer) — `org_revenue_share_percent` in `app_configuration` (generic `GET/PUT /admin/config`), edited via a dedicated numeric field on the Configuration screen. Distinct from the pre-existing freelancer revenue-sharing (deduction-based, per service_type): this is additive and organization-only. Verified live end-to-end through a full booking (org fee 300/hr → provider payout 300 × hours, customer billed 300 × hours × 1.2).
- **[COVERED]** Time Bank configuration — Admin defines points credited per donated hour, per service, per application year (e.g. Companion 250 pts/hr for 2026, Medical Companion 300 pts/hr for 2026) — `time_bank_config` table, `GET/PUT /admin/time-bank-config` (batch upsert by service_type + year), editable table on the Configuration screen matching the existing revenue-sharing table's UX. Verified live: admin changes a rate, a subsequent donated session picks up the new rate immediately.

## Non-functional requirements

- **[COVERED]** Track all transactions — Device ID, User Name, Location ID, Transaction date, Form name — audit_log table, written automatically by shared middleware on every mutating request — independently re-verified live during this build (confirmed correct attribution to the acting user, not just "system"). Follow-up pass: the customer health-profile sections (Vitals, Medications, Surgery, Allergies, Family) previously only had this on create — edit and (soft) delete were added for all five, each writing its own audit_log row; verified end-to-end against a live backend + MySQL instance, including the family min-1-active-member rule after a soft delete. SQL reference: docs/sql-update-delete-queries.md.
- **[STUBBED]** Phone call to Service Provider must not reveal the provider's name; call routed via a Sathiyaa number only — masked_call_sessions table + an endpoint that returns a virtual number; no real telephony/IVR bridging (e.g. Exotel/Twilio Voice) is integrated.

## Notes from this pass's real-backend verification

The admin portal ships defaulting to a self-contained mock-data mode (`VITE_USE_MOCK` unset ⇒ `true`), which is unaffected by anything below and is what the delivered zip runs out of the box. To verify the new Business Partner block/unblock feature against the *real* backend (not just the mock store), this pass pointed the portal at the live Express API and, in doing so, found and fixed several pre-existing frontend/backend contract bugs that were unrelated to blocking but were blocking real-backend verification of any admin list screen:
- Admin and Business Partner login responses were reshaped incorrectly on the frontend, silently defeating real-backend authentication (fixed).
- Most admin list-fetching functions unwrapped the API response under the wrong key (fixed for Providers, Customers, Business Partners, Revenue Sharing, Broadcasts, Tracking, Audit Log, and Business-Partner Referrals).
- The Providers/Customers "All" status-filter tab was being sent to the backend literally as `status=all`, which matched zero rows (fixed).
- The Configuration screen's flat settings object vs. the backend's array-of-rows shape was reshaped (fixed).
- The Revenue Sharing "save all" batch save didn't match the backend's single-row endpoint; the backend endpoint was rewritten to upsert an array (fixed).
- Not fixed in this pass (flagged, not required for the block feature): the admin Providers list table expects each row to carry nested `expertise`/`addresses`/`work_hours` data that the current `GET /admin/providers` query doesn't join in — the list renders blank against the real backend today. This doesn't affect the shipped (mock-mode) app and is unrelated to the block feature; worth a follow-up pass. The Reports/Growth/Broadcast-create response shapes also have minor real-backend mismatches noted in code comments but not yet reshaped.


## 2026-09-10 pass — Flutter apps brought up to the requirements doc

Built and verified on a local Windows toolchain (Flutter 3.47.3, JDK 21, Android SDK 36 + NDK
28.2, MySQL 8.0.44). `flutter analyze` reports **no issues** in either app, both widget test
suites pass, and both APKs build.

### Bugs found and fixed in the existing code

- `customer_app/lib/screens/linked_providers_screen.dart` was missing its `models.dart` import —
  the customer app **did not compile**.
- `provider_app/lib/screens/time_bank_screen.dart` had the same missing import — the provider app
  **did not compile**.
- `backend/src/db/migrations/002_provider_languages.sql` used `ADD COLUMN IF NOT EXISTS`, which is
  MariaDB-only syntax; migrations failed against MySQL 8, the engine the spec requires. The runner
  already treats `ER_DUP_FIELDNAME` as benign on re-run, so the redundant guard was dropped.
- Both Android configs pinned an NDK version that broke the build against current SDK tooling.
  Neither app has native code, so the pin was removed.

### Customer app — requirements newly covered

- **[COVERED]** Customer Profile create/update of Name, Photo, Age (date-picker), Gender, Blood
  Group, Email, Preferred Languages, Height/Weight/BMI — previously the app displayed these
  read-only with no way to set them. New `basic_details_screen.dart`; photo upload uses
  `image_picker` (camera or gallery); BMI recalculates live and is derived, never stored.
- **[PARTIAL]** Address with Google mapping, Primary & Secondary, at least one mandatory — both
  addresses are now editable and the primary is enforced; the map itself remains a labelled
  placeholder (same Maps-stub caveat as everywhere else).
- **[COVERED]** Preferred mode of communication (Email/Call/SMS) with timeframe — was absent from
  the Flutter model entirely; now captured and shown on the profile.
- **[STUBBED]** Registration Payment via Payment Gateway — new section on the profile; resolves
  through the same payment stub as the backend.
- **[COVERED]** Enter Reference Code received from a Business Partner — new section, validated
  against the known partner codes, removable.
- **[COVERED]** Expand/Collapse Insurance, Family, Allergy, Surgery, Medication, Vital sections —
  the six sections were separate full screens; they are now inline collapsible panels, which is
  what the requirement asks for.
- **[COVERED]** Vitals graph over a selectable duration — `fl_chart` was a declared dependency but
  unused; there is now a trend chart with a metric picker and 7/30/90-day windows.
- **[COVERED]** Create / **update** / delete on Vitals, Medication, Surgery, Allergy, Insurance,
  Family — edit was missing across all six (delete-only); every section now has all three, with
  the 5-record caps and the minimum-one-family-contact rule enforced.
- **[COVERED]** Search by date duration, time and location — search took a service type and a
  single date; it now takes a date range, a daily time window, a chosen address and a radius,
  sorts by distance, and excludes providers already booked in the range.
- **[COVERED]** Cancel booking with the spec's fee tiers — there was no cancellation UI at all.
  The new screen quotes the fee before committing: no refund under 24h, 50% fee between 24h and
  36h, full refund earlier.

### Provider app — requirements newly covered

- **[COVERED]** View calendar of appointments and free slots — new month-grid calendar screen
  showing booked, blocked and non-working days, with per-day appointments and remaining free
  hours computed from the work preference.
- **[COVERED]** Block calendar so blocked time is hidden from customer search — block/unblock date
  ranges from the calendar; blocking refuses to run over existing bookings, and a blocked date
  refuses new accepts.
- **[STUBBED]** "Show Direction" button — new action on the booking detail showing the provider's
  position, the customer's address, straight-line distance and an ETA. Live routing still needs
  the Google Maps integration.
- **[COVERED]** Service Provider can accept a request only when location is 'on' — new location
  toggle on the dashboard; accepting throws while it is off, and the Bookings screen warns.
- **[STUBBED]** Facial recognition checks provider location + face before OTP is sent — new
  pre-start check gating the OTP button. Face matching is the usual stub; the geofence half is
  real haversine arithmetic against the customer's address (0.5 km, matching the backend's
  `START_SERVICE_GEOFENCE_KM`).
- **[COVERED]** Send Customer a "running late — 10/15/30 minutes" message — was a bare boolean
  flag with no way to choose; the provider now picks the interval and it travels with the message.
- **[COVERED]** Dashboard — Appointments / Total Revenue / Pending Amount by Employee for
  Today/Week/Month/Quarter/Annual — the period dropdown existed but **every figure ignored it**.
  All figures now filter by the selected period, with a per-employee breakdown for organizations.

### Still open after this pass

- ~~Neither Flutter app talks to the Express API.~~ **Done — see the 2026-09-10 (later) pass
  below.**
- Maps, payment gateway, facial recognition, push notifications and masked calling remain the same
  four documented integration stubs.
- Encryption at rest / in motion is still a deployment-layer concern, not implemented in app code.
- Admin allocation of a provider to a Business-Partner referral is still unbuilt (see the Admin
  section above).


## 2026-09-10 pass (later) — Flutter apps wired to the live API

Both apps now run against either the built-in demo data or the real Express + MySQL backend,
chosen in-app and remembered between launches. A fresh install still starts on demo data, so the
APK works with no server; switching to **Live Sathiyaa server** and entering the machine's
address moves the same screens onto real accounts and real rows in MySQL.

### How it is put together

- `lib/backend.dart` — one interface (`SathiyaaBackend` / `SathiyaaProviderBackend`) that every
  screen talks to through `Backend.instance`, plus the mode switch and the persisted server URL.
- `lib/mock_data.dart` — the offline implementation (unchanged behaviour, now `implements` the
  interface).
- `lib/api/api_client.dart` — JSON + JWT over HTTP, with the device id on every request so the
  backend's `audit_log` attribution keeps working, and the server's `{error:{code,message}}`
  envelope surfaced as a typed `ApiException`.
- `lib/api/api_backend.dart` — the live implementation against `docs/api-contract.md`.

No screen knows which backend it is using.

### Model corrections found by wiring it up

- **Vitals were modelled wrongly.** The Flutter apps bundled BP + SpO2 + Pulse + Glucose into one
  record, but the backend stores one row per metric (`customer_vitals.vital_type`). The cap of 5
  records therefore meant two different things in the two places. The Flutter model now matches
  the backend: one reading = one vital type, which also makes the trend graph a per-metric graph.
- **The OTP field was too short to use.** The mock issued 4-digit OTPs and both apps' entry fields
  capped at 4 characters; the backend issues 6. A real OTP could not have been typed in. Both now
  use 6.
- **Provider registration sent the wrong shape.** `POST /auth/provider/register` takes an
  `addresses` array, and silently ignores `noFees`, the medical-certificate fields and the
  police-verification validity dates. The client now sends the right shape and backfills the
  ignored fields through `PUT /providers/me` immediately afterwards.

### Verified against a live server

`test/api_backend_test.dart` in each app drives the real HTTP layer against a running backend,
and skips itself when nothing is listening so `flutter test` still passes on a machine with no
server. Currently **7 customer + 12 provider live tests pass**, alongside the offline suites
(36 tests in total across both apps).

Customer, end to end against MySQL: register → OTP → profile save with the server computing BMI
from height/weight → both addresses → the 5-record cap refused server-side with `DATA_LIMIT` and
freed again by a delete → per-metric vitals round-tripped → provider search with distance ranking
→ link/unlink capped at 10 → booking created and read back.

Provider: registration (arriving `approval_status='pending'`, as the spec requires) → PIN login
→ wrong PIN rejected → **device binding rejected a second phone with the correct PIN** → location
toggle and position ping → accept refused while location is off → calendar block/unblock → free
hours derived from the registered work window.

### Still open after this pass

- Maps, payment gateway, facial recognition, push notifications and masked calling remain the
  same four documented integration stubs.
- ~~Photo upload has no home.~~ **Closed** — `POST /uploads` now stores photos, prescriptions and
  all four provider documents and returns a served URL; the apps upload on save and store the URL.
- ~~Provider calendar blocks are not re-read from the server.~~ **Closed** —
  `GET /providers/me/calendar-blocks` added (with an optional `?from=&to=` window), and the
  provider app loads them on every refresh.
- Encryption at rest / in motion is still a deployment-layer concern, not implemented in app code.
- Admin allocation of a provider to a Business-Partner referral is still unbuilt.


## 2026-09-10 pass (third) — uploads and calendar-block listing

Two gaps the API-wiring pass surfaced, now closed on both ends.

### `POST /uploads`

Every upload in the requirements doc is the same operation, so there is one endpoint rather than
eight: customer photo, prescription, provider photo, Aadhar, police verification, work
certificate, medical certificate, broadcast image. It stores the file and returns a URL, which
the caller writes into the relevant `*_url` column.

- Categories are validated; accepted types are JPEG/PNG/WebP/HEIC/PDF; the cap is 8 MB.
- Stored filenames are random, so a name never reveals whose file it is.
- Served back from `/uploads/...` with `X-Content-Type-Options: nosniff`.
- Local disk by default (`UPLOAD_DIR` moves it). Swapping to S3/Azure Blob is a change inside
  `controllers/uploadController.js` alone — callers only ever see a URL.
- **[COVERED]** Customer "Upload Photo — mandatory": the app now uploads on save and stores the
  URL, so a photo survives a reinstall and is visible from any device.
- **[COVERED]** Medication "prescription upload facility": attach a prescription image from the
  medication dialog; editing a medication without touching the prescription re-uses the existing
  URL rather than re-uploading.

### `GET /providers/me/calendar-blocks`

Returns `{calendarBlocks:[{id, blockStart, blockEnd, reason, createdAt}]}`, with an optional
`?from=&to=` window; with none, everything from today onwards. `POST` now echoes the created row
back instead of just an id. The provider app loads blocks on every refresh, so a block made on
one device shows up on another.

### A bug this pass caught

`http.MultipartFile.fromPath` does not infer a content type — every upload was arriving as
`application/octet-stream` and being refused. The client now derives the type from the file
extension. Found by the new integration test, not in production.

### Verified

- 20/20 on a Node smoke script against the live API: upload round trip (bytes served back
  byte-identical), the URL stored on and read back from a profile, PDF documents, and the
  rejections — unsupported type, unknown category, over-size, anonymous. Plus calendar blocks:
  empty list, create, list, date-window filtering both ways, delete, and **scoping** (one
  provider cannot see another's blocks).
- **39 Flutter tests pass** across both apps (17 customer, 22 provider), including new live tests
  that upload a real PNG and assert the local path does *not* survive, attach a prescription, and
  prove a second client sees a calendar block created by the first.

## 2026-09-10 pass (fourth) — integrations built but switched off, and business numbers set

The brief for this pass: write the real third-party integrations now, leave them
inactive until accounts exist, and keep the whole platform free to run in the
meantime. Also: Android only for now, Azure as the cloud, and set the business
numbers rather than leaving placeholders.

### Integrations — finished code, stub still running

Each integration is now a selector with two implementations behind it. The stub
is the default, so nothing is charged, sent or called out to; naming a provider
switches the same call sites to the real service.

| Integration | Real adapter | Turn on with |
|---|---|---|
| Payments | Razorpay — orders, HMAC signature verification, refunds, webhook validation | `PAYMENT_PROVIDER=razorpay` |
| SMS / OTP | MSG91 and Twilio | `SMS_PROVIDER=msg91` or `twilio` |
| Face matching | Azure AI Face — detect + verify, thresholded | `FACE_PROVIDER=azure` |
| Maps | Google — Geocoding and Directions with live traffic | `MAPS_PROVIDER=google` |
| Push | FCM HTTP v1 — service-account JWT, token cached | `PUSH_PROVIDER=fcm` |
| Masked calls | Exotel — two-leg bridge, neither real number returned | `CALL_PROVIDER=exotel` |

None of them needs an SDK; all use the providers' REST APIs, so there is nothing
extra to install or keep patched.

- **The server reports its own state at startup** and **refuses to boot** if a
  provider is selected without its credentials, naming the missing variable. A
  half-configured payment gateway fails at boot, not when a customer taps Pay.
- **[COVERED]** *(was PARTIAL)* Running-late and payment-reminder notifications
  now go through `integrations/push.js`, and admin broadcasts fan out to active
  customers and/or providers by audience. Behaviour is unchanged until FCM is
  enabled, but delivery is no longer a dead end.
- **Azure** is the chosen cloud: its Face API authenticates with a plain header
  (no request signing, so no SDK), Azure Database for MySQL is a drop-in for the
  current schema, and App Service + Static Web Apps map onto the Express + React
  split. AWS Rekognition would need `@aws-sdk/client-rekognition` for SigV4; the
  adapter's shape would be identical.

**Two integrations have a waiting period, not just a signup.** Indian
transactional SMS needs DLT registration of the sender id and every template
(1-2 weeks). Azure Face verification is Limited Access and needs an approved
application. Both are business processes; neither is a code change.

### Business numbers set

Working assumptions for urban India, documented in `backend/src/db/seed.js` with
their reasoning, and editable by Admin without a deploy.

| Service | Customer/hr | Provider/hr | Sathiyaa | Partner/hr | Net on a referred booking |
|---|---:|---:|---:|---:|---:|
| Companion | 200 | 150 | 50 | 20 | 30 |
| Medical Companion | 300 | 225 | 75 | 30 | 45 |
| Nurse | 450 | 340 | 110 | 45 | 65 |
| Physiotherapy | 600 | 450 | 150 | 60 | 90 |

Providers keep 75%, which is what comparable Indian platforms pay and what makes
joining worthwhile: a companion working six hours a day, 25 days, takes home
about INR 22,500 a month — more than agency-employed attendants earn.

**This corrected a real flaw.** The previous rates were 200/160/40 for Companion:
a Sathiyaa margin of 40 and a Business Partner payout of 40, so **every
partner-referred booking earned Sathiyaa exactly nothing**, and the better the
partner channel performed the worse the economics got. Partner rates now follow
the requirements doc's own example (INR 20/hr for Companion), leaving a 15%
margin on referred bookings.

Fees: booking charge INR 99; customer annual 499 new / 399 renewal; provider
annual **599 new / 499 renewal**, lowered from 999/699 — in a two-sided
marketplace supply is the scarce side, and a large upfront fee on a caregiver who
has not earned anything yet costs more in lost supply than it raises. Organization
markup stays at 20%, from the doc's worked example.

The same figures are now used by the backend seed, the admin portal's demo data
and the Flutter demo data, which had drifted apart.

### Another seeding bug found

`npm run seed` failed on any second run: `time_bank_config` and five other tables
added by migrations 003-005 were never added to the seed's truncate list, so the
second run hit a duplicate key. Fixed and verified by seeding twice in a row.

### Admin portal deployed

`admin-portal/build-single-file.mjs` inlines the script, styles and logo into one
self-contained HTML file that runs from any URL with no server. Published as a
private artifact so it opens on a phone. It builds in demo-data mode on purpose:
a hosted page cannot reach an API on someone's own machine, so the deployed copy
is the clickable demo and the local build is what talks to the real backend.

### Still open

- Push needs a `device_tokens` table before it can reach an actual device; that
  needs the Flutter side to have a token to register.
- Maps, payments, face matching and masked calls are complete but inactive,
  awaiting accounts.
- iOS is not scaffolded — Android only by decision, iOS in a later pass.
- Encryption at rest / in motion remains a deployment-layer concern.
- Admin allocation of a provider to a Business-Partner referral is still unbuilt.


## 2026-09-10 pass (fifth) — making the three surfaces work together

The question this pass answered: can a customer on one phone, a provider on
another and an admin on a laptop actually run a booking between them? Not
"does each app compile", but does the loop close.

It did not, for four reasons. All four are now fixed and covered by a test that
drives the API exactly as three separate devices would
(`smoke/three-devices.mjs`, **30/30**).

### Bugs found by trying the whole loop

- **`GET /admin/providers` was returning `pin_hash`.** A provider's login
  credential, sent to the browser on every admin page load. The query now names
  its columns instead of `SELECT *`, so a future migration cannot silently
  reintroduce it. Customers and Business Partners were checked too and are
  clean.
- **`GET /admin/providers` returned no nested detail**, so the console's
  directory and detail drawer rendered blank against the real backend — which
  meant **no provider could be approved, and an unapproved provider never
  appears in customer search**. That single gap broke the entire loop. Expertise,
  addresses and work hours are now attached with three grouped queries, so the
  cost stays flat as the directory grows.
- **Provider registration accepted a `deviceId` and dropped it.** The account
  stayed unbound until its first PIN login, so until then *any* device with the
  right PIN could claim it — the spec's "one user cannot have his application
  open on two mobiles" was not actually enforced for newly registered
  providers. Now bound at registration.
- **Running-late crashed with a 500.** The push import added in the previous
  pass never landed — its anchor did not match — so the handler referenced an
  undefined module. Caught here rather than by a provider on a doorstep.

### New: releasing a bound device

Binding an account to one handset has an obvious failure mode: a lost, wiped or
replaced phone locks the provider out permanently. `POST
/admin/providers/:id/reset-device` clears the binding, with a **Release device**
button in the console (shown only where an account is actually bound). It is an
admin action on purpose — self-service would defeat the binding.

### The rest of the console's real-backend contract

A field-by-field sweep (`smoke/admin-contract.mjs`, **23/23**) now asserts that
every key each screen reads is present, so an empty page is caught here rather
than by someone staring at one. It found and fixed:

- **Reports crashed** on `undefined.toLocaleString` — the endpoint groups
  revenue as `byCity`/`byServiceType`/`byProvider` and carries no headline
  totals. Reshaped in the service layer, with totals derived from the same rows
  the charts draw so a tile can never disagree with its chart.
- **Growth** returns two independent series keyed by bucket; they are now zipped
  across the union of buckets rather than assuming both cover the same range.
- **Live Tracking crashed** on `undefined.map` — the map labels each pin with
  the provider's services and the endpoint did not return them. Added, and the
  label now tolerates a provider with none recorded.
- **Business Partners showed "Invalid Date"** — `created_at` was not selected.
  Added, along with the second contact number and address the screen reads.
- **The "All" status tab matched nothing**, because `status=all` was passed to
  SQL as a literal. Now treated as no filter, on both providers and customers.
- The customers directory renders a city that nothing supplied; joined from the
  primary address.

### Deployed

The admin console is published as a private artifact and rebuilt with all of the
above. It ships in demo-data mode by necessity — a page hosted elsewhere cannot
reach an API on someone's own machine — so the local build remains the one that
talks to the real database. `_builds/TESTING-ON-PHONES.md` documents both, plus
the three behaviours that look like bugs and are not: device binding, the
approval gate before a provider becomes visible, and no SMS arriving.

### Still open

- Push needs a `device_tokens` table before a notification can reach a handset.
- Payments, SMS, maps, face matching and masked calls are complete but inactive,
  awaiting accounts.
- iOS is not scaffolded — Android only by decision.
- Encryption at rest / in motion remains a deployment-layer concern.
- Admin allocation of a provider to a Business-Partner referral is still unbuilt.
- Business Partner OTP login exists in the backend but the login form only
  offers password.


## 2026-09-10 pass (sixth) — bugs found by actually using it on a phone

Four failures reported from real use, all reproduced and fixed. Every one of
them was invisible to the existing tests because the tests drove the API
directly and never went through a screen.

### The customer could never pay for a booking

**The most serious of the four.** Against the real backend a new booking has
status `searching`: the request has fanned out to every matching provider and
nobody has accepted. It only becomes `pending_payment` once someone accepts,
and only then does the spec's 15-minute window start.

The app skipped that phase entirely — it created the booking, immediately
showed a Pay button and a countdown, and the server refused the payment with
`Cannot pay a booking in status searching`. The offline demo *did* allow it,
which is why this was never noticed: the two modes disagreed about the rules.

Fixed on both sides so they now agree:

- `BookingStatus` gained `searching`, and the live client maps it rather than
  mislabelling it as `pendingPayment`.
- The confirm screen is now a waiting screen first — spinner, how many
  providers were asked, and a Cancel request button — which turns into the
  payment card with the countdown the moment somebody accepts. It polls every
  three seconds.
- The offline backend models the same phase (a provider "accepts" after a few
  seconds, since there is no second phone) and **refuses early payment the same
  way the server does**, so a flow that works in demo mode works live.
- Appointments shows searching bookings under Current, cancellable, with
  readable status labels instead of enum names.

### Provider registration hung forever

`completeRegistration` had no error handling. Any failure — a mobile number
already registered, an unreachable server — left `busy = true` and the spinner
ran indefinitely with no message. Now the failure is caught and shown.

The same screen also force-set `approvalStatus = 'active'` after registering,
which against a live server is simply false: the account is `pending` until an
admin approves it. That claim is now made only in demo mode; live registration
says an administrator has to approve before customers can find you.

### The admin console could not be signed into

The login form was **pre-filled** with `admin@sathiyaa.example` / `admin1234`
and `BP-000001` / `partner1234`. Those work in demo mode, where any 4+
character password is accepted. Against a real server they are simply wrong
credentials — so clicking Sign in produced a 404 (no such admin) and a 422
(incorrect password) for the partner tab.

- The fields are now empty in live mode, with placeholders and a line naming
  the server being talked to and the seeded account.
- **Errors now carry the server's own wording.** Axios reported "Request failed
  with status code 404", which explains nothing; the API always replies with
  `{error:{code,message}}` and that is what the screen shows. The same login
  now says "Incorrect password".

### "Test connection" reported an error on a healthy server

The check called the provider-search endpoint with only `service_type`, so a
perfectly healthy server answered "service_type and date_from are required" —
which reads like a failure when it is proof of the opposite. It now calls the
server's own `/health` endpoint, which needs no parameters and no sign-in, and
distinguishes "reached something that is not Sathiyaa" from "could not reach
the address at all".

### Also, from the same session

- **Sessions did not survive an app restart.** The token was held in memory
  only, so every launch demanded a fresh OTP (customer) or PIN (provider).
  Tokens are now persisted and restored, and validated against the server
  before being trusted; an unreachable server starts you signed out rather than
  hanging. Persistence is injected into `ApiBackend` rather than reached for
  directly, so it stays a pure API client.
- **The provider app's start-up check tested for `approvalStatus == 'active'`,
  a value the real backend never returns** (it uses pending/approved/hold/
  rejected). Against a live server an approved provider was sent back to the
  Welcome screen. Being signed in is now enough to enter the app; approval
  gates appearing in customer search, not opening the app.
- A restored customer session that had not yet accepted the Terms was sent to
  Welcome, where registering again failed with "mobile already registered". It
  now resumes at the Terms gate.
- PowerShell scripts were UTF-8 without a BOM, which PowerShell 5.1 reads as
  ANSI — em-dashes broke parsing outright. Scripts are ASCII, and `.cmd`
  wrappers avoid the execution-policy block entirely.

### Verified

93 backend checks and 44 Flutter tests, both apps clean on `flutter analyze`.
New coverage for the searching phase in both modes, and for session restore.
Admin and Business Partner logins were driven through a real browser against
the real backend, including a deliberate wrong password to confirm the message.
