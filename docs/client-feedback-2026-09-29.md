# Admin console — client observations, 29 September 2026

Seven observations from the client, what each turned out to be, and what was
done. Three were real bugs, two were things that existed but were not findable,
one was a genuine missing feature, and one was a question with a product
decision behind it.

---

## 1 · Search does not bring the result to the top

**A real bug, and worse than reported.** The search did nothing at all.

The console has always had the box and has always sent the term. The server
read `status` from the query string and ignored `search` entirely, so typing
"Meena Joseph" reloaded the same unfiltered list in registration order. She was
not failing to come to the top — she was never being searched for.

It worked in the demo build, which filters in the browser. That is why it was
not caught: the two halves disagreed, and only the live one was wrong.

**Fixed** in `backend/src/controllers/adminController.js`. Search now matches
name, ID, mobile number and email, and results are **ranked**:

| Rank | Match |
|---|---|
| 1 | Name is exactly the term |
| 2 | Name starts with the term |
| 3 | ID or mobile number is exactly the term |
| 4 | Name contains the term |
| 5 | Matched on something else |

"Meena Joseph" now returns Meena Joseph first.

**The customer list had the same bug** and the same fix. Nobody had reported it
yet; they would have.

---

## 2 · No provision to upload details of a Service Provider

**Correct, and it is a real gap.** Today a carer can only arrive two ways:
they register in the provider app themselves, or an agency adds them from the
agency's own account. An administrator cannot enter one.

That is wrong for how this business actually signs people up. A carer met at a
hospital, or one who gives their documents on paper, has no route into the
system at all.

**Not built yet — it is a feature, not a fix.** It needs a form covering
everything registration collects, document upload from the console, duplicate
detection against the mobile number, and a decision about whether an
admin-created carer is approved on the spot or still goes through review.

**Estimate: 3–4 days.** Not built yet; queued next.

**Decided:** a carer an administrator enters lands in **Pending**, not approved
on the spot. The person typing the details is rarely the person who checked the
documents, and collapsing those two steps is how an unverified carer reaches a
family.

---

## 3 · Approval and Status contradict each other

**A fair criticism.** They are two different facts and the console presented
them as one, so "Approval: Rejected" beside "Status: Active" read as a
contradiction rather than as two true statements.

They mean:

- **Approval** — their paperwork. Whether we have checked this person and will
  put them in front of a family.
- **Status** (now **Account**) — their login. Whether they can sign in at all.

They are independent **on purpose**. A carer rejected for a missing police
check keeps a working account, so they can re-upload the document and be
approved without registering from scratch. Tying the two together would mean
every rejection destroys an account, and every correction means starting again.

**Changed:**

- "Status" is now labelled **Account**, which is what it is.
- A new **Bookable** column answers the question people were actually asking:
  can a family find and book this person right now? It needs both — approved
  *and* not blocked — and hovering it says why when the answer is no.
- A paragraph at the top of the page explains all three.
- The profile view states the conclusion in words above the badges.

---

## 4 · Capture comments when the status is On Hold or Rejected

**Already there** — both actions have always required a note, and neither can
be confirmed without one.

The problem was that the note was only visible **after opening the profile**, so
a list of rejections gave no hint why any of them happened. Reasonable to
conclude it was never captured.

**Changed:** the reason now appears under the Approval badge in the list, and
the profile shows it as "Reason given" with the date it was recorded.

---

## 5 · What is the Remove button for?

**Fair — the label explained nothing.** It deletes a registration outright, and
is meant for junk sign-ups and leftover test accounts, of which automated test
runs leave dozens.

It is **not** the tool for a carer who misbehaves. That is **Block**, which
keeps the person, their history and the audit trail while stopping them working.
The server already refuses to delete any account with booking history and says
so, so the button cannot destroy anything real — but nothing on screen said any
of that until you had already clicked it.

**Changed:** relabelled **Delete registration**, with a hover explaining what
it does and pointing at Block as the usual answer.

---

## 6 · Add Gandhinagar

**Done.**

Worth knowing: Gandhinagar was **already served**, by distance. It is 30 km
from the Ahmedabad centre, inside the 35 km radius, so anyone registering there
with working location services was already let in.

The gap was the other route. A phone that refuses the location prompt, or gives
a bad indoor fix, falls back to the city name — and "Gandhinagar" matched
nothing, so those people were turned away from a city we serve. Exactly the
people least likely to try twice.

**Changed:** the service area now holds a **list** of cities rather than one.
Configuration reads *Cities*, accepts them comma-separated, and shows what it
parsed as you type. The live value is now `Ahmedabad, Gandhinagar`.

Opening a third city is now a value typed into the console. No deployment, no
app release.

One related fix came with it. City matching was deliberately loose so that
"Ahmedabad District" and "Ahmadabad" both count — but it matched a name
appearing *anywhere*, and "Nagar" is inside "Gandhinagar" and is also the name
of half the localities in Gujarat. With one city that was harmless; with a list
it would have let places we do not serve register. Matching is now anchored to
the front of the name, which keeps every lenient case and drops that one.

---

## 7 · Where is the Business Partner login?

**It exists** — and there are two different things this could mean, which is
probably the root of the question.

### Business Partners (referral partners) — have a web login already

Same address as the admin console, same login box. Signing in with a business
partner's credentials lands on their own pages:

- **My Referrals** — everyone they have referred and where each one got to
- **My Revenue** — what they have earned

They see only their own data. Create their account under **Business Partners**
in the admin console, which is also where their credentials come from.

A referral partner has **no employees**. They introduce customers and earn a
share. So if "their employees and their allocation" is the question, it is
about the other thing:

### Organisations (agencies) — have this, but only on the phone

An agency that employs carers already has all of it, in the **provider app**:

- Employees — add, edit, and see every carer they employ
- Schedule overview — who is booked, when
- Utilisation — how busy each carer is

**What does not exist is a web console for agencies.** An agency owner managing
twenty carers is doing it on a phone.

### Clarified, and done

The client meant the **admin web panel**. Two things were behind the question,
and both are now fixed.

**The login was never missing.** It is this same console at the same address —
the login box has an Admin / Business Partner toggle on it. Nothing anywhere
said so, so it was invisible. The Business Partners page now explains it in a
line at the top.

**The allocation genuinely was missing**, and for a worse reason than "no
screen for it". `POST /admin/business-agents/referrals/:id/allocate` picked a
matching carer, set the referral to `booked`, returned that carer's name — and
**stored nothing**. The name went back in one HTTP response and was gone.
Reopen the partner a minute later and the referral said `booked` with no way to
find out who had been sent. The allocation was not hidden; it was never written
down. On top of that, nothing in the console ever called the endpoint, so a
referral could not be moved off `pending` by anybody at all.

**Changed:**

- Migration `017_referral_allocation.sql` adds `allocated_provider_id`,
  `allocated_at` and `allocated_by` to `business_agent_referrals`.
- `allocateReferral` writes them, and reports how many *other* carers matched —
  "the only carer who matched" is worth knowing when you allocate, not on the
  morning of the visit.
- The referral list joins the carer in by name, ID and mobile number.
- The partner detail view has an **Allocated carer** column and an **Allocate**
  button on every unallocated referral.

Proven end to end in the demo build: clicked Allocate, got *"Allocated to
Kavitha Kumar — the only carer who matched, so there is no fallback if they
drop out"*, and the row now names her.

### What is still not connected

Allocating records a carer. It does **not** yet create a booking or link a
customer account, so partner revenue — which is computed from bookings carrying
that partner's referral code — still reads zero until a real booking exists.

That last step needs a decision that is yours, not mine:

**When an administrator allocates a referral, should the system create the
customer's account there and then, or wait until that person registers in the
app themselves?**

Auto-creating means the partner's referral becomes revenue immediately, and it
means accounts existing for people who never asked for one. Waiting is cleaner
and slower. The answer changes the shape of the rest of the feature, so it is
worth deciding before anything else is built on top.

### Agencies are a separate thing, and still phone-only

An agency that employs carers already has employees, schedule overview and
utilisation — in the **provider app**, not the console. If the client also wants
that on a computer, it is a third role in the console reusing endpoints that
already exist. **Roughly a week.** Not started, because this was not that.

---

## What changed in the code

| File | Change |
|---|---|
| `backend/src/controllers/adminController.js` | Search implemented and ranked, for providers and customers; service-area city list tidied on save |
| `backend/src/services/serviceArea.js` | Multiple cities; city matching anchored to the front of the name |
| `backend/src/db/migrations/016_service_area_multiple_cities.sql` | Sets the live value to `Ahmedabad, Gandhinagar` |
| `admin-portal/src/pages/admin/ServiceProviders.tsx` | Account column, Bookable column, explanation, reason in the list, Delete relabelled |
| `admin-portal/src/pages/admin/Configuration.tsx` | Cities instead of City, with validation and live parsing |
| `_tests/service-area-and-fees.mjs` | Gandhinagar by name alone; a place called "Nagar" is still refused |
| `backend/src/db/migrations/017_referral_allocation.sql` | Referrals remember which carer was allocated |
| `backend/src/controllers/businessAgentController.js` | Referral list joins the allocated carer by name |
| `admin-portal/src/pages/admin/BusinessAgents.tsx` | Allocated carer column, Allocate button, partner-login note |
| `admin-portal/src/api/services.ts`, `types/index.ts` | `allocateReferral` and the allocation fields |

**Verified:** `tsc -b` clean, every backend file parses, and the search
escaping, placeholder counts and city matching were each exercised against the
real source. The console was built and driven in a browser: the Approval /
Account / Bookable columns render, hold reasons show in the list, and Allocate
was clicked through to a named carer that persisted on reload.

**Not verified:** anything needing MySQL. The local database is not running, so
migrations 016 and 017 have not been applied, the ranked SQL search has not been
run against real rows, and the two new integration tests have not executed. All
of that happens on the next deploy.

**Nothing here is live yet.** These changes are in source and in a fresh build;
the running console on CloudFront and the API on EC2 are still on the previous
version until someone redeploys.

**Still open:** item 2 (queued, decided), and the customer-creation question
under item 7.
