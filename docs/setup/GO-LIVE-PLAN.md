# Go-live plan — one choice per capability

Written 29 September 2026. Deliberately excluded for now, by decision:
**payment gateway** and **masked calling**. Both are wired on the server
already; both wait until the rest of this list is done.

This file is the index. Each capability has its own file with the exact
clicks, and every one of them is split the same way: **You** (accounts,
cards, approvals — things only the account holder can do) and **Me** (code).

---

## The choices, and why

| Capability | Chosen | Runner-up, and why not |
|---|---|---|
| OTP / SMS | **MSG91** | Twilio works and is already coded, but costs ~4x for India-only traffic and gives no help with DLT |
| Push notifications | **Firebase Cloud Messaging** | There is no runner-up. FCM is how Android delivers push, free at any volume we will reach |
| Face verification | **AWS Rekognition** | Azure Face needs written approval from Microsoft before it answers at all — days to weeks, for no gain |
| Maps / addresses | **Google Maps Platform** (server-side) | Nominatim is free but weak on Indian addresses, and its usage policy does not permit commercial volume |
| Media storage | **Amazon S3** + expiring links | Staying on the instance disk means no backup, and documents readable by anyone holding a URL |

Every one of these is already written in the codebase behind an interface with
a stub on the other side. Switching each one on is an environment variable and
a restart — the server prints a table at boot saying which provider each
capability resolved to, so there is no guessing.

---

## Order of work, and why this order

Two of these have a **waiting period you cannot shorten**. Start them first
and they run in the background while everything else gets built.

### Start today, finish weeks later

| # | Task | Your time | Then you wait |
|---|---|---|---|
| 1 | **DLT registration** — [SMS-MSG91.md](SMS-MSG91.md) §1 | ~2 hours of forms | **3–10 working days** |
| 2 | **AWS Activate credits** — see note below | ~1 hour | **7–10 business days** |

> The new-account and migration runbook is `AWS\NEW-ACCOUNT-AND-MIGRATION.md`,
> which stays on the laptop rather than in this repository: it names our actual
> instances, buckets and distributions. Everything in this `setup/` folder is
> generic and carries no account details.

Nothing else depends on you while those run.

### Same day, no waiting

| # | Task | Your time | Unlocks |
|---|---|---|---|
| 3 | **Firebase project** — [PUSH-FCM.md](PUSH-FCM.md) | 20 min | Push notifications |
| 4 | **Google Cloud + Maps keys** — [MAPS-GOOGLE.md](MAPS-GOOGLE.md) | 30 min | Real addresses, autocomplete |
| 5 | **Rekognition IAM user** — [../AWS-REKOGNITION.md](../AWS-REKOGNITION.md) | 15 min | Face check at arrival |
| 6 | **S3 bucket for uploads** — [S3-UPLOADS.md](S3-UPLOADS.md) | 20 min | Documents backed up and access-controlled |
| 7 | **Billing budget alarm** — [BILLING-ALARM.md](BILLING-ALARM.md) | 5 min | You find out before the card does |

About **two hours of your time in total**, plus the two waits.

---

## What I build once you hand me the keys

You never send me a key. Every one of them goes into `backend/.env` on the
server, by you. What I need from you is only "done" — then I switch the
provider on and build the parts of the product that use it.

| Capability | What is already written | What I still have to build |
|---|---|---|
| SMS OTP | Whole provider, both vendors, OTP generation, hashing, expiry | Nothing. One env var |
| Push | FCM provider, device registry table | Token column + registration endpoint, Flutter side, the events that trigger a notification |
| Face | Rekognition provider, signed requests, threshold | The selfie step in the provider app at check-in, the comparison call, what happens on a mismatch |
| Maps | Geocoding, directions, distance | Address autocomplete, proxied through our server so no key ships inside the APK |
| Media | Local disk storage | S3 provider, expiring links, closing the open `/uploads` path, moving the existing files |

Rough total: **three to four weeks of build**, assuming the accounts above are
ready when each piece starts.

---

## The one thing on this page that is a security problem today

`backend/src/app.js` mounts `/uploads` with `express.static` **before** the
access-key gate that protects `/api/v1`. Different path prefix, so the gate
never applies to it.

Anyone holding the URL of an uploaded aadhaar card, police verification or
medical certificate can fetch it — no key, no login, no token, no record that
they did. The filenames carry 64 bits of randomness so nobody can guess one;
but a URL that leaks in a log, a screenshot or a forwarded email stays valid
for ever, and there is no way to revoke it.

This is fixed by the S3 work in item 6, which is why item 6 is not optional
and is not last.

---

## What I am deliberately not choosing yet

- **Payment gateway** (Razorpay) — your decision, deferred. Server side is done.
- **Masked calling** (Exotel) — deferred. Server side is done.
- **iOS** — needs a Mac and an Apple Developer account, and neither exists yet.
