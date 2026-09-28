# Push notifications — Firebase Cloud Messaging

**There is no decision to make here.** FCM is how Android delivers push
notifications. Every alternative — OneSignal, Airship, Pusher — is a wrapper
that calls FCM underneath and charges for the wrapping. We call it directly.

**Cost: free.** Unlimited messages, no tier, no card. Google has never charged
for FCM and the paid Firebase plan is about other products.

Twenty minutes of your time. The server side is already written
(`backend/src/integrations/providers/fcm.js`); the app side is not.

---

## What is missing today, honestly

The provider that talks to Google is written and tested. What is missing is
the other end: **nothing records which handset belongs to which account**, so
there is nowhere to send a notification even with keys in place. That is the
part I build — see "What I build" at the bottom.

---

## 1 · Create the Firebase project

1. Go to **console.firebase.google.com** and sign in with the Google account
   you want to own this. Use a company account, not a personal one — moving a
   Firebase project between owners later is tedious.
2. **Create a project** → name it `Sathiyaa`.
3. Google Analytics: **turn it off.** We do not use it, and leaving it on adds
   a consent obligation under the DPDP Act for no benefit.
4. Wait for it to provision, about a minute.

---

## 2 · Register both Android apps

Two apps, two registrations. The package names must be exact:

| App | Package name |
|---|---|
| Customer | `in.sathiyaa.customer` |
| Provider | `in.sathiyaa.provider` |

For **each** of them:

1. Project overview → **Add app** → the Android icon.
2. **Android package name**: exactly as in the table above. A typo here
   produces an app that builds fine and never receives a notification.
3. **App nickname**: `Sathiyaa Customer` / `Sathiyaa Provider`.
4. **SHA-1**: leave blank. It is only needed for Google Sign-In, which we do
   not use.
5. **Download `google-services.json`.**

You now have two files with the same name. Keep them apart — put each in its
own folder named after the app. Getting them the wrong way round is the second
most common way this fails.

Skip the rest of Firebase's wizard ("Add Firebase SDK", "Run your app"). That
is the part I do.

**Send me both files.** These are not secrets — they ship inside the APK and
anyone can extract them. The private key in step 3 is a different matter.

---

## 3 · The server key

This one **is** a secret. It can send a notification to every user we have.

1. Gear icon → **Project settings** → **Service accounts**.
2. **Generate new private key** → confirm. A `.json` file downloads.
3. Open it in a text editor. Three values matter:

| In the JSON | Goes into `.env` as |
|---|---|
| `project_id` | `FCM_PROJECT_ID` |
| `client_email` | `FCM_CLIENT_EMAIL` |
| `private_key` | `FCM_PRIVATE_KEY` |

4. Put them into `backend/.env` **on the server, yourself**:

```
PUSH_PROVIDER=fcm
FCM_PROJECT_ID=sathiyaa-xxxxx
FCM_CLIENT_EMAIL=firebase-adminsdk-xxxxx@sathiyaa-xxxxx.iam.gserviceaccount.com
FCM_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMIIEv...\n-----END PRIVATE KEY-----\n"
```

The private key runs over many lines in the JSON file. **Keep the `\n`
sequences exactly as they appear there and wrap the whole thing in double
quotes.** Pasting the key with real line breaks is the single most common
mistake with FCM, and it fails at boot rather than silently, which is at least
honest.

5. Delete the downloaded JSON once the values are in `.env`. It is a
   credential sitting in your Downloads folder.

6. Restart and confirm the boot table says `push: fcm`:

```bash
sudo systemctl restart sathiyaa && sudo journalctl -u sathiyaa -n 40 --no-pager
```

---

## What I build

| Piece | What it is |
|---|---|
| `push_token` on `user_devices` | The device registry already exists (migration 008) and knows which handset belongs to which account. It just has nowhere to put the token. One migration adds the column |
| Registration endpoint | The app sends its token after login and whenever Google rotates it |
| Flutter side | `firebase_messaging` in both apps, permission prompt on Android 13+, foreground and background handlers, tapping a notification opening the right screen |
| The actual notifications | Booking requested, accepted, declined, carer on the way, carer arrived, visit complete, payment due, registration approved or rejected, broadcast from the console |

The last row is the real work. The rest is plumbing.

**Roughly a week.** The permission prompt on Android 13+ and the
notification-tap routing are where the time goes, not the sending.

---

## What each of us does

| | |
|---|---|
| **You** | Firebase project, two app registrations, two `google-services.json` files to me, three values into `.env` |
| **Me** | Token column, registration endpoint, both Flutter apps, and every event that should notify somebody |
