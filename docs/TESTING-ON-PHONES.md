# Testing Sathiyaa across several phones

The goal: a customer on one phone books a provider on another, and you watch it
happen in the admin console on your laptop. Everything here is free to run —
no payment gateway, no SMS bill, no cloud account.

---

## Once, before the first run

### 1. Start everything

```powershell
powershell -File "C:\Only Forward\Sathiyaa\_builds\start-everything.ps1"
```

That brings up MySQL, the API and the three web apps, and prints which
integrations are live (all stubbed) so you can see at a glance that nothing is
reaching out to a paid service.

### 2. Let the phones reach your PC

```powershell
powershell -File "C:\Only Forward\Sathiyaa\_builds\phone-connection-info.ps1"
```

It prints the address to type into the apps. **Windows Firewall blocks this by
default** — the script gives you the exact command to run in an Administrator
PowerShell. Without it every phone just times out.

Every phone must be on the same Wi-Fi as the PC. `localhost` will not work from
a phone; to a phone that means the phone.

### 3. Install the apps

Copy `sathiyaa-customer.apk` and `sathiyaa-provider.apk` to each phone, or with
the phone plugged in:

```powershell
adb install -r "C:\Only Forward\Sathiyaa\_builds\sathiyaa-customer.apk"
adb install -r "C:\Only Forward\Sathiyaa\_builds\sathiyaa-provider.apk"
```

Android will ask once to allow installing from an unknown source.

### 4. Point each app at your PC

In the app: **Welcome screen → the chip at the top right → Live Sathiyaa server
→ type the address → Test connection → Save.**

Test connection tells you immediately whether that phone can reach the server,
so you find out here rather than halfway through a booking.

A fresh install starts on **demo data** and works with no server at all. That is
deliberate — it means the APK is useful the moment it lands, and it means an
app that "works" on demo data proves nothing about your server. Check the chip.

---

## The three things that will look like bugs but aren't

### A provider account only works on one phone

The spec requires it: *"One user cannot have his application open on two
mobiles."* Sign in on a second phone with the correct PIN and it is refused.

That is correct behaviour. When you genuinely need to move an account to a
different handset — you swapped phones, or you are reshuffling test devices —
an admin releases it: **Admin console → Service Providers → View → Release
device.** The next phone to log in becomes the bound one.

Customer accounts have no such restriction; sign in on as many as you like.

### A brand-new provider is invisible to customers

Providers arrive with approval status **pending** and do not appear in customer
search until an admin approves them. Also by design — it is the vetting step.

So the order matters:

1. Register the provider on its phone
2. **Approve them in the admin console** (Service Providers → Pending → View → Approve)
3. Only then will the customer app find them

### You stay signed in between launches

Closing and reopening an app does not sign you out — the session is remembered
and restored, and the app checks with the server that it is still valid before
trusting it. If the server is off when you open the app, it starts signed out
rather than hanging.

Switching backend or changing the server address deliberately signs you out:
the account you were using does not exist on the other side.

### No SMS arrives

Nothing is sent, because no SMS account is configured. The OTP is shown on
screen in the app instead, in a yellow box. That is the stub doing its job.

---

## A full run-through, three devices

**Phone A — provider**

1. Register: freelancer, work days and hours, hourly rate, 6-digit PIN
2. It will say pending approval

**Laptop — admin** (http://localhost:4173, `admin@sathiyaa.com` / `Admin@123`)

3. Service Providers → Pending → View → **Approve**

**Phone B — customer**

4. Register with name + mobile, read the OTP off the screen, accept the terms
5. Profile → Basic details → add a photo, date of birth, gender, and a
   **primary address** — search will not work without one
6. Search: pick the service, the dates, the time window and the address
7. Your provider should appear, with the distance shown
8. Open them → **Request this provider** → pay the booking charge

**Phone A — provider**

9. Dashboard → turn **Share my location** on (accepting is refused while it is off)
10. Bookings → Requests → **Accept**
11. Open the booking → **Show direction** → "Simulate: I have arrived"
12. **Run face & location check** — this only passes when you are near the
    customer's address, so use the simulate button first
13. **Send start OTP to customer**

**Phone B — customer**

14. Appointments → the booking → the OTP is on screen; read it out

**Phone A — provider**

15. Enter the OTP → **Confirm OTP & start**
16. Try **Send "running late"** → pick 10/15/30 minutes
17. **End service** → record payment, full or partial
18. **Rate the customer**

**Phone B — customer**

19. Appointments → the completed booking → hours and total → **rate the provider**

**Laptop — admin**

20. **Audit Log** shows every one of those actions, with which device did it
21. **Live Tracking** shows the provider's last position
22. **Reports** shows the revenue that booking generated

---

## What to look at in the admin console

The console runs in two modes:

- **http://localhost:4173** — demo data, self-contained, nothing you do is saved
- **The published link** — same demo data, opens on any device, shareable

To point the local console at your **real** database instead, so it shows what
your phones actually did:

```powershell
cd "C:\Only Forward\Sathiyaa\sathiyaa-full-project - Flutter Web version\admin-portal"
$env:VITE_USE_MOCK = "false"
$env:VITE_API_BASE_URL = "http://localhost:4000/api/v1"
npm run build
npm run preview -- --port 4180
```

Then open http://localhost:4180. The published link can never do this — a page
hosted elsewhere cannot reach a server on your machine.

---

## When something looks wrong

**"Cannot reach the server"** — the firewall rule is missing, the phone is on
mobile data instead of Wi-Fi, or the API is not running. Run
`phone-connection-info.ps1`; it checks all three.

**Search finds nobody** — the provider is not approved yet, has no matching
expertise, does not work that weekday, is outside the radius, or already has a
booking in that range. The seeded providers work Monday to Saturday; a Sunday
search legitimately matches nobody.

**"This account is already bound to a different device"** — expected. Release
it from the admin console.

**Start service is refused** — the provider is not within 500 m of the
customer's address. Use "Show direction → Simulate: I have arrived".

**Starting over** — this wipes everything and reloads the sample data:

```powershell
cd "C:\Only Forward\Sathiyaa\sathiyaa-full-project - Flutter Web version\backend"
npm run seed
```

---

## Questions you will probably have

**Does my PC need to be on?**
For live mode, yes — the apps talk to the API and MySQL running on it. Close the
terminal or sleep the PC and the phones lose the server. Demo mode needs
nothing at all.

**Can the two phones talk to each other without the PC?**
No. Every message goes through the server. There is no phone-to-phone channel.

**Does what I do survive closing the app?**
- **Live mode** — yes. It is in MySQL, and still there after a reboot.
- **Demo mode** — no. The demo data is in memory and resets to the seeded
  sample every time the app starts. That is the giveaway that you are looking
  at demo data rather than your server.

**Can I install both apps on the same phone?**
Yes. They have different package names and sit side by side.

**Can I give an APK to someone else to try?**
On your Wi-Fi, yes. Away from it they can only use demo mode — their phone
cannot reach your PC from another network. Putting the API on the internet is
what changes that.

**iPhone?**
Not yet. Android only for now, by decision; iOS is a later pass and needs an
Apple Developer account.

**Will the apps drain battery or track me in the background?**
No. There is no background location and no background service. Location is only
read while the app is open and you have switched sharing on.

**Do I need to reinstall when you change something?**
For app changes, yes — install the new APK over the old one; your settings and
session survive. For server changes, no; just restart the API.

## Sample logins

| Who | How |
|---|---|
| Admin | `admin@sathiyaa.com` / `Admin@123` |
| Provider | mobile `9600000000`, PIN `123456` |
| Organization head | mobile `9611122233`, PIN `123456` |
| Customer | mobile `9700000000` — OTP flow, code shown on screen |
| Business Partner | mobile `9800000001` / `Partner@123` |

The seeded provider accounts may already be bound to a device from earlier
testing. Release the device from the admin console, or `npm run seed` to reset
everything.
