# Sathiyaa Admin & Business Partner Portal

React + TypeScript (Vite) web app for the Sathiyaa home-healthcare booking
platform. One app, two roles: **Admin** gets the full console; **Business
Partner** gets a scoped referrals/revenue view. Shared sidebar/header chrome,
nav items gated by role.

## Quick start

```bash
npm install
cp .env.example .env   # already defaults to mock mode, see below
npm run dev             # http://localhost:5173
```

Login screen has two tabs (Admin / Business Partner). In mock mode any
non-empty password of 4+ characters signs you in — try the business partner
IDs `BP-000001`..`BP-000004` shown as a hint on the login card.

```bash
npm run build   # tsc -b && vite build — zero TypeScript errors
npm run preview # serve the production build locally
```

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `VITE_API_BASE_URL` | `http://localhost:4000/api/v1` | Base URL of the real backend (see `../docs/api-contract.md`). |
| `VITE_USE_MOCK` | `true` | When `true` (default), the entire app runs against an in-memory mock data layer instead of the network — fully clickable and populated with no backend running. Set to `false` to talk to the real backend. |

## Mock mode vs. real backend mode

- **`src/api/mockData.ts`** — deterministic, realistic seed data: 14 service
  providers spanning pending/hold/approved/rejected/blocked states, 26
  customers, 4 business partners with 21 referrals across several months,
  90 audit log entries, revenue-sharing config for all four service types,
  broadcast history, and a growth/reports dataset. Avatars, document scans,
  and broadcast images are generated locally as SVG data-URIs
  (`src/utils/placeholder.ts`) — no external image host, so the app looks
  fully populated and stays console-clean even fully offline.
- **`src/api/mockStore.ts`** — a mutable in-memory clone of that seed data.
  Actions taken in the UI (approve/hold/block a provider, register a
  business partner, submit a referral, save configuration, send a
  broadcast...) mutate this store and an audit-log row is appended, so the
  demo stays internally consistent for the rest of the browser session.
  Refreshing the page resets it back to the seed data.
- **`src/api/services.ts`** — the single API surface every screen calls
  (`listProviders`, `approveProvider`, `getReportsDashboard`, ...). Each
  function branches on `VITE_USE_MOCK`: `true` reads/writes the mock store
  with a simulated network delay (so loading skeletons are visible);
  `false` calls the real backend through `src/api/client.ts` (an axios
  instance with the JWT bearer token attached from `localStorage`,
  base URL from `VITE_API_BASE_URL`, and a 401 interceptor that clears
  the session and redirects to `/login`), hitting the exact paths in
  `../docs/api-contract.md`.

Switching to `VITE_USE_MOCK=false` requires no code changes elsewhere —
every page already calls through `services.ts`.

## Screens

**Admin**
- Login (`/login`)
- Service Providers — approval queue, directory and sign-up in one
  (`/admin/providers`): filter by approval status, search, view full
  profile (photo, Aadhaar / police verification / work certificate as
  view/download links, work days & hours, hourly rate, distance
  preferences), Approve / Put on Hold (with required note) / Block (with
  required note) / Unblock / Release device, all with confirmation dialogs.

  **Add provider** opens a five-step form — named and ordered exactly like
  the provider app's own registration, so staff reading answers off a paper
  form are asked for the same things in the same order. It uploads the
  documents, finds the address on a map, sets a sign-in PIN shown once, and
  the provider can then sign in on their own handset immediately. See
  `AddProviderDialog.tsx`; the server does the validating and answers with a
  per-field error map.
- Customers — searchable/sortable directory with block/unblock
  (`/admin/customers`)
- Business Partners — list, register new partner (entity, partner name, 2
  contacts, email, address), view a partner's referrals and revenue earned,
  block/unblock (`/admin/business-agents`)
- Configuration — booking amount, customer/provider annual fees (new vs.
  existing, with a "same for both" toggle), and revenue sharing per service
  type (customer rate / provider rate / business-partner flat rate) with a
  live inline example calculation ("if used for 20 hours → ...")
  (`/admin/configuration`)
- Reports — revenue by city / service type / provider (charts + tables),
  new customers & providers with a day/week/month/quarter/year period
  selector and trend chart (`/admin/reports`, recharts)
- Broadcast — compose title/message/image, pick audience, send, view send
  history (`/admin/broadcast`)
- Live Tracking — stat tiles, a labeled provider list, and a lightweight
  SVG scatter "map" (lat/lng projected to an SVG viewport, colored by
  available/on-booking/offline) with 15s auto-refresh polling, matching the
  REST-polling approach in the API contract (`/admin/tracking`)
- Audit Log — filterable by user type, form name, and date range
  (`/admin/audit-log`)

**Business Partner**
- Login (shared screen, "Business Partner" tab)
- My Referrals — list + "Refer a Customer" form, shows the generated
  referral code on success (`/partner/referrals`)
- My Revenue — totals, earnings-over-time chart, per-referral breakdown
  (hours used × flat rate) (`/partner/revenue`)

## What's implemented vs. simplified

- **Live tracking map** is a hand-rolled SVG scatter plot, not a real map
  tile layer — the task explicitly allows this ("a labeled list ... your
  call"). It projects providers' lat/lng into an SVG viewport and colors
  them by status; swapping in Leaflet + an OSM tile layer later is a
  contained change inside `src/pages/admin/Tracking.tsx`.
- **OTP login** for Business Partners is described in the contract
  (mobile + OTP) but only user-id/password is wired into the login form,
  per the "Or sign in with mobile + OTP ... not shown in this demo" note —
  the backend endpoint exists in the contract for when it's needed.
- **Unblock** endpoints (for providers, customers, and business partners)
  aren't explicit line items in `api-contract.md` (`block`/`approve`/`hold`
  are); the directories need it, so mock mode implements it and real-backend
  mode calls a same-shaped `POST .../unblock` — confirm/adjust that path
  name against the backend once it exists.
- **File uploads** (provider documents, broadcast image) are handled
  client-side only in mock mode (`FileReader` → data URI preview); a real
  backend integration would need multipart upload endpoints, which aren't
  in the current contract.
- Revenue-sharing "effective_from" dating and historical rate versioning
  (the schema supports multiple dated rows per service type) is simplified
  to "one current row per service type" in the Configuration screen, which
  matches what the screen needs to show today.
- Growth report bucketing (day/week/month/quarter/year) and reports
  dashboard totals are randomly generated but internally consistent mock
  data — real numbers will come from `/admin/reports/*` once the backend
  is live.

## Project structure

```
src/
  api/          client.ts (axios + mock toggle), services.ts (API surface),
                mockData.ts (seed data), mockStore.ts (mutable mock state)
  components/   Layout.tsx (sidebar/header), ui.tsx (badges, modals, states),
                ProtectedRoute.tsx (role-gated routing)
  context/      AuthContext.tsx
  pages/admin/  ServiceProviders (+ AddProviderDialog), Customers,
                BusinessAgents, Configuration, Reports, Broadcast, Tracking,
                Devices, AuditLog
  pages/partner/ MyReferrals, MyRevenue
  types/        TypeScript types mirroring the API's shapes. Read endpoints
                hand back database rows (snake_case); write endpoints take
                camelCase, the same shape the apps send. Each type names its
                fields the way that endpoint actually names them.
  utils/        placeholder.ts (locally-generated avatar/doc/banner SVGs)
```
