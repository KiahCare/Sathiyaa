# Uploaded documents — move to Amazon S3

This is the one item on the list that fixes a live security problem rather
than adding a feature.

---

## What is wrong today

**Three things, in order of seriousness.**

### 1 · The documents are served without authentication

`backend/src/app.js` mounts `/uploads` with `express.static`. The access-key
gate is applied to `/api/v1`. Different prefix, applied afterwards, so it
**never covers `/uploads`**.

Anyone holding the URL of an uploaded aadhaar card, police verification,
medical certificate or prescription can fetch it. No key, no login, no token,
and no record that they did.

The filenames carry 64 bits of randomness, so nobody guesses one. But that is
the only thing protecting them, and it is a one-way door: a URL that leaks
once — in a log file, a screenshot pasted into WhatsApp, a browser's referrer
header, a forwarded email — is valid for ever and cannot be revoked.

These are identity documents belonging to carers who have not been asked
whether that is acceptable.

### 2 · Replacing the instance deletes every file

They live on the EC2 machine's own disk at `/var/lib/sathiyaa/uploads`. A
redeploy is safe. **Rebuilding or replacing the instance is not** — and
migrating to the new AWS account will do exactly that.

### 3 · There is no backup at all

No snapshot, no copy. If that volume fails, every document uploaded since
launch is gone and every carer has to be asked to submit their papers again.

### And it will run out

20 GB shared with the OS, Node and the application. Realistically **12–15 GB**
for uploads, about **7,000 carers** at ~2 MB each. Not urgent. Not far away
either.

---

## Why S3

| | Instance disk (today) | **S3** |
|---|---|---|
| Durability | One volume, no backup | 99.999999999%, replicated |
| Survives instance replacement | **No** | Yes |
| Access control | None — URL is the only secret | Private bucket, links that expire |
| Capacity | ~13 GB | Unlimited |
| Cost at 50 GB | (fills the disk) | **about ₹100/month** |

There is no serious alternative while we are on AWS. Cloudflare R2 is cheaper
on egress and would mean leaving the one place all the other pieces live.

---

## 1 · Create the bucket

1. **S3 console** → **Create bucket**. Region **ap-south-1 (Mumbai)** — the
   same region as everything else, or every read pays to cross the country.
2. Name: `sathiyaa-uploads-prod`. Bucket names are globally unique, so add
   digits if it is taken.
3. **Block all public access: LEAVE ON.** All four boxes ticked.

   This is the whole point. Nothing in this bucket is ever public. The app
   hands out links that work for a few minutes and then stop.

4. **Bucket Versioning: Enable.** A deleted or overwritten document is
   recoverable. Pennies at our volume.
5. **Default encryption: SSE-S3.** On by default; confirm it.
6. Create.

## 2 · Expire old versions

Versioning without a lifecycle rule means storage that only grows.

**Management → Create lifecycle rule** → name `expire-old-versions` → apply to
all objects → **Permanently delete noncurrent versions after 90 days**.

## 3 · An IAM user that can do nothing else

**IAM → Users → Create user** → `sathiyaa-s3-uploads`. **No console access.**

Attach an inline policy — replace the bucket name if yours differs:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"],
    "Resource": "arn:aws:s3:::sathiyaa-uploads-prod/*"
  }]
}
```

Three actions, one bucket. A leaked key here cannot read another bucket,
cannot touch the database, cannot start an instance, cannot raise the bill.
Compare that to a key with `AmazonS3FullAccess`, which is what most people
paste in and regret.

**Security credentials → Create access key → Application running outside AWS.**
Copy both values straight into the server's `.env`. Do not put them in a file
on your laptop, and do not send them to me.

## 4 · Switch it on

```
STORAGE_PROVIDER=s3
S3_BUCKET=sathiyaa-uploads-prod
S3_REGION=ap-south-1
S3_ACCESS_KEY_ID=AKIA...
S3_SECRET_ACCESS_KEY=...
UPLOAD_URL_TTL_MINUTES=10
```

```bash
sudo systemctl restart sathiyaa && sudo journalctl -u sathiyaa -n 40 --no-pager
```

## 5 · Move what is already there

I will write `backend/scripts/migrate-uploads-to-s3.mjs`. It copies every file
up, rewrites the stored paths, and **verifies each one is readable from S3
before deleting the local copy**. It can be run twice safely.

Run it yourself on the server, once, after step 4.

---

## What changes for the people using it

**Nothing visible.** The console still shows "View / Download"; the apps still
show photographs. The difference is that the link behind the button is minted
when you click it, carries a signature, and stops working ten minutes later.

An administrator who copies a document link and pastes it into an email is
sending something that expires — which is the behaviour we want, because they
will do that.

---

## What I build

| Piece | Detail |
|---|---|
| S3 storage provider | Behind the same interface the local one uses, chosen by `STORAGE_PROVIDER`. Signed by hand with `node:crypto`, like the Rekognition provider — no SDK, nothing new to audit |
| Presigned reads | Short-lived signed URLs, minted per request by someone already authenticated |
| **Close `/uploads`** | The static mount goes. Every document is fetched through an authenticated endpoint that checks *who is asking* before it mints a link |
| Migration script | As above |

**Two to three days.** It is the highest value-per-day item on the whole list.

---

## What each of us does

| | |
|---|---|
| **You** | Bucket, lifecycle rule, IAM user, six lines in `.env`, run the migration script once |
| **Me** | Storage provider, presigned links, closing the open path, the migration script |
