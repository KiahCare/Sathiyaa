# The practical: one service, start to finish

A run-through where you play all three parts — a provider, a customer, and the
admin — and watch one real booking travel between them.

Every step has been run as a script first (`practical.mjs`, 74 checks) and every
route in the API has been exercised (`audit-everything.mjs`, 157 checks), so
nothing here should get stuck. If something does, it is a bug — tell me.

**Time:** about 25 minutes.

---

## Before you start

```
Double-click:  _builds\start-everything.cmd
```

Wait for `=== Everything is up ===`.

Open four browser tabs and arrange the first two side by side. That pairing is
where the interesting part happens — you will watch one screen change because
of something you did on the other.

| Tab | Address | Who you are |
|---|---|---|
| 1 | http://localhost:4175 | **Anjali**, the nurse |
| 2 | http://localhost:4174 | **Rohan**, the customer |
| 3 | http://localhost:4180 | **Admin** |
| 4 | http://localhost:4180 | Admin again — leave Audit Log open here |

### Switch both apps to live first

Both apps open in demo mode. In each of tabs 1 and 2:

> the icon at the **top right** → **Live Sathiyaa server** →
> `http://localhost:4000/api/v1` → **Test connection** → **Save and restart**

You should see *"Connected. The Sathiyaa server answered at …"*, and after the
restart a green **Live server** badge in the corner. Do this in both tabs.

On a phone instead, use the address `phone-connection-info.cmd` prints.

### Who you can be

| | |
|---|---|
| Admin | `admin@sathiyaa.com` / `Admin@123` |
| Business partner | `BP-000001`, or `9800000001`, or `APOL1001` — password `Partner@123` |
| A ready-made provider | `9600000274` (Sunita Joshi), PIN `123456` |
| A ready-made customer | `9700000000` (Anita Rao) — OTP shows on screen |

Invent your own mobile numbers for the new accounts: any 10 digits starting 6–9
that you have not used before.

---

## 1 · Anjali registers  *(tab 1)*

**Register as a provider → Freelancer.**

First, press **Next** with the form empty. It should refuse and mark every
missing field in red with a sentence saying what it needs. Until this pass you
could press Next five times and submit a completely blank application.

Then fill it in:

| Step | What to enter |
|---|---|
| 1 | **Anjali Deshpande**, Female, a mobile number, a date of birth |
| 2 | An address, then **Use my current location**. Work days Mon–Sat. Service: **Nurse** |
| 3 | Hourly rate `460` |
| 4 | The three documents — any photo will do |
| 5 | A 6-digit PIN |

Worth trying on purpose, because each of these used to be accepted:

- A mobile number starting `5` → refused.
- A date of birth under 18 → refused.
- PIN `111111`, or `123456` → refused.
- Skipping the police verification → refused.
- Choosing **Nurse** makes the medical certificate required; deselect Nurse and
  it becomes optional again.

**Submit.** You land on "pending admin approval" — correct. Customers cannot
find her yet.

---

## 2 · Admin reviews her  *(tab 3)*

**Service Providers → Pending →** Anjali → **View**.

Check that her expertise, her work hours and her three uploaded documents are
all there, and that a document link opens. Checking those is the entire point of
the queue, and until this pass the Aadhar never arrived at all.

Try the buttons: **Put on Hold**, then **Reject**, then **Approve**. All three
work now — Reject was not wired up at all, and Block was pointed at the wrong
endpoint, so pressing it silently *approved* the provider instead.

Finish on **Approve**.

---

## 3 · Rohan signs up  *(tab 2)*

**Create account.** Name **Rohan Saxena**, a mobile number. The OTP appears on
screen — no SMS is sent and nothing is charged.

Accept the terms, then **Profile → Basic details**:

- Fill in the identity fields.
- **Use my current location** for the address — the browser asks permission and
  the map moves to where you are.
- Under *Preferred mode of communication*, tick **all three**. Save.

That last one used to fail with "something went wrong" whenever more than one
was ticked: the column only accepted a single value.

Now open **Profile → Vitals** and add a blood-pressure reading. The rows should
be readable, not clipped top and bottom.

---

## 4 · He books her  *(tab 2)*

**Search** → Nurse → a weekday → 09:00 to 13:00 → **Search**.

Anjali appears with a distance. Tap her — you get a **real map** of where she
works. Tap the map to open it full screen; it pans and zooms. Then **Book**.

The booking says **Waiting for a provider**, with no Pay button. Correct: nobody
has accepted yet.

---

## 5 · She accepts  *(tab 1 — watch both screens)*

**Bookings → Requests.**

If it is not there yet, wait. The screen checks every 20 seconds by itself and
the line under the tabs says when it last looked; you can also pull down or use
the refresh button. Before this pass there was no way to check at all without
closing and reopening the app.

The request shows her **first name and area only** — not the full address or
phone. One request goes out to every matching provider, so those arrive with the
job, not with the offer.

Try **Accept** with location sharing off: refused. Go to **Dashboard**, turn on
**Share my location** — the browser asks permission, and the switch reports how
accurate the fix was. Now accept.

**Look at tab 2.** Within 20 seconds, without you touching it, Rohan's booking
becomes **Confirm your booking** with a countdown. Confirm it.

Nothing is charged. No payment provider is connected; confirming records the
charge against the booking and moves on.

---

## 6 · The visit  *(tab 1)*

Open the booking. Now that she has the job you should see Rohan's **full
address, his phone number with a Call button**, his blood group, and how he
prefers to be contacted. None of that existed before — a nurse on her way to a
house had a service type and a pair of coordinates.

Then, in order:

- **Show direction** — a real road route from OpenStreetMap, with a distance and
  a time. Free, no account.
- **Take arrival photo & check location** — the camera opens. The photo is
  uploaded and kept with the booking. Automated face *matching* stays off until
  a provider is connected, but the photo is real and an admin can look at it.
- **Send start OTP to customer.**
- **In tab 2**, Rohan's screen shows a 6-digit code. Read it across.
- Enter it in tab 1 → the service starts.
- **Send "running late"** — 10, 15 or 30 minutes.
- **End service.** It bills by the hours actually worked.
- **Record payment** — what Rohan handed over.
- Rate each other.

---

## 7 · What the admin sees  *(tabs 3 and 4)*

| Page | What should be there |
|---|---|
| **Audit Log** | Every step above, by name, with the device it came from |
| **Reports** | Anjali's visit under Revenue by Provider — with her name, not a blank |
| **Reports → by City** | Bengaluru, not "unknown" |
| **Live Tracking** | Anjali on a real map. **On active booking** counts her while the service is running — it used to be permanently 0 |
| **Customers** | Rohan, with his city |
| **Service Providers** | Anjali, approved and active |

Then try the actions on Anjali:

- **Block** → sign out in tab 1 and try to sign back in: refused. **Unblock** →
  she can.
- **Release device** → her account can move to a new phone.
- **Remove** → refused, because she has a booking. That is deliberate: an
  account with history gets blocked, never deleted.

And on Rohan: **Block** → he cannot even request an OTP. **Unblock** → he can.

---

## 8 · Broadcast and the business partner  *(tab 3)*

**Broadcast** → write a message → **Everyone** → send. The history below should
show it with your name, the time, and how many people it reached. Sending the
first broadcast used to turn the entire console blank, because the recipient
count was never stored and the page tried to read it.

Then sign out and use the **Business Partner** tab: `BP-000001` /
`Partner@123`. You should see their referrals and the revenue earned on them.
Any of these work as the identifier, upper or lower case:

```
BP-000001     the partner ID
9800000001    the contact number
APOL1001      the referral code
```

Those codes used to be regenerated on every reseed, so anything written down
stopped working the next day. They are fixed now.

---

## If something gets stuck

1. Is the API up? `http://localhost:4000/health` should say `{"status":"ok"}`.
2. Is the app on the live server? Green badge, top right.
3. Run the scripted version of this walk-through and compare:

```bash
node C:\Only Forward\Sathiyaa\_tests\practical.mjs
```

It performs the whole thing against the same server in about a minute and names
the exact step that failed.

Two more worth knowing about:

```bash
node C:\Only Forward\Sathiyaa\_tests\audit-everything.mjs
```

Calls every one of the 97 routes in the API, including the ones no journey
passes through.

```bash
node C:\Only Forward\Sathiyaa\_tests\contract-drift.mjs
```

Compares what the server sends against what the admin console's own types
expect. This is what catches the "blank column" class of bug before you see it.

And if the console ever fills up with test accounts:

```bash
node C:\Only Forward\Sathiyaa\_tests\cleanup-test-rows.mjs
```

Removes leftover automated-test rows. Anything that ever took a booking is left
alone.

---

## What is deliberately not real yet

| | |
|---|---|
| **Payment** | Removed. Every "pay" records as complete; no money moves. |
| **SMS** | OTPs appear on screen. No SMS provider, no bill. |
| **Push** | No notifications; the apps poll every 20 seconds instead. |
| **Face matching** | The arrival photo is real and stored. The automated comparison is off. |
| **Masked calls** | The provider sees and dials the customer's real number. Masking needs a paid telephony account. |
| **Maps** | Real, and free — OpenStreetMap. No live traffic, so ETAs are optimistic. |

## And one thing about the APKs

Windows Smart App Control is switched on on this machine, and it blocks
`gen_snapshot.exe` inside the Flutter toolchain — the tool that compiles a
*release* APK. I have not suggested turning that off: Windows only lets you
disable it once, and it cannot be turned back on without reinstalling.

So the APKs in this folder are **debug builds**: about 157 MB instead of 54,
slower to start, with a DEBUG ribbon in the corner. They install and run
normally. The browser builds at `localhost:4174` / `4175` are unaffected — they
are the same code and are what this walk-through uses. For real testers later,
build the release APK on a machine without that policy.
