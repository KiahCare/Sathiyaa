# Walkthrough audit — 17 September 2026
*Updated 21 September. The numbered list has been empty since the 19th; what
follows is work you asked for since. A customer can now pick which carers get
asked rather than the request quietly going to everyone. The papers step in
provider registration was rebuilt. Vitals no longer clips its own controls. The
tabs move. Demo data covers every screen rather than one of each. And the device
registry, which nothing had ever tested, now has seventeen checks proving it
records what a handset actually reports.*

Every screen of both apps and every page of the web panel, gone through as a
first-time user. Findings are split by what they need, not by where they are,
because the next session should work top-down.

Backend state: **20 scripts, 0 failures, run in full three times in a row**,
each run on a database built from the migrations and dropped afterwards. The
write-heavy scripts no longer have to be skipped, because they no longer touch
anything you care about. A twenty-first script checks the *deployed* configuration
— access key, CORS, rate limiting, preflight, account enumeration — and passes
26 of 26. Live schema 39 tables, migrations 001–011.

    _tests\run-all.ps1            everything, on a throwaway database
    _tests\run-all.ps1 -Flutter   the 64 Flutter tests, same database
    _tests\run-all.ps1 -Public    the AWS configuration, before you deploy

Database, counted back out of a freshly seeded server rather than off the seed
script: 36 providers (31 approved and active), 5 of them giving their time free,
20 customers, 3 partners, 9 bookings. Demo data carries 25 providers of its own,
so the app looks the same size with or without a server.

Apps: **64 Flutter tests passing**, both analyze clean, all 32 screens on one
design system. APKs verified current with `_builds/verify-apks.ps1`.

---

## Fixed on 18 September

| # | What | Where |
|---|---|---|
| 8 | **Home header reduced to the name only** (requested). Greeting, the "how are you feeling" line and the mood row removed. The name now carries the block on its own and steps down in size as it gets longer, rather than wrapping into a cramped second line. | `customer_app/screens/home_screen.dart` |
| 9 | **Search rebuilt.** Care type is four tappable cards rather than a dropdown — it is the choice everything else hangs off. Results carry real avatars, skill tags, distance, languages and rate, with a sort control (nearest / best rated / lowest rate) and an empty state that offers to widen the radius. | `customer_app/screens/search_screen.dart` |
| 10 | **Bookings rebuilt.** Segmented tabs with live counts, status chips, a live pulse while a request is out or a visit is running, per-bucket empty states, skeletons, and the confirm button inline on the card. | `customer_app/screens/appointments_screen.dart` |
| 57 | **The audit log recorded what happened and showed none of it.** Every row read `CreateBooking` and nothing else. The server has always written a JSON payload beside it — the booking id, how many carers were asked, which of them the customer chose — and the endpoint has always returned it; the console simply never rendered the column. There is a **What happened** column now, written as a sentence rather than raw JSON: keys become words, nulls are dropped, and the full value is on the row. | `admin-portal/src/pages/admin/AuditLog.tsx` |
| 56 | **Nothing tested the device registry.** Built on the 19th and never covered, which for a feature whose whole job is to answer "which phone was that?" is the wrong amount of testing. It only works if the app sends the headers, the middleware reads them on every authenticated request, and the admin endpoints join a deliberately unconstrained `user_id` back to the right table. All three do: 17 checks now prove make, model, OS, app version, emulator flag, caller address, first and last seen, the join back to the account, a second handset recorded alongside the first, and one handset shared by two accounts. Two early failures were the test's fault and one was a real race — the write is fire-and-forget, so a test that does not allow for it passes alone and fails in a suite. | `_tests/device-registry.mjs` |
| 55 | **Demo data was one of everything.** Three vitals of a single metric, so three of the four graphs were empty and whoever looked concluded the chart was broken. One booking, so two of three tabs had nothing and the receipt, the rating and the cancellation treatment could not be reached. Every metric now has a short series with a shape to it; bookings cover all three tabs including rated, unrated and cancelled; the provider app gained a visit already running, an unpaid job and blocked days. Dates are relative, because a fixed one is correct for a week and then becomes a booking in the past filed under Future. | `{customer,provider}_app/lib/mock_data.dart` |
| 54 | **The bottom tabs did not move.** The pill fills, the icon lifts as it becomes the selected one with a touch of overshoot so it settles rather than arrives, and the whole thing dips under the finger; the Current/Future/Past tabs got the same press response. Anything louder on a control somebody presses forty times a day stops being feedback. All of it is skipped when the phone asks for reduced motion. | `widgets/sathiyaa_ui.dart`, both apps |
| 53 | **Reading and Duration were cut off under Vitals.** Two dropdowns side by side with about 150px each. A `DropdownButtonFormField` does not shrink its selected item — without `isExpanded` it lays the item out at natural width and the box clips it — so "Blood pressure" and "Last 30 days" were sliced and only the floating labels could be read. Reading is full width; the window became three buttons. | `customer_app/lib/screens/profile_sections.dart` |
| 52 | **The papers step in provider registration.** The one part of either app not on the design system: Material greys on warm paper, and a row holding a thumbnail, a two-line label and an Upload button, which on a 375px phone left the button about forty pixels. It worked and looked broken, which to the person using it is the same thing. Each document is now a card the size of what it asks for, the whole card is the target, and it says what each paper is for. Worth saying plainly: **the upload itself was never broken** — registration sends the files the moment the token arrives. | `provider_app/lib/widgets/document_field.dart`, `screens/auth_screens.dart` |
| 51 | **A customer could not choose who to ask.** The app opened one carer's profile, said *requesting Lakshmi Iyer*, and sent a request the server fanned out to every carer who matched. Neither half was wrong alone; together they were a lie. Search results now carry a tick, a bar says how many are picked, and the waiting screen names them. The shortlist is intersected with who is actually free, so somebody off duty never gets a request they cannot accept and a dropped choice is reported rather than left to wonder about; a carer who was not asked cannot accept, the accept path taking a row lock on the request, which is also what settles the race when two say yes at once. 16 checks. | `backend/src/controllers/bookingController.js`, customer_app search and booking flow |
| 50 | **The booking journey had no progress indicator.** The component had been built and then left unused, which is how it reached the "could be better" list and stayed there. Requested / Accepted / Paid / Visit / Rated now sits on the waiting, confirm, tracking and rating screens. Each of the five is a status the server really sets rather than a stage invented to make a nicer picture, so the stepper and the rest of the screen cannot disagree; the mapping is a switch over the status enum with no default, so a new status breaks the build instead of drawing the wrong step. | `customer_app/lib/screens/booking_flow.dart` |
| 49 | **Both apps opened already signed in.** The last item on the list. Demo data opened as Anita Verma and as Karuna Companion Services, so nobody handed the APK ever saw the welcome screen, the sign-up or the code. Neither seeds a session now; Welcome keeps a one-tap way into the demo account, and a demo sign-in is remembered across restarts the way a live one is. Found on the way: the provider app's skip button walked into the home shell *without* signing in, which the first screen would have answered with a null dereference. | `{customer,provider}_app/lib/{backend, mock_data}.dart`, `splash_and_auth.dart`, `auth_screens.dart` |
| 48 | **The Flutter tests were writing to the live database too.** Found by counting rows, not by reading code: the development database went from 138 customers to 141 while nothing was supposed to be writing to it, and the three new ones were called *Flutter Flow*, *Flutter Booking* and *Parity Tester*. `api_backend_test.dart` has a group that talks to a real server and registers real accounts on it; two runs of `flutter test` had put six customers and six bookings there. `run-all.ps1 -Flutter` runs both suites against the throwaway server instead, passing the address as a `--dart-define` because Dart reads `String.fromEnvironment` at compile time. | `_tests/run-all.ps1`, `{customer,provider}_app/test/api_backend_test.dart` |
| 47 | **The sign-in told strangers who has an account.** A wrong password on the admin sign-in came back `422 Incorrect password`; an address with no account came back `404 No admin account found`. Two different answers, so anyone who could reach the API could work through a list and find out which addresses are administrators. The partner sign-in did the same, and a partner can be looked up four ways. Both now answer `401 INVALID_CREDENTIALS` with the same sentence either way, compare the password against a fixed hash when there is no account so the timing matches too (56ms against 1ms before), and check *blocked* only after the password. Asking for a partner code says "if that account exists, a code has been sent" whichever it is. Customer and provider sign-ins deliberately unchanged: those are the two places a person signs themselves up, and the app has to be able to offer to create an account. | `backend/src/controllers/authController.js` |
| 46 | **The seed left three tables behind.** `npm run seed` clears a list of tables and re-inserts the demo directory; the list had not been updated for migrations 008–011, so `user_devices`, `sos_alerts` and `booking_messages` were never cleared. It clears with foreign key checks off, so nothing complained — the rows stayed, pointing at ids that no longer existed, and the re-insert starts again at 1. A stale emergency alert would reattach itself to whichever customer landed on that id. | `backend/src/db/seed.js` |
| 45 | **Five test scripts printed FAIL and exited 0.** `contact-modes` worked out whether each case passed and discarded the answer; `admin-actions` printed FAIL and never counted; `shapes`, `admin-console-check` and `osm` reported nothing at all — `osm` prints `undefined` and exits 0 on a machine with no internet, which is how "OpenStreetMap is working fine" gets reported. All five count and exit properly now, and the runner checks the printed output as well as the exit code. | `_tests/` |
| 44 | **One run in seven booked on a Sunday.** Seeded carers work Monday to Saturday. `messages` picked a random day 20–60 out to avoid colliding with its own previous run, so roughly one run in seven it matched nobody and failed nine checks that have nothing to do with messages. Every other script already skipped weekends. `booking-for-dependent` was booking on hardcoded December dates, which stop being in the future on 1 January; those are relative now too. | `_tests/messages.mjs`, `_tests/booking-for-dependent.mjs` |
| 43 | **The test suite had nowhere of its own to run.** `run-all.ps1` builds `sathiyaa_test` from the migrations, seeds it, starts a second API on port 4010 pointed at it, runs all eighteen scripts and drops the database. The development database is never touched. The same script points the suite at a deployment with `-Api` and `-Key`, which is how the AWS server gets checked once it is up. | `_tests/run-all.ps1`, `_tests/lib/preamble.mjs`, `_tests/public-config.mjs` |
| 42 | **The test suite only passed on a clean database.** `happy-path` failed whenever `three-devices` had run first — the account it uses was bound to the other script's device, and every step after it cascaded into 401s. `messages` then collided with `happy-path` over a time slot, and once that was fixed, with *itself*: the booking it left confirmed held the slot against the next run. Both now clean up after themselves and pick their own slots. **All 17 scripts pass twice in a row**, which is the property that matters — a suite that only passes on a fresh database tells you nothing on the second deploy. | `_tests/{happy-path, messages}.mjs` |
| 41 | **Re-running the migrations broke.** The runner skips "already exists" errors so it can be run twice safely, but its list did not include `ER_FK_DUP_NAME` — so the second run of migration 009 failed on the foreign key it had just created. On a laptop that is an annoyance; on a deployment where somebody runs `npm run migrate` twice to be sure, it is a failed deploy. | `backend/src/db/migrate.js` |
| 40 | **Messaging, built.** A thread on each booking, the same one read from both ends, with unread badges on the list and the job sheet. Deliberately tied to a booking rather than an open inbox: a customer can message the carer coming to their house and nobody else. That is not a limitation to widen later — an open messaging surface between strangers on a care platform is a safeguarding problem, and the booking is what makes the conversation legitimate. A stranger asking for a thread gets 404, not 403, so bookings cannot be enumerated. 17 checks. | migration 011, `services/messageService.js`, both apps |
| 39 | **SOS now raises a real alert.** The screen always put the right numbers in front of you and said plainly that nothing had been sent, because nothing had. It now records the alert, notifies the family on the account and the carer on any visit in progress, and reports back what actually went out. Two rules: the alert is recorded *before* anything is sent, so a gateway failure cannot lose the fact that somebody pressed the button; and with no SMS provider configured it says `simulated` rather than claiming success — telling somebody their family has been notified when no message left is worse than saying nothing, because it stops them phoning themselves. The office can see every alert and must say what was done before closing one. 16 checks. | migration 010, `services/sosService.js`, `customer_app/screens/sos_screen.dart`, admin endpoints |
| 38 | **Booking for a dependent** (the reference app's "Services for"). The commonest case this app exists for is an adult child in another city arranging care for a parent: they hold the account and they pay, and the carer is visiting somebody else. The carer's job sheet now says who they are visiting, their age, a number to reach them on, and any note — "hard of hearing, knock twice and wait". A family member id that is not yours is refused. 12 checks. | migration 009, both apps |
| 37 | **Device information in the admin panel** *(your item 10)*. We stored one opaque `device_id` per account and nothing else. There is now a registry: make, model, OS version, app version, whether it is a real handset or an emulator, when it was first and last seen, and the address the request came from. Recorded on every authenticated request from one place — `requireAuth` — so a new route group cannot forget it. The console has a **Devices** page with filters, and it flags **one handset under several accounts**, which is the pattern device binding exists to catch. Releasing a device unbinds it and keeps the history, because that history is exactly what somebody comes looking for afterwards. No advertising id and no IMEI. | migration 008, `middleware/deviceRegistry.js`, `admin-portal/pages/admin/Devices.tsx`, both apps |
| 37b | **No way to change the admin password, and no throttling on trying one.** The super-admin password is baked into the seed and written down in the repository, and nothing in the API could change it. Added `scripts/set-admin-password.mjs` for the server, `POST /admin/me/password` for the console, and the seed now reads `ADMIN_EMAIL`/`ADMIN_PASSWORD` from the environment so a deployment does not ship with the published one. Sign-in and code-request endpoints now allow 20 attempts per quarter hour; everything else 600 per five minutes. | `backend/scripts/set-admin-password.mjs`, `controllers/adminController.js`, `middleware/rateLimit.js`, `db/seed.js` |
| 36 | **The backend would have gone onto the internet with a forgeable token and an open CORS policy.** `JWT_SECRET` defaulted to `'dev-secret'` with nothing refusing to boot without it — anyone who has seen the repository could sign a token saying `role=admin`. `cors()` was called with no options, so any origin. Added `config/preflight.js`, which refuses to start when `PUBLIC_DEPLOYMENT=true` and the secret is a placeholder, under 32 characters, or missing; when CORS is unrestricted; or when the API access key is absent. Also helmet, and a proxy-hop setting so rate limiting counts the caller rather than CloudFront. The flag is separate from `NODE_ENV` on purpose: this deployment keeps the on-screen OTP, and that decision must not drag every other development default along with it. | `backend/src/config/{env,preflight}.js`, `src/app.js`, `src/server.js` |
| 35 | **Admin Reports rendered blank on an empty database.** The only page of eleven with no empty handling: Recharts draws axes around nothing, so four panels of blank grid and no explanation. Each chart now says what would appear there and why it is empty. The growth fetch also had no `catch`, so a failed request left the skeleton spinning for ever with nothing said. | `admin-portal/pages/admin/Reports.tsx` |
| 34 | **The demo directory was five people.** A search for a companion returned three results on demo data against twenty-seven on a live server — anyone shown the app without switching to live would have concluded the directory was nearly empty. It is twenty-five now, across all four service types, at real Bengaluru coordinates so the distances in search are plausible; four of them give their time free, roughly the live proportion. | `customer_app/mock_data.dart` |
| 33 | **Three hidden or missing safeguards in the organisation screens.** Blocking a carer was a **long press on the row** — no label, no hint, no confirmation: undiscoverable if you wanted it, a nasty surprise if you hit it by accident. The employee form validated nothing, so a nameless carer with no number could be saved and then allocated to a visit. And it rendered a grey box reading **"Map placeholder"**, a note-to-self left where a user can read it; an employee has no coordinates to draw, so the box is gone rather than faked. | `provider_app/screens/organization/*.dart` |
| 32 | **The provider's checks said "uploaded" even when expired.** A police verification that ran out last month is not on file in any sense that matters. The dates were already stored and never read. Each check now says On file / Expiring / Expired / Not given, with the date and the days left. | `provider_app/screens/profile_screen.dart` |
| 31 | **Log out did not sign out, and the device id was invented.** The provider's log-out set `currentProvider = null` directly instead of calling `signOut()` — on a live server that left the auth token sitting in storage, so the screen said you were logged out and the session was not. The same screen printed the bound device as `PROV-000201-DEV-01`, a string the app makes up; the real id, which is what the server binds the account to and what the admin console shows, was never on screen. It is now, and it is selectable, because support will ask for it. | `provider_app/screens/profile_screen.dart` |
| 30 | **The last six provider screens rebuilt** — profile, calendar, server settings, your carers, the team's day, and how the team is doing. All thirteen are now on the design system. The calendar gained a way back to today after you have paged three months ahead, and the two organisation list screens gained empty states; an organisation that had not added anybody got a blank white screen. | `provider_app/screens/{profile, calendar, server_settings}_screen.dart`, `organization/*.dart` |
| 29 | **Signing out of demo data was a one-way door — in both apps.** The customer's mock store kept one `currentCustomer` and nothing else, so signing out dropped the only reference to the account: logging back in with the same number built a blank "New Customer" and Anita Verma's profile, bookings and health record were gone. The provider's was worse — `loginWithPin` compared the PIN against `currentProvider`, which sign-out had just set to `null`, so *every* PIN answered "Incorrect PIN" forever. Both mock stores now key accounts by mobile number, the way the server does. Registering on a number that already has an account is refused, as the server refuses it. Three regression tests added. | `customer_app/mock_data.dart`, `provider_app/mock_data.dart`, both test suites |
| 28 | **The design sync script was corrupting the provider app's map.** `Get-Content -Raw` reads a BOM-less UTF-8 file as the system codepage in PowerShell 5.1, and `Set-Content -Encoding utf8` then re-encodes the damage and adds a BOM. The provider app has been rendering **`Â© OpenStreetMap`** under every map — the attribution OSM's tile policy requires — along with a mangled em dash in each location message. Reads and writes go through .NET now, and the file is repaired. | `_builds/sync-design.ps1`, `provider_app/widgets/osm_map.dart` |
| 27 | **The map camera did not follow a moved pin.** `initialCenter` is read once and never again, so pressing "Use my current location" on the address form moved the marker and left the camera on the old neighbourhood — the pin slid off the edge of a map showing the wrong place. It follows now, once the map reports it is ready. | `widgets/osm_map.dart`, both apps |
| 26 | **Dates were written `12/4/1958`.** Ambiguous everywhere, and on a health record — a surgery date, when a medicine started, when a policy runs out — not a style question. 29 sites across both apps now go through one shared helper and read `12 Apr 1958`. | `{customer,provider}_app/utils/dates.dart` + 10 screens |
| 25 | **Welcome, register and log in rebuilt**, with four real faults found on the way through: the register button was labelled **"Set OTP"**; the login screen posted whatever was in the mobile box, including nothing, and let the server do the complaining; resending had no cooldown, so it could be tapped in a loop; and both verify steps ran `setState` in a `finally` that fires *after* the screen has been replaced. The code card is now large, says no SMS is sent, and fills itself in. | `customer_app/screens/splash_and_auth.dart`, `widgets/common.dart` |
| 24 | **`basic_details_screen` rebuilt** — the one screen a customer has to fill in. A meter in the header says how much is left. Mandatory fields are marked *beside the field*, only after a save attempt, and clear themselves as they are filled. Leaving with unsaved changes asks first. Save is pinned to the bottom. Gender and blood group became tappable pills rather than dropdowns, and BMI now says which band it falls in. | `customer_app/screens/basic_details_screen.dart` |
| 23 | **The last five customer screens rebuilt** — regular carers, cancel booking, the account cards, terms and privacy, server settings. Unlinking a carer now asks first; it was one tap on a small red icon, with no undo, on the list of people you trust. Cancelling says what it costs *on the button*, not on a different part of the screen. Terms and privacy are four honest points each rather than one grey paragraph. | `customer_app/screens/{linked_providers, booking_cancel, account_sections, legal_content, server_settings}_screen.dart` |
| 22 | **The annual fee now goes through a payment sheet.** It was settled by a button reading "Mark registration complete" — accurate, since nothing is taken, but it made the one recurring charge in the app feel unlike every other payment in it. Same UPI apps, same simulated authorisation, same plain warning that no money moves. | `customer_app/screens/account_sections.dart` |
| 21 | **The customer profile and the health record rebuilt.** Restyling the three shared primitives — the expandable section, the record row, the add bar — lifted all six health sections at once rather than rewriting 853 lines of dialog logic. `ExpansionTile` was replaced with a hand-rolled section: it insisted on its own Material, its own divider colours, and a trailing slot only as wide as it felt like giving, which is what pushed the count into the title. Each section and each record now carries its own icon. | `widgets/common.dart`, `customer_app/screens/{profile_screen, profile_sections}.dart` |
| 18 | **Customer booking flow and provider profile rebuilt.** The profile now says what "checked by Sathiyaa" actually means and gives a cost estimate for the hours asked for. The flow's four screens — waiting, confirm, track, rate — carry a live pulse while a request is out, a countdown that turns red under three minutes, the OTP in large type, and a star picker with words. All timers and backend calls unchanged. | `customer_app/screens/{provider_detail_screen, booking_flow}.dart` |
| 19 | **`SCard` had no `Material`, so ListTiles inside it could not paint ink.** Flutter asserts on this. Introduced when I gave cards press feedback and dropped the Material wrapper. Fixed in the component, so every card gets it back. | `widgets/sathiyaa_ui.dart`, both apps |
| 20 | **Four stale Flutter tests**, all asserting a UI that no longer exists — the old Search title, a Profile nav tab that moved to the header avatar, the old dashboard card, and a renamed nav icon. Two also used `pumpAndSettle` on a screen whose live pulse repeats forever, so they hung rather than failed. | `customer_app/test/widget_test.dart`, `provider_app/test/widget_test.dart` |
| 16 | **Provider sign-up rebuilt**, and the volunteer choice with it. Giving your time free was a switch labelled "No Fees (donated / volunteer service)" — jargon, unexplained. It is now two cards that say plainly what each means, including that free work earns nothing back. Welcome and sign-in rebuilt too; the five steps carry a stepper. All validation and submit logic unchanged. | `provider_app/screens/auth_screens.dart` |
| 17 | **A dead button and a false claim on the sign-in screen.** "Reset OTP provision" had an empty handler, and a line claimed the demo PIN was pre-filled when the field was empty. The PIN is now genuinely pre-filled in demo mode only, and the reset button says who to call — the server endpoint exists but the app has no OTP/new-PIN flow wired to it yet. | `provider_app/screens/auth_screens.dart` |
| 14 | **The volunteer decision, built.** Nothing material: no points balance, no tier, no badge. The Time Bank tab became **Impact** — a thank-you, hours given, people visited, and a list of visits. Points are still recorded in the ledger for Sathiyaa's own reporting; they are simply not shown as a score, because a score turns a gift into a transaction. Ending a visit as a volunteer shows a short thank-you, and the payment block says "Nothing to collect" instead of ₹0. | `provider_app/screens/{time_bank_screen, booking_detail_screen, dashboard_screen, home_shell}.dart` |
| 15 | **`booking_detail_screen` rebuilt.** Laid out as the sequence it actually is — accept, travel, arrive and photograph, OTP, work, end, payment, rate — with a stepper saying where you are and only the current step expanded. Every handler and backend call unchanged. | `provider_app/screens/booking_detail_screen.dart` |
| 12 | **Provider app: shell, Home, Jobs and Time Bank rebuilt.** Four-tab pill bar matching the customer app (Profile moved to the header avatar). Home is an on-duty card with a live pulse, today's work, and an animated earnings figure. Jobs has counted tabs, a location-off warning, and per-bucket empty states. Time Bank leads with points earned. | `provider_app/screens/{home_shell, dashboard_screen, bookings_screen, time_bank_screen}.dart` |
| 13 | **`BookingStatus.name` was showing users "inProgress".** A variable name, put in front of a carer. Added a proper label extension. | `provider_app/lib/models.dart` |
| 11 | **A dead ~100px band under the care-type grid.** A nested `GridView` inherits the ambient `MediaQuery` padding, so it reserved the phone's bottom safe area in the middle of a form. Found while checking the rebuild. | `customer_app/screens/search_screen.dart` |

---

## Fixed on 17 September

| # | What | Where |
|---|---|---|
| 1 | **Tab switching ghosted.** An `AnimatedSwitcher` wrapped the `IndexedStack`, so both the outgoing and incoming tab stayed mounted and painted — on screen the old tab appeared to refuse to go away, and two copies of the page showed side by side. Removed; the pill bar animates its own selection, which is the feedback a tab switch actually needs. | `customer_app/screens/home_shell.dart` |
| 2 | **A tooltip painted over the header.** The bell's `Tooltip` rendered as a dark box across the greeting on web and lingered. Replaced with a `Semantics` label — a screen reader still announces it, nothing is drawn. | `customer_app/widgets/sathiyaa_ui.dart` |
| 3 | **Locate button on the map** (requested). Full-screen maps now carry a round "find me" control: it asks permission, centres on the device, drops the familiar blue dot with an accuracy ring, and reports how accurate the fix was. Failures say what to do rather than doing nothing. Shared with the provider app. | `widgets/osm_map.dart`, both apps |
| 4 | **A partner could not sign in with their email.** The lookup checked partner ID, both phone numbers and referral code, but not email — even though one is stored for every partner. | `backend/controllers/authController.js` |
| 5 | **Four test scripts were wrong, not the code.** Stale field names, a wrong email guess, and two places that scored a *correct* refusal as a failure. One had a nastier shape: the script created a partner each run, and since the list is newest-first its own leftover row became the login target. | `_tests/admin-actions.mjs`, `partner-login.mjs`, `contact-modes.mjs` |
| 6 | **Cleanup missed most test rows.** `cleanup-test-rows.mjs` matched six name prefixes and only swept customers. Widened to cover every name the scripts use, plus providers and a report on partners. Scripts that used realistic names now tag them `(QA)` — one of them, "Anjali Deshpande", had become a seeded provider too, so a name-matched delete could have removed a real row. | `_tests/cleanup-test-rows.mjs`, `practical.mjs`, `full-journey.mjs` |
| 7 | **The design sync script did not carry everything.** It copied the theme and the component set but not `motion.dart` or `osm_map.dart`, so the provider app failed to compile after the last change. | `_builds/sync-design.ps1` |

---

## To fix next session

Ordered by how much they hurt a demo.

### 1 · ~~Nineteen customer screens on two different designs~~  — **done**

All nineteen are on the design system. Welcome, register, log in, home,
search, the provider profile, the booking flow, payment, bookings, tracking,
rating, the customer's own profile, the health record, basic details, regular
carers, cancel, the account cards, terms and privacy, and server settings.

Both apps analyze clean and 64 tests pass.

### 2 · ~~Thirteen provider screens on two different designs~~  — **done**

All thirteen. Welcome, sign-in, registration, Home, Jobs, Impact, the job
detail screen, the shell, the profile, the calendar, server settings, and the
three organisation screens.

Both apps analyze clean and 64 tests pass.

### 3 · ~~Search result avatars are the old green~~  — **done**

Closed with the Search rebuild. Results now use `InitialsAvatar`, so each
person keeps a stable colour derived from their name, with a verified tick on
approved providers.

### 4 · ~~Provider app has no empty states~~  — **done**

All three closed. Time Bank now distinguishes a volunteer with no hours yet
from a provider who is not set up as a volunteer at all — they need different
sentences. Staff and the schedule overview use the shared component.

### 5 · ~~Appointments tabs have no empty treatment~~  — **done**

Closed with the Bookings rebuild. The three buckets are segmented controls
carrying live counts, and each empty state explains what would appear there.

### 6 · ~~Admin Reports renders blank with no data~~  — **done**

All four charts now say what would appear there and why it is empty, and the
growth request reports a failure instead of leaving the skeleton up for ever.

### 7 · ~~Running the test suite permanently pollutes the console~~  — **done**

The suite has a database of its own. `_tests\run-all.ps1` builds
`sathiyaa_test` from the migrations, seeds it, starts a second API on port 4010
pointed at it, runs all eighteen scripts and drops the database afterwards. The
development database is never touched, so the tests leaving rows behind stops
being something that can happen rather than something to sweep up after.

`cleanup-test-rows.mjs` is still there and still runs, for the rows already in
the development database from before this. See `_tests/README.md`.

### 8 · ~~First run lands you logged in~~  — **done**

Demo data opened as "Anita Verma", and the provider app as Karuna Companion
Services, so a first-time user never saw the welcome screen, the sign-up or the
code. Neither seeds a signed-in session now; Welcome carries a one-tap way into
the demo account, and a demo sign-in is remembered across restarts the way a
live one is, so it costs a first run and nothing after it.

The provider app's *Skip — look around with the demo account* button walked
straight into the home shell without signing in, which was harmless only while
the app opened signed in anyway. The first screen reads `currentProvider!`.

### 9 · ~~Demo mode shows three providers, live shows twenty-seven~~  — **done**

The demo directory is twenty-five providers across all four service types, at
real Bengaluru coordinates, four of them volunteers.

---

## Not built yet

| | Needed for |
|---|---|
| **Device info in the admin panel** | We store one opaque `device_id` string. Tracing a provider's handset needs make, model, Android version and last-seen IP — new columns, a new table, and the apps sending it. |
| **The volunteer experience** | The database already carries `no_fees` and a Time Bank ledger, and four volunteers are seeded. What is missing is the sign-up choice, the explanation of what they are opting into, and their own version of the screens. Still needs a decision: **what do volunteers actually get?** |
| **SOS that alerts anybody** | The screen puts the right numbers in front of you and says plainly that nothing was sent. Actually sending needs an SMS provider and a backend endpoint. |
| **Messaging** | The reference app has a chat thread with the companion. There is no messaging service behind ours; Notifications is derived from bookings instead. |
| **Booking for a dependent** | The reference app has a "Services for" picker — book on behalf of a parent. We store family members but cannot book for them. |

---

## Could be better

Checked against the code on 19 September rather than left as written. Two of
the five had been fixed and this list had not noticed; one has been done since;
the last two are restated as what is actually true.

- **Provider photos.** Everyone falls back to initials. That looks deliberate
  and works offline, which is more than the reference build manages — it
  hotlinks stock photos from `randomuser.me`. But real approved providers
  should have a real photo, and the upload path exists. *Still true.*
- **Caching stops at the provider list.** Providers fetched for a search are
  kept in memory for the session, which is what lets a booking row show a name
  without another round trip. Nothing else is: bookings, the health record and
  the directory are fetched fresh every time a screen opens, and nothing at all
  survives a restart. *Restated — the old wording said nothing is cached, and
  something is.*
- ~~**The booking journey has no progress indicator.**~~ **Done.** Requested,
  Accepted, Paid, Visit, Rated, on the waiting, confirm, tracking and rating
  screens. Each is a status the server really sets, so the stepper and the rest
  of the screen cannot disagree.
- ~~**No pull-to-refresh outside Home.**~~ **Wrong when it was written down.**
  It is on bookings, notifications and Home in the customer app, and on jobs and
  the dashboard in the provider app.
- ~~**Search has no sort.**~~ **Wrong when it was written down.** Nearest, best
  rated and lowest rate, with volunteers first on price — and it is in the
  fixed list above, which is how a stale entry survives in one section while the
  same document contradicts it in another.

---

## What is working

Worth recording, because it is most of it.

**Backend** — 158 routes exercised, the full booking journey, three-device
binding, uploads, blocks, admin actions, partner sign-in, contact modes, OSM
geocoding and routing. No contract drift between server and the console's
types across nine list endpoints.

**Free APIs, all live and verified** — OpenStreetMap tiles, Nominatim
geocoding ("Koramangala, Bengaluru" resolves correctly), OSRM routing
(Koramangala → MG Road returns 7.3 km / 11 min against a 5.2 km straight line,
so it is a real road route). No keys, no accounts, no bills.

**Admin panel** — all eleven pages return data, typechecks clean.

**Customer app** — Home, SOS, Notifications, Help and Payment are rebuilt and
behave: live data, staggered entrances, press feedback, skeletons while
loading, empty states that explain themselves, errors that offer a retry.

**Both APKs** — release builds, verified to contain the current code and the
cleartext-traffic config needed to reach a LAN server.
