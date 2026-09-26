# Putting Sathiyaa on AWS

Written to be followed top to bottom. Every command is one you run — I never
have your AWS credentials and never will; nothing here asks you to paste a key
anywhere but your own console.

The shape at the end:

```
  phones + browser
        │  HTTPS
        ├── CloudFront  d-aaaa.cloudfront.net ──→ S3 bucket        admin console
        └── CloudFront  d-bbbb.cloudfront.net ──→ EC2 :4000        the API
                                                    ├── RDS MySQL 8   (private)
                                                    └── EBS volume    (uploads)
```

**CloudFront sits in front of the API on purpose.** It gives you HTTPS on a
free `*.cloudfront.net` name, so you need no domain and no certificate to start.
Buy a domain later and point it at the same distributions; nothing else changes.

---

## Before anything: the order that avoids a wasted afternoon

The console bundle has the API address **compiled into it**, and the API will
only accept requests from the console's address. Each needs the other's name,
and both names only exist once the distributions do.

So: **create both CloudFront distributions first**, write down both domain
names, and only then configure and build. Doing it the other way round means
building twice.

### First, prove the configuration on your own machine

The settings below are the ones that only exist on the deployed server: an
access key, a CORS allow-list, a real JWT secret, rate limiting, a rotated admin
password. Nothing you have run locally so far has used any of them, so nothing
you have run so far says whether they work.

```bash
powershell -ExecutionPolicy Bypass -File "C:\Only Forward\Sathiyaa\_tests\run-all.ps1" -Public
```

That builds a throwaway database, starts an API configured exactly the way this
guide is about to configure the real one, and checks the things that only go
wrong in that configuration: the key is required and a wrong one is refused, the
console's origin is allowed and another site is not, repeated wrong passwords
get cut off while the health check keeps answering, an unknown account and a
wrong password are the same answer, and the server refuses to start at all when
the secret is a placeholder or the key is too short.

**Twenty-six checks, about a minute.** If it passes, the configuration in step 3
is not going to surprise you at two in the morning. Run the ordinary suite too:

```bash
powershell -ExecutionPolicy Bypass -File "C:\Only Forward\Sathiyaa\_tests\run-all.ps1"
```

Twenty scripts, its own database, dropped afterwards — the development
database is not touched. And the Flutter suites, which have a group that talks
to a live server and is easy to forget about:

```bash
powershell -ExecutionPolicy Bypass -File "C:\Only Forward\Sathiyaa\_tests\run-all.ps1" -Flutter
```

---

## 0. Two things on your machine, and one in the console

### The AWS CLI

Step 6 uploads the console with `aws s3 sync` and clears the CloudFront cache
with `aws cloudfront create-invalidation`. Neither is optional and neither has a
usable equivalent in the browser for a folder of hashed asset files.

```bash
winget install --id Amazon.AWSCLI -e
```

Close and reopen the terminal afterwards, then check it:

```bash
aws --version
```

### An access key for it

Console — IAM — Users — Create user. No console access — this user is only for
the CLI on your laptop.

Attach **AmazonS3FullAccess** and **CloudFrontFullAccess**. Both are broader
than this actually needs; narrowing them to the one bucket and the one
distribution is worth doing once the names exist, and is not worth blocking the
first deploy on.

Then Security credentials — Create access key — *Command Line Interface*.
Download the CSV. Now, on your machine:

```bash
aws configure
```

It asks four things: the access key id, the secret, `ap-south-1`, and `json`.

**I never see any of that.** It is typed into your own terminal and stored in
your own `~/.aws/credentials`. Nothing in this project reads it, and nothing I
run asks for it.

### A billing budget, before anything is running

Console — Billing and Cost Management — Budgets — Create budget — Monthly cost
— set a figure and an email alert.

Five minutes, and it is the difference between noticing a surprise on day three
and reading about it in a statement four weeks later. Do this first, not last:
everything below costs money the moment it starts, and the free tier has edges
that are easy to walk over without noticing.

---

## 1. Generate the two secrets

On your machine:

```bash
powershell -ExecutionPolicy Bypass -File "C:\Only Forward\Sathiyaa\_builds\make-deploy-secrets.ps1"
```

It prints a `JWT_SECRET` and an `API_ACCESS_KEY` and writes nothing to disk.
Keep them somewhere you can find them — you need each one in three places.

**What each is:**

- **`JWT_SECRET`** — anyone holding it can sign a token that says `role=admin`.
  This is the real secret. It never leaves the server.
- **`API_ACCESS_KEY`** — a door on the building. It is baked into the two APKs
  and the console bundle, so anyone who unpacks an APK can read it. That is
  understood. Its job is to stop a scanner that finds your hostname from
  walking through a registration flow that hands back one-time codes, which is
  what happens while no SMS provider is configured. Treat it as "do not put
  this in a public repo or a screenshot", not as "this is unbreakable".

---

## 2. RDS — the database

Console → RDS → Create database.

| Setting | Value |
|---|---|
| Engine | MySQL 8.0 |
| Template | Free tier |
| Instance | `db.t4g.micro` |
| Storage | 20 GB gp3 |
| Public access | **No** |
| VPC security group | new, call it `sathiyaa-db` |
| Initial database name | `sathiyaa` |
| Master username | `admin` |
| Master password | generate one, save it |

When it is up, note the **endpoint** — `sathiyaa.abcdef.ap-south-1.rds.amazonaws.com`.

Use `ap-south-1` (Mumbai) unless you have a reason not to. The users are in
India and the difference is real: about 30 ms to Mumbai against about 250 ms to
Virginia, on every single request.

---

## 3. EC2 — the API

Console → EC2 → Launch instance.

| Setting | Value |
|---|---|
| Name | `sathiyaa-api` |
| AMI | Amazon Linux 2023, 64-bit (x86) |
| Instance type | `t3.micro` — the console no longer offers `t4g.micro` on the free tier |
| Key pair | create one, download the `.pem`, keep it |
| Security group | new, `sathiyaa-api` |
| Storage | 16 GB gp3 |

**Security group inbound rules — this is the part that matters:**

| Type | Port | Source | Why |
|---|---|---|---|
| SSH | 22 | **My IP** | Not `0.0.0.0/0`. Every SSH port on the internet is being brute-forced right now. |
| Custom TCP | 4000 | Prefix list `com.amazonaws.global.cloudfront.origin-facing` | Only CloudFront can reach the API directly. Anything else that finds the instance IP gets nothing. |

Then edit the **`sathiyaa-db`** group: allow MySQL 3306 **from the
`sathiyaa-api` security group** (pick the group, not an IP).

### Install and run

SSH in, then:

```bash
sudo dnf update -y
sudo dnf install -y nodejs20 git
sudo mkdir -p /opt/sathiyaa /var/lib/sathiyaa/uploads
sudo chown -R ec2-user:ec2-user /opt/sathiyaa /var/lib/sathiyaa
```

Pack the backend on your machine:

```bash
powershell -ExecutionPolicy Bypass -File "C:\Only Forward\Sathiyaa\_builds\package-for-ec2.ps1"
```

That writes `_builds\sathiyaa-backend.tar.gz` — about 120 KB — and checks what
is *not* in it before telling you so. `scp -r` of the folder would send 14 MB,
and three things you do not want on a public instance: `node_modules` built for
Windows that get deleted and reinstalled for Linux anyway, your laptop's
`.env` with its database password and JWT secret, and two megabytes of documents
from local test runs.

Copy it up and unpack it:

```bash
scp -i "C:\Users\Phoenix\.ssh\sathiyaa-key.pem" "C:\Only Forward\Sathiyaa\_builds\sathiyaa-backend.tar.gz" ec2-user@<instance-ip>:/tmp/
```

```bash
tar -xzf /tmp/sathiyaa-backend.tar.gz -C /opt/sathiyaa
cd /opt/sathiyaa/backend
npm ci --omit=dev
```

### The .env

`nano /opt/sathiyaa/backend/.env` — and read the comments in `.env.example`
if any line is unclear:

```ini
PORT=4000
NODE_ENV=development          # deliberate: keeps the code on screen, see below
PUBLIC_DEPLOYMENT=true        # turns on every guard that matters

DB_HOST=sathiyaa.abcdef.ap-south-1.rds.amazonaws.com
DB_PORT=3306
DB_NAME=sathiyaa
DB_USER=admin
DB_PASSWORD=<the RDS master password>
DB_SSL=true                   # the database is on another machine now
DB_SSL_CA=/opt/sathiyaa/global-bundle.pem

JWT_SECRET=<from step 1>
JWT_EXPIRES_IN=7d

CORS_ORIGINS=https://d-aaaa.cloudfront.net    # the CONSOLE distribution
API_ACCESS_KEY=<from step 1>
TRUST_PROXY_HOPS=1

ADMIN_EMAIL=admin@sathiyaa.com
ADMIN_PASSWORD=<a long one you choose — at least 12 characters>

UPLOAD_DIR=/var/lib/sathiyaa/uploads
MAPS_PROVIDER=osm
```

`NODE_ENV=development` is not an oversight. It is what keeps the one-time code
coming back in the response so people can sign in with no SMS provider wired
up. `PUBLIC_DEPLOYMENT=true` is what stops that decision dragging the rest of
the development defaults onto the internet. The server prints a note about this
every time it starts.

### Migrate, seed, lock the admin account

```bash
cd /opt/sathiyaa/backend
npm run migrate
npm run seed
node scripts/set-admin-password.mjs admin@sathiyaa.com "a long passphrase you choose"
```

`npm run migrate` applies all eleven migrations, including the four added on
19 September: the device registry, the dependent on a booking, emergency alerts
and the message thread. **It is safe to run twice** — that was fixed on the
19th, when the second run used to fail on a foreign key it had itself created.

The seed writes the demo directory — 36 providers, 20 customers, 3 partners.
Useful for showing the console with something in it. Skip `npm run seed` if you
want to start empty; migrate alone creates the schema and the admin account.

### Keep it running

```bash
sudo tee /etc/systemd/system/sathiyaa-api.service >/dev/null <<'UNIT'
[Unit]
Description=Sathiyaa API
After=network-online.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/sathiyaa/backend
ExecStart=/usr/bin/node src/server.js
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now sathiyaa-api
sudo systemctl status sathiyaa-api
```

**If it refuses to start, read the message.** `preflight` names exactly which
setting is wrong and why. That is the whole point of it — it will not let you
put a forgeable token or an open CORS policy on the internet by accident.

Check it locally on the instance:

```bash
curl localhost:4000/health
```

---

## 4. CloudFront in front of the API

Console → CloudFront → Create distribution.

| Setting | Value |
|---|---|
| Origin domain | the EC2 **public DNS**, e.g. `ec2-13-1-2-3.ap-south-1.compute.amazonaws.com` |
| Protocol | **HTTP only**, port **4000** |
| Viewer protocol policy | **Redirect HTTP to HTTPS** |
| Allowed methods | **GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE** |
| Cache policy | **CachingDisabled** |
| Origin request policy | **AllViewerExceptHostHeader** |

**The last two are the ones people get wrong.** With the default cache policy
CloudFront strips the `Authorization` and `X-Sathiyaa-Key` headers and caches
responses, and every call comes back 401 or stale. `AllViewerExceptHostHeader`
forwards them; `CachingDisabled` stops an API response being served to the next
person who asks.

Note the domain it gives you — that is `d-bbbb.cloudfront.net`, the API address.

Test from anywhere:

```bash
curl https://d-bbbb.cloudfront.net/health
```

That should answer without a key. Then check the door is shut:

```bash
curl -i -X POST https://d-bbbb.cloudfront.net/api/v1/auth/admin/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@sathiyaa.com","password":"whatever"}'
```

**That must come back 401 with "Missing API access key".** If it comes back
anything else, stop and fix it before going further.

---

## 5. S3 + CloudFront for the console

Create a bucket — `sathiyaa-console-<something-unique>`, block all public
access **on** (CloudFront reaches it through an Origin Access Control, not
through public reads).

Create a second distribution:

| Setting | Value |
|---|---|
| Origin | the S3 bucket, with **Origin access control** (create one, then apply the bucket policy it offers) |
| Viewer protocol policy | Redirect HTTP to HTTPS |
| Default root object | `index.html` |

The console is a single-page app, so a deep link like `/admin/reports` is not a
file in the bucket. Add two **custom error responses**:

| HTTP error code | Response page | Response code |
|---|---|---|
| 403 | `/index.html` | 200 |
| 404 | `/index.html` | 200 |

Without these, refreshing on any page but the root gives you an S3 error.

That distribution's domain is `d-aaaa.cloudfront.net` — the one that goes in
`CORS_ORIGINS` above. If you have not set it yet, set it now and
`sudo systemctl restart sathiyaa-api`.

---

## 6. Build and upload the console

On your machine:

```bash
powershell -ExecutionPolicy Bypass -File "C:\Only Forward\Sathiyaa\_builds\build-for-cloud.ps1"
```

It asks for the API URL and the access key, builds `dist-cloud`, and tells you
the `aws s3 sync` command to run. Then:

```bash
aws s3 sync dist-cloud s3://sathiyaa-console-<yours>/ --delete
aws cloudfront create-invalidation --distribution-id <console dist id> --paths "/*"
```

The invalidation matters. Without it CloudFront serves the old bundle for up to
24 hours and you will think the deploy failed.

Open `https://d-aaaa.cloudfront.net` and sign in with the password you set in
step 3.

---

## 7. The two apps

```bash
powershell -ExecutionPolicy Bypass -File "C:\Only Forward\Sathiyaa\_builds\build-for-cloud.ps1" -Apks
```

This compiles **both** the cloud address and the access key into each APK, and
then reads the built file back to prove they are in there — a dart-define whose
name is wrong fails silently, the built-in default applies, and you find out
once it is on somebody's phone.

Because the address is compiled in, these open against AWS on first run rather
than on demo data. That is the difference between handing somebody an APK and
handing them an APK plus a piece of paper with a hostname on it.

They come out as `sathiyaa-customer-cloud.apk` and
`sathiyaa-provider-cloud.apk`, alongside the laptop ones rather than replacing
them. The **Server** screen still works, so a cloud build can be pointed back at
your machine.

---

## 8. Check the deployed server, from here

The same suite, aimed at the thing that is now live:

```bash
powershell -ExecutionPolicy Bypass -File "C:\Only Forward\Sathiyaa\_tests\run-all.ps1" -Api https://YOUR-API-DOMAIN/api/v1 -Key YOUR-ACCESS-KEY -AdminPassword YOUR-ADMIN-PASSWORD
```

It builds nothing and drops nothing in this mode — it only makes
requests. Two things to know before you read the result:

- **It will create real rows** on the deployed database, the same way it does
  locally: test customers, test providers, a handful of bookings. Run it before
  you show anybody, not after, or reseed afterwards.
- **Rate limiting will stop it.** The suite makes several hundred requests and
  the sign-in endpoints allow twenty attempts a quarter of an hour, which is the
  limit doing its job. Expect the auth-heavy scripts to hit 429 and say so.
  Point it at one script at a time with `-Only happy-path` if you want a clean
  read, or take the result as "the server answered, and the limiter works".

What this is really for is the first five minutes after a deploy: it tells you
whether the API is reachable, whether the key is right, whether the database
migrated, and whether the admin password took — in one command,
rather than by clicking around the console guessing.

---

## What this costs

Rough shapes, not quotes — check the AWS pricing page and your own billing
console, because free-tier terms change and depend on how old your account is.

- On a **new account inside the 12-month free tier**: `t4g.micro` EC2 and
  `db.t4g.micro` RDS are both covered for 750 hours a month, S3 up to 5 GB, and
  CloudFront's first terabyte out is on the always-free tier. Realistically
  close to nothing.
- **After the free tier**: order of ₹2,000–3,000 a month for the two instances
  plus storage, if they run continuously.

**Set a billing alarm before you start.** Billing → Budgets → a monthly cost
budget with an email alert. Five minutes, and it is the difference between
noticing a surprise and reading about it a month later.

---

## What is still not production

Honest list, so nothing here is a surprise later.

- **One-time codes appear on screen.** Anyone with the access key can sign in as
  any registered number. Wiring MSG91 or Twilio and setting
  `NODE_ENV=production` closes this; the adapter already exists in
  `src/integrations/sms.js` and needs only keys.
- **Emergency alerts are recorded but not sent**, for the same reason. The whole
  path works — the alert is written, the recipients are worked out, the office
  sees it — and the last step reports `simulated` rather than pretending. The
  same SMS keys turn it on, with no other change. Until then the app tells the
  customer plainly to phone somebody themselves, which is the right thing for it
  to say.
- **Uploads live on the instance's disk.** They survive a reboot and do not
  survive the instance being replaced. Moving them to S3 is a change to
  `controllers/uploadController.js`.
- **One instance, no failover.** If it stops, everything stops.
- **No backups configured.** RDS can do automated snapshots — turn them on in
  the instance settings, it is a checkbox.
- **The access key is in the APK.** By design. It is a deterrent, not a wall.
- **A customer or provider number can still be checked.** Asking for a code for
  a number that has no account says so, because the app has to be able to offer
  to create one. The admin and partner sign-ins no longer do this; those two
  were closed on 19 September. This one is the price of a sign-up flow that
  works, and it stops mattering the day SMS is wired up and the code stops
  coming back in the response.

None of these stop you showing the thing working end to end, which is what you
asked for. They are what stands between that and real customers.
