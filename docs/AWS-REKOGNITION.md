# Turning on the face check

Sathiyaa's arrival check has two halves. The geofence half is real already —
a carer who is not at the address is refused, and always has been. The face
half has been a stub that says yes to everything.

This turns the face half on, using AWS Rekognition. About twenty minutes, all
of it in a browser, and nothing here needs a developer.

**Nothing in this document asks you to send a key to anybody.** The two values
you create go from your AWS console into one file on your own server, and
that is the only place they ever exist.

---

## What it actually does, and what it does not

Rekognition's `CompareFaces` answers one question: **are these two
photographs the same person?** Sathiyaa sends the selfie the carer takes on
arrival and the photograph on their approved profile, and gets back a
similarity score.

It does **not** answer "is there a live human in front of the camera". A
printed photograph held up to the lens compares as a match. AWS sells a
separate service for that (Rekognition Face Liveness) which is more expensive
and needs work in the app as well.

That is less of a hole than it sounds, because the two halves run together:
faking the check means standing at the family's front door holding a
photograph of the carer whose visit it is. If someone has gone that far, a
liveness check is not what stops them.

---

## What it costs

Region `ap-south-1` (Mumbai), which is where Sathiyaa already runs:

| | |
|---|---|
| Free tier | 5,000 images a month, for the first 12 months |
| After that | **$0.001 per image** for the first million a month |

One arrival check is one `CompareFaces` call. So:

- **500 visits a month** — free for the first year, then about **₹45/month**
- **2,000 visits a month** — about **₹180/month**
- **10,000 visits a month** — about **₹900/month**

At Sathiyaa's size this is a rounding error next to the EC2 bill. It is worth
knowing that a *failed* check costs the same as a successful one, so a carer
retrying three times costs three calls.

There is no monthly minimum, no instance to leave running, and nothing to
turn off. If nobody starts a visit, it costs nothing.

---

## Step 1 — Create the IAM user

The key you are about to make can do exactly one thing. That is deliberate:
it will sit in a file on a server, and a key that can only compare two faces
is a key that cannot empty your account if it ever leaks.

1. Sign in to the AWS console and open **IAM**.
2. **Users** → **Create user**.
3. Name it `sathiyaa-face-check`. Leave "Provide user access to the AWS
   Management Console" **unticked** — this user is for the server, not for a
   person.
4. **Next** → **Attach policies directly** → **Create policy**.
5. Choose the **JSON** tab and replace everything in the box with:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "rekognition:CompareFaces",
      "Resource": "*"
    }
  ]
}
```

6. **Next**, name the policy `SathiyaaCompareFacesOnly`, **Create policy**.
7. Back on the user screen, refresh the policy list, tick
   `SathiyaaCompareFacesOnly`, **Next**, **Create user**.

`Resource: "*"` looks alarming and is not. `CompareFaces` takes image bytes in
the request and touches nothing stored in your account, so there is no
resource to narrow it to.

---

## Step 2 — Create the access key

1. Open the user you just made → **Security credentials** tab.
2. **Create access key** → **Application running outside AWS** → **Next** →
   **Create access key**.
3. You are shown an **Access key ID** and a **Secret access key**.

**The secret is shown once.** Copy both into a password manager now. Do not
paste them into a chat, an email, a ticket, or a file in the project folder.
If you lose the secret, delete the key and make another — that costs nothing.

---

## Step 3 — Put them on the server

SSH to the EC2 instance and edit the server's own `.env`:

```bash
ssh -i your-key.pem ec2-user@<your-ec2-public-ip>
nano /opt/sathiyaa/backend/.env
```

Add these five lines at the end, pasting your own two values:

```
FACE_PROVIDER=rekognition
AWS_REGION=ap-south-1
AWS_ACCESS_KEY_ID=<the access key id>
AWS_SECRET_ACCESS_KEY=<the secret access key>
FACE_MATCH_THRESHOLD=0.6
```

Save (`Ctrl+O`, `Enter`, `Ctrl+X`) and restart:

```bash
sudo systemctl restart sathiyaa
sudo systemctl status sathiyaa --no-pager
```

`redeploy.ps1` never overwrites this file — the archive it uploads does not
contain a `.env` — so the keys survive every future deploy.

---

## Step 4 — Check it actually works

On the server:

```bash
sudo journalctl -u sathiyaa -n 40 --no-pager | grep -i face
```

The boot table should now say `Face match: rekognition` rather than `stub`.
If a key is missing the server **refuses to start** and names the variable —
that is on purpose, so a half-configured face check cannot pretend to work.

Then a real end-to-end test, which is the only one worth trusting:

1. In the admin console, make sure a test carer has a **clear photograph** on
   their profile. This is the reference image; everything depends on it.
2. From the provider app on a phone, start a visit and take the selfie.
3. It should pass. Then have somebody else take the selfie — it should fail
   with "the face did not match".

---

## Choosing the threshold

`FACE_MATCH_THRESHOLD` is how similar is similar enough, between 0 and 1.

| Value | What it means |
|---|---|
| 0.5 | Loose. Fewer complaints, more chance of accepting the wrong person |
| **0.6** | The default. Sensible for a photograph taken in a stairwell |
| 0.8 | Strict. AWS's own recommendation for identity verification |
| 0.9 | Very strict. Expect real carers to be refused in bad light |

Start at 0.6. The failure that matters here is not a false match — it is a
real carer standing outside a house at 8am being told they are not
themselves. Raise it once you have seen a month of real arrivals, not before.

---

## What to expect in the field

The reference photograph does most of the work. A blurry, badly lit or
five-year-old profile photo will fail against a perfectly good selfie, and
the carer will have no idea why.

So before switching this on:

- go through the approved carers in the console and replace any photograph
  you would not recognise somebody from;
- tell carers the check exists, and that a failure means retake the photo in
  better light rather than something is wrong with your account.

The app already handles failure gracefully — the visit cannot start, the
carer is told why, and support can override — but the first week will
generate calls. Turning it on quietly is the way to get complaints you cannot
explain.

---

## Turning it off again

Set `FACE_PROVIDER=stub` in `.env` and restart. The geofence half keeps
working. Nothing in the database changes, and the carer's profile photos stay
where they are.

---

## Where the code is

| | |
|---|---|
| The adapter | `backend/src/integrations/providers/awsRekognition.js` |
| Provider choice | `backend/src/integrations/faceMatch.js` |
| Settings | `backend/src/config/env.js` (`aws`, `faceMatch`) |
| Where it is called | `providerSelfController.js`, start-of-service |
| Self-test | `scripts/check-rekognition.mjs` |

The adapter signs its own requests rather than pulling in the AWS SDK —
forty-odd packages for one HTTP call, on a free-tier box that reinstalls its
dependencies on every deploy. There is nothing to `npm install`.
