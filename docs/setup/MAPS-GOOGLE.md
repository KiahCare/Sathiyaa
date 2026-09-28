# Maps and addresses — Google Maps Platform

There are **two separate things** the word "maps" covers here, and they have
different answers. Conflating them is why this looks bigger than it is.

| | Today | Change? |
|---|---|---|
| **The map you look at** in the app | OpenStreetMap tiles via `flutter_map`. Free, no key | **No.** It works, it costs nothing |
| **Turning an address into coordinates**, and distances | OSM Nominatim + OSRM | **Yes.** This is the one worth paying for |

---

## Why change the second one

Two reasons, and the first is the one that matters.

**Nominatim is weak on Indian addresses.** Indian addresses are not what it
was built for — "B/402, Shivalik Residency, nr. Prahladnagar Garden,
Ahmedabad" is a completely normal way to write an address here and a
completely abnormal one to parse. Google handles it. Nominatim often does not.

A wrong geocode is not a cosmetic bug in this product. It is a carer sent to
the wrong building for a booked visit to an elderly person.

**And we are outside Nominatim's terms.** Their usage policy caps use at one
request per second and discourages commercial volume. Nothing has broken
because our volume is tiny, but they block by IP without warning, and finding
that out on the day we grow is not a plan.

**The runner-up:** MapMyIndia (Mappls) is genuinely good on Indian addresses
and often cheaper. It is not implemented here, so choosing it costs a week of
work Google does not. Worth revisiting if Google's bill ever gets real.

---

## Cost

Google gives a monthly free allowance per API. At our volume the likely bill
is **nothing, or a few dollars**.

> Google restructured Maps pricing in March 2025 and it has moved since.
> **Check the live figures on their pricing page before you enable billing.**
> Do not take a number from me on this.

The card is required even to stay inside the free allowance. Set the budget
alert in step 5 and it cannot surprise you.

---

## 1 · Project and billing

1. **console.cloud.google.com** → sign in with the same Google account you
   used for Firebase. Keeping them together makes the billing legible later.
2. Top bar → project dropdown → **New Project** → name it `Sathiyaa Maps`.
3. **Billing** → **Link a billing account** → add a card.

---

## 2 · Enable exactly three APIs

**APIs & Services → Library**, and enable, one at a time:

| API | What we use it for |
|---|---|
| **Geocoding API** | Address text → coordinates, at registration and booking |
| **Directions API** | Real road distance, so a ₹ estimate is not a straight line |
| **Places API (New)** | Address autocomplete as somebody types |

Enable **only** these three. Every extra API is extra surface on a key that
gets stolen one day.

> Google ships two generations of Places. Pick **"Places API (New)"**. The old
> one is on a deprecation path.

---

## 3 · One key, restricted properly

**APIs & Services → Credentials → Create credentials → API key.**

Then immediately click **Edit API key** — an unrestricted key is a key someone
else will eventually spend your money with.

**Application restrictions** → **IP addresses** → add your EC2 server's public
IP address, and nothing else.

**API restrictions** → **Restrict key** → tick exactly the three APIs above.

Name it `sathiyaa-server`. Save.

### Why only one key, and why server-only

Address autocomplete could be called straight from the phone. It will not be.
A key inside an APK is a key anyone can extract with a zip tool, and it cannot
be IP-restricted because a phone has no fixed IP.

So the apps ask **our** server, and our server asks Google. The key never
leaves the EC2 instance, stays IP-locked, and if it ever leaks we rotate one
value in one file. This costs one extra network hop and is worth it.

---

## 4 · Switch it on

In `backend/.env`, on the server, by you:

```
MAPS_PROVIDER=google
GOOGLE_MAPS_API_KEY=AIza...
```

```bash
sudo systemctl restart sathiyaa && sudo journalctl -u sathiyaa -n 40 --no-pager
```

Boot table should read `maps: google`.

---

## 5 · Budget alert — do not skip this

A loose Maps key is one of the classic ways to wake up to a four-figure bill.

**Billing → Budgets & alerts → Create budget** → ₹2,000/month → alert at
50%, 90% and 100% → your email.

This does not cap spending; it warns you. Combined with the IP restriction
above, that is enough.

---

## What I build

| Piece | Detail |
|---|---|
| Autocomplete proxy | `/api/v1/places/autocomplete` and `/places/details`, keyed to the logged-in user, rate limited, key stays server-side |
| Address entry in both apps | Type three characters, pick from a list, done — replaces free-typing an address nobody validates |
| Session tokens | Google bills autocomplete by session, not keystroke. Getting this wrong multiplies the bill by ten. It is a small detail with a large invoice attached |
| Bias to the service area | Results near Ahmedabad first, so "Shivalik" does not offer a match in Delhi |

**Roughly a week**, mostly the app side.

The map you look at stays on free OSM tiles. If you later want Google's
familiar look inside the app, that is a separate change and a separate
(Android-restricted) key — say the word and I will cost it then.

---

## What each of us does

| | |
|---|---|
| **You** | Cloud project, billing, three APIs, one restricted key, budget alert, two lines in `.env` |
| **Me** | The proxy endpoints, autocomplete in both apps, session tokens, service-area bias |
