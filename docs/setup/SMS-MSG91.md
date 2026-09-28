# SMS and OTP — MSG91

**Start this first.** Everything here is fast except one step, and that step
takes up to ten working days and cannot be hurried.

---

## Why MSG91

| | MSG91 | Twilio | AWS SNS |
|---|---|---|---|
| Per SMS to India | ~₹0.15–0.25 | ~₹0.60+ | ~₹0.15–0.30 |
| Helps with DLT | Yes, it is their main market | No | No |
| Already coded here | **Yes** | Yes | No |
| Support in IST | Yes | US hours | Ticket only |

Twilio is the better API and the worse choice: four times the price for
India-only traffic, and no help at all with the paperwork below, which is the
part that actually blocks you.

Both are already implemented in `backend/src/integrations/providers/sms.js`,
so if MSG91 disappoints, switching is one environment variable.

**Real cost at our scale:** 1,000 OTPs a month is ₹150–250. The registration
fee below is the only number worth thinking about.

> Treat every price on this page as indicative. Telecom pricing in India moves,
> and portals restructure their fees. Check the live figure before you pay.

---

## 1 · DLT registration — the long pole

TRAI requires every business sending commercial SMS in India to register on a
**DLT** (Distributed Ledger Technology) platform run by a telecom operator. No
provider can bypass this. Not MSG91, not Twilio, not AWS. An unregistered
sender is dropped by the carriers, silently.

You register **three separate things**, in order, each needing the one before it:

1. **Entity** — the business itself. Gets you a 19-digit Entity ID (also called PE ID).
2. **Header** — the 6-character sender name recipients see. We want `SATHYA`.
3. **Templates** — the exact wording of every message we will ever send.

### Pick a portal

Any operator's DLT registration is valid across all operators. Pick one:

| Portal | URL |
|---|---|
| **Jio TrueConnect** (recommended) | trueconnect.jio.com |
| Airtel | dltconnect.airtel.in |
| Vodafone Idea | vilpower.in |
| BSNL | ucc-bsnl.co.in |

Jio is the usual recommendation: the interface is the least painful and
approvals tend to come back fastest. Nothing stops you using another.

### Documents to have ready before you start

- Company **PAN** card
- **GST certificate**, or Certificate of Incorporation if not GST registered
- **Authorised person's PAN and Aadhaar**
- **Letter of Authorisation** on company letterhead, signed — the portal gives
  you a template to copy
- A **company email address on your own domain**. A Gmail address is rejected.
- Company address proof (utility bill or rent agreement)

### Step by step

1. Create an account on the portal with the **company** email address.
2. Choose **Enterprise** registration (not Telemarketer).
3. Fill the entity details exactly as they appear on the PAN card. A mismatch
   of even one character is the most common rejection.
4. Upload the documents above.
5. Pay the registration fee. **Roughly ₹5,000 plus GST**, one time, though this
   varies by operator — confirm the figure on the portal before paying.
6. Wait. **2–7 working days** for the entity to be approved. You get an
   **Entity ID / PE ID** — a 19-digit number. Save it.

### Then register the header

7. Under **Headers**, request a new **Transactional** header: `SATHYA`

   Exactly six characters, letters only, no spaces. It must plausibly relate to
   your registered business name, or it is rejected — "SATHYA" against an
   entity named Sathiyaa is fine.

   Choose **Transactional**, not Promotional. OTPs sent on a promotional
   header are blocked by DND and simply do not arrive.

8. Wait **1–2 working days**.

### Then register the templates

Register these two. The text must match **byte for byte** what we send, so
copy them exactly as written here. `{#var#}` is DLT's placeholder syntax.

**Template 1 — OTP** · category: Service Implicit / OTP

```
Your Sathiyaa verification code is {#var#}. It is valid for {#var#} minutes. Do not share this code with anyone.
```

**Template 2 — Emergency alert** · category: Service Implicit

```
SATHIYAA EMERGENCY: {#var#} has raised an alert at {#var#}. Please call them now. {#var#}
```

Two things about the second one:

- It carries a **map link**. DLT requires every URL in a template to be
  declared and whitelisted separately, under the portal's URL/header section.
  Declare the domain we use for map links — tell me which and I will make the
  code match, or declare `maps.google.com` and I will use that form.
- If the URL whitelisting turns into a fight, say so and I will drop the link
  from the SMS and leave it in the app only. The alert still works.

9. Wait **1–2 working days**. You get a **Template ID** for each. Save both.

**Running total: 4–11 working days, ~₹5,000–6,000.** This is why it is item 1.

---

## 2 · MSG91 account

Do this while DLT is pending — it takes fifteen minutes.

1. Sign up at **msg91.com** with the company email.
2. Complete their KYC — PAN and the same company documents.
3. **Settings → DLT** (sometimes under Compliance): enter your **Entity ID**
   and add the approved **header** and both **Template IDs**. MSG91 will not
   send on a template it does not know about.
4. **Buy credits.** Start with ₹1,000. It is prepaid; there is no bill later.
5. **Settings → API Keys → Auth Key.** Copy it.

Three values come out of this, and one more from MSG91's own OTP panel:

| Value | Where it comes from |
|---|---|
| `MSG91_AUTH_KEY` | MSG91 → API keys |
| `MSG91_SENDER_ID` | The DLT header: `SATHYA` |
| `MSG91_OTP_TEMPLATE_ID` | MSG91's OTP template id for template 1 |
| `MSG91_SMS_TEMPLATE_ID` | MSG91's template id for template 2 |

> MSG91's OTP API wants **its own** template id, created in their OTP section
> and linked to your DLT template — not the raw DLT template id. If the ids you
> have look wrong, that is the distinction that trips people up.

---

## 3 · Switching it on — your server, your keys

SSH to the server and edit `backend/.env`. **Do not paste these values into a
chat, a commit, or a screenshot — including to me. I never need them.**

```
SMS_PROVIDER=msg91
MSG91_AUTH_KEY=...
MSG91_SENDER_ID=SATHYA
MSG91_OTP_TEMPLATE_ID=...
MSG91_SMS_TEMPLATE_ID=...
```

Restart:

```bash
sudo systemctl restart sathiyaa
```

The server prints its integration table at boot. Confirm it says `sms: msg91`
and not `sms: stub`:

```bash
sudo journalctl -u sathiyaa -n 40 --no-pager
```

If a value is missing or malformed the server **refuses to start** and names the
variable. That is deliberate — a server that starts with a broken SMS config
looks healthy right up until nobody can log in.

---

## 4 · Proving it works

Register a new account in the customer app with a **real phone number you
hold**. The OTP should arrive by SMS from `SATHYA` within a few seconds.

Two things change the moment `SMS_PROVIDER` is set, and both matter:

- **The OTP stops coming back in the API response.** While the stub is active,
  the code is returned to the caller so testing works without SMS. With a real
  provider that would be a gaping hole, so it is suppressed.
- **A failed send fails the request.** If MSG91 is out of credits, registration
  returns an error rather than silently creating an account nobody can get into.

---

## What each of us does

| | |
|---|---|
| **You** | DLT entity, header, both templates, MSG91 account, credits, and the five lines in `.env` |
| **Me** | Nothing — it is written. I will re-check the provider against MSG91's current API the day you get the keys, and adjust the template text here if theirs differs |
