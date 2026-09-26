# Checking Sathiyaa works, end to end

> **Looking for the full walk-through?** It moved to
> **[THE-PRACTICAL.md](THE-PRACTICAL.md)** - one booking followed from
> registration to payment across all three apps, with what to expect at each
> step. This file is the shorter smoke test and the reference for the scripted
> checks.

A short, ordered run. Each step says what you should see, so a wrong result is
obvious rather than ambiguous.

---

## Start it up

```
Double-click:  _builds\start-everything.cmd
```

(Or `powershell -ExecutionPolicy Bypass -File "...\start-everything.ps1"`. The
plain `powershell -File` form fails because Windows blocks unsigned scripts by
default; the `.cmd` handles that for you.)

**You should see** the integrations listed -- `Maps` is `LIVE  osm` (free
OpenStreetMap, no account needed) and everything else is `stub` -- then five
addresses:

```
Admin console - REAL DATA   http://localhost:4180   <- the one that matters
Admin console - demo data   http://localhost:4173
Customer app in a browser   http://localhost:4174
Provider app in a browser   http://localhost:4175
```

The two app addresses run the **real Flutter apps** compiled for the browser --
the same `lib/` code the APKs are built from. Use them when you want to try a
change without reinstalling an APK, or to act as the second person (customer
and provider) without a second phone.

**Once, in an Administrator PowerShell**, or phones cannot reach the server:

```powershell
New-NetFirewallRule -DisplayName "Sathiyaa API (port 4000)" -Direction Inbound -Protocol TCP -LocalPort 4000 -Action Allow -Profile Private
```

---

## Handing the APK to somebody

Both apps open on **demo data**: everything is already filled in, nothing
needs a server, and nothing they do is saved anywhere. That is the mode to
share.

**They will land on the welcome screen, not inside an account.** That is
deliberate, and it changed on 19 September: the apps used to open already
signed in, so nobody ever saw the sign-up or the one-time code, which is most
of what there is to show. Two ways on from there:

- **The real journey.** Create an account, watch the code appear on screen,
  accept the terms. Two minutes, and it is the part worth showing.
- **Straight in.** The note at the bottom of the welcome screen opens the demo
  account in one tap — *Open the demo account* on the customer app,
  *Skip — look around with the demo account* on the provider app.

Whichever they pick, the app remembers it. The welcome screen is a first run,
not every run.

If they press **Log out**, these are the accounts to log back in with:

| App | Number | Then |
|---|---|---|
| Customer | `9876500013` | The six-digit code appears on screen — tap **Use it** |
| Provider | `9998800201` | PIN `135790` |

The customer's number is pre-filled on the login screen when the app is on
demo data, so in practice it is two taps. Both numbers bring back the same
account with its bookings and history, not a blank one.

To point the app at your own server instead, open **Server** from the gear on
the welcome screen and switch to *Live Sathiyaa server*.

---

## Added 21 September

### Asking several carers at once

Customer app — **Companion** tab — search. Every result now has a **tick on
the left**. Tick two or three and a bar slides up from the bottom: *"3 carers
picked — all 3 are asked; the first to accept takes it"*. Tapping the card
still opens the profile, because you want to read about somebody before putting
them on the list.

**This was half-true before and is now honest.** The server has always sent the
request to every carer who matched and given it to whoever accepted first — but
the app showed one profile and said "requesting Lakshmi Iyer", so the screen and
the server were describing different things. Now the customer picks the
shortlist, only those are asked, and the waiting screen names them.

Worth trying: **tick four and pick one who is busy**. The shortlist is checked
against who is actually free, so that one is dropped and the waiting screen says
so rather than leaving you waiting on somebody who was never contacted.

### The papers step in provider registration

Provider app — **Register** — step 4. Rebuilt. Each document is a card the size
of the thing it is asking for, the whole card is the tap target, and it says
what each paper is for — half of these get refused because somebody
photographed the wrong piece of paper. Tapping opens a sheet offering the
camera, a file, or removing one you have already chosen.

### Smaller things

- **The bottom tabs move now.** The pill fills, the icon lifts as it becomes the
  selected one, and the whole thing dips under your finger. Skipped entirely if
  the phone is set to reduce motion.
- **Vitals reads properly.** The Reading and Duration controls were side by side
  with about 150px each, so the selected value was cut off and only the labels
  could be read. Reading is full width; the window is three buttons.
- **More demo data.** Every health section has records, the bookings list has
  something in all three tabs including a finished visit you can rate and a
  cancelled one, and the provider app has a visit already running so the OTP and
  "running late" screens can be seen without starting one.

---

## The four things added on 19 September

Worth walking through once, because none of them existed before and each has a
part that is easy to miss.

### Booking for somebody else

Customer app → **Companion** tab. Above the dates there is now **Who is this
for** — Myself, or anybody on your family list. Pick Anita's mother, book, and
then look at the same booking in the provider app: the job sheet says
*"You are visiting Kamala Devi (Mother), 85"*, gives a number for her, and
carries her note — "hard of hearing, knock twice and wait".

That is the whole point of it. The person paying and the person being visited
are often not the same, and a carer knocking and asking for the wrong name is a
mistake a family does not give you twice.

### Messages

On any confirmed booking, both apps now have a **Message** button — the
customer's is on the booking card, the carer's is in the job sheet header.
It is the same thread from both ends, with an unread badge.

Try sending one from the customer app and watching the badge appear on the
provider side. On demo data a reply comes back a few seconds later so you can
see it working without a second device.

**A thread only exists on a booking**, and only while it is confirmed, running
or just finished. Ask for one before a carer has accepted and it says so.

### The SOS button actually does something

Customer app → the red **Emergency** card → hold the button. It now raises a
real alert: recorded on the server, with your location and the people it would
reach.

**Read what it says afterwards.** With no SMS provider connected it tells you
plainly that nothing was sent and to call somebody yourself. That is
deliberate — a screen claiming your family has been notified when no message
left is worse than one that says nothing, because it stops you picking up the
phone. Wire up MSG91 or Twilio and the same button starts sending for real, with
no other change.

In the console, **every alert is visible**, and closing one makes you say what
was done about it.

### Devices

Console → **Devices**. Every handset that has signed in: make, model, Android
version, app version, when it was last used and from what address. Open the
customer or provider app once and refresh — your own phone appears.

The column worth understanding is **shared handsets**. One device under two
provider accounts is the exact thing device binding exists to catch; the page
flags it and shows you both accounts. For a family sharing a phone it is
ordinary, which is why it is flagged rather than blocked.

---

## 1. Is the backend alive?

Open **http://localhost:4180** and sign in:

| | |
|---|---|
| Email | `admin@sathiyaa.com` |
| Password | `Admin@123` |

**Should see:** the Service Providers list with real rows.
**If it says "Incorrect password"** you mistyped. **"Could not reach the API"**
means the server is not running — check the start window.

The fields start empty on purpose. Anything pre-filled would be demo
credentials that a real server rejects.

---

## 2. Point the phone at the server

Install both APKs. In each app: **chip at top right -> Live Sathiyaa server ->
type `192.168.1.35:4000` -> Test connection**.

**Should see:** "Connected. The Sathiyaa server answered at ..."
**If it says it could not reach the address:** the firewall rule is missing, or
the phone is on mobile data.

Press **Save**. The app signs out and the chip turns green: **Live server**.
If the chip still says "Demo data" you did not save, and nothing you do will
reach your database.

---

## 3. Register a provider

Provider app -> Register. Fill it in, set a 6-digit PIN, Submit.

**Should see:** "Registration submitted", saying an administrator must approve
you before customers can find you.
**Should NOT see:** a spinner that never stops. If a registration fails now it
tells you why — most often the mobile number is already registered.

**Check it landed:** refresh the admin console. Your provider is in
**Pending**, with the expertise and rate you entered.

---

## 4. Approve them

Admin console -> Service Providers -> **Pending** -> **View** -> **Approve**.

**Should see:** they move to Approved. Until this moment they are invisible to
customer search — that is the vetting gate, not a bug.

---

## 5. Register a customer and book

Customer app -> Create account. The OTP appears on screen in a yellow box (no
SMS is configured).

Then **Profile -> Basic details**: photo, date of birth, gender, and a
**primary address**. Search does not work without an address.

Search: service, dates, time window, address, radius.

**Should see:** your approved provider, with the distance.
**If empty:** not approved yet, wrong weekday for their work days, or outside
the radius.

Open them -> **Request this provider**.

**Should see:** "Waiting for a provider" with a spinner, and how many providers
were asked. **There is no Pay button yet, and that is correct** — the request
goes to every matching provider and the first to accept gets it. You pay only
once somebody has.

---

## 6. Accept it on the provider app

Provider app -> Dashboard -> turn **Share my location** on.
(Accepting is refused while it is off — a rule from the spec.)

Bookings -> Requests -> **Accept**.

**Should see, back on the customer app within a few seconds:** the waiting card
is replaced by **Booking charge** with a green "Provider accepted" badge and a
15-minute countdown. Pay it.

**Should see:** "Booking confirmed!"

---

## 7. Deliver the service

Provider app -> the booking:

1. **Show direction** -> "Simulate: I have arrived"
2. **Run face & location check** — passes only when you are near the customer's
   address, which is why you simulate arrival first
3. **Send start OTP to customer**
4. Customer app -> Appointments -> the booking -> read the OTP out
5. Provider app -> enter it -> **Confirm OTP & start**
6. Try **Send "running late"** -> 10/15/30 minutes
7. **End service** -> record payment -> **Rate the customer**
8. Customer app -> the completed booking -> hours and total -> **rate the provider**

---

## 8. Confirm the admin console saw all of it

At **http://localhost:4180**:

- **Audit Log** — every action, with which device did it
- **Live Tracking** — the provider's last position, with their services
- **Reports** — revenue from that booking, by city, service and provider
- **Customers** — the customer you registered
- **Business Partners** — sign out and back in as `BP-000001` / `Partner@123`
  to see the partner view

---

## What "working" looks like

| Layer | Proof |
|---|---|
| Database | The customer is still there after `stop-everything` then `start-everything` |
| API | Every step above returned something rather than an error |
| Provider app | Registration reached the admin console |
| Customer app | Search found the provider *only after* approval |
| Both together | Accepting on one phone changed the other phone's screen |
| Admin console | Audit Log lists actions taken from the phones |

If all six hold, the whole stack is working together.

---

## The two modes, and telling them apart

| | Demo data | Live server |
|---|---|---|
| Chip on the Welcome screen | grey, "Demo data" | green, "Live server" |
| Needs your PC | no | yes |
| Survives closing the app | **no** — resets every launch | yes, it is in MySQL |
| Shows in the admin console | no | yes |

The published link (`claude.ai/code/artifact/...`) is **always demo data**. It
opens anywhere, but it cannot reach a server on your machine. Use
**localhost:4180** for anything real.

---

## Starting over

```powershell
cd "C:\Only Forward\Sathiyaa\sathiyaa-full-project - Flutter Web version\backend"
npm run seed
```

Wipes everything and reloads the sample data. Safe to run repeatedly.


---

## 9. Demo and live should feel identical

The one difference that is deliberate: offline, a provider accepts your booking
automatically after a few seconds so you can walk the whole flow on one device.
Against the live server a real provider has to tap Accept in the other app.

Everything else must match. To check quickly, open the customer app twice --
once at http://localhost:4174 in demo mode, once switched to the live server --
and compare:

| | Demo | Live |
|---|---|---|
| Search finds nurses in Bengaluru | yes | yes |
| Each result shows a distance | yes | yes |
| A new booking says "Waiting for a provider" | yes | yes |
| Confirm is refused until someone accepts | yes | yes |
| Registration fee completes in one tap | yes | yes |

There is an automated version of this comparison:

```
cd "...\customer_app"
flutter test test/parity_test.dart
```

It runs the same script through both backends and fails naming the step where
they disagree. It skips itself if no server is running.

---

## 10. Switching an app to the live server

In either app: **Profile -> the icon in the top right -> Live Sathiyaa server**.

- In a browser on this computer: `http://localhost:4000/api/v1`
- On a phone: run `phone-connection-info.cmd` and use the address it prints.

Press **Test connection** first. A healthy server answers:

> Connected. The Sathiyaa server answered at http://...

Then **Save and restart the app**. A "Live server" badge appears in the top
right, and you have to sign in with a real account -- the demo accounts do not
exist on the server.


---

## 11. A note on the APKs and Windows Smart App Control

Smart App Control is switched on on this machine. It blocks two unsigned
binaries that live inside the Flutter toolchain:

| Binary | Used for | Worked around by |
|---|---|---|
| `font-subset.exe` | trimming the icon font | `--no-tree-shake-icons` (costs ~1.5 MB) |
| `gen_snapshot.exe` | compiling a **release** APK | see below |

The browser builds and the backend are unaffected. Release APKs are not,
because there is no way to compile one without `gen_snapshot`.

**I have deliberately not suggested turning Smart App Control off.** Windows
only lets you switch it off once — it cannot be turned back on without
reinstalling Windows — and that is not a decision worth making to build a test
app. The options that do not touch it:

1. **Use the browser builds** (`localhost:4174` / `4175`). Same code, no APK
   needed, and this is how the practical run-through is written.
2. **Install a debug APK.** Larger and slower than a release build, and it
   carries a "DEBUG" ribbon, but it installs and runs on a phone normally.
3. **Build the release APK somewhere else** — any machine without Smart App
   Control, or a cloud build. This is the right answer once the app is going to
   real testers.

The APKs currently in this folder are from the last successful release build.
They are older than the current source: they do not have the real maps, the
location permission prompts, the registration validation, or the document
uploads.


---

## 12. The scripted checks, and what each one is for

Run these against a running server. Together they take about three minutes.

| Command | What it proves |
|---|---|
| `node C:\Only Forward\Sathiyaa\_tests\practical.mjs` | The whole walk-through in THE-PRACTICAL, as a script. 74 checks. |
| `node C:\Only Forward\Sathiyaa\_tests\audit-everything.mjs` | Every one of the 97 API routes, including ones no journey touches. 157 checks. |
| `node C:\Only Forward\Sathiyaa\_tests\contract-drift.mjs` | That the server sends every field the admin console's own types require. |
| `node C:\Only Forward\Sathiyaa\_tests\full-journey.mjs` | A named end-to-end day plus 13 security probes. 55 checks. |
| `node C:\Only Forward\Sathiyaa\_tests\three-devices.mjs` | Two phones and a laptop against one server. 30 checks. |
| `node C:\Only Forward\Sathiyaa\_tests\admin-contract.mjs` | Every admin console screen's data shape. 23 checks. |
| `node C:\Only Forward\Sathiyaa\_tests\uploads-and-blocks.mjs` | Photos, calendar blocks, cross-account access. 20 checks. |
| `node C:\Only Forward\Sathiyaa\_tests\happy-path.mjs` | Register, book, serve, rate. 20 checks. |
| `node C:\Only Forward\Sathiyaa\_tests\osm.mjs` | That the free maps really reach OpenStreetMap. |
| `node C:\Only Forward\Sathiyaa\_tests\cleanup-test-rows.mjs` | Removes leftover test accounts. Anything with a booking is left alone. |

And in the Flutter apps:

```bash
flutter test                          # 22 customer, 23 provider
flutter test test/parity_test.dart    # runs one script through demo AND live
```

`contract-drift.mjs` is the one worth running after any backend change. It
catches the class of bug where a page reads a field the server stopped sending
- a blank column, or in one case the whole console going white.
