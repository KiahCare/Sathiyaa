# Sathiyaa — archived

**This repository is frozen. The code lives in two others now.**

| Where it went | What is in it |
|---|---|
| **[KiahCare/Sathiyaa-apps](https://github.com/KiahCare/Sathiyaa-apps)** | The two Flutter apps — the family's and the carer's. |
| **[KiahCare/Sathiyaa-platform](https://github.com/KiahCare/Sathiyaa-platform)** | The API, the admin console, the integration suite and the deployment. |

Everything was here until 3 October 2026. The two halves ship on completely
different clocks — an APK goes through store review and a user may be versions
behind for a month, while the API and the console go out together in an
afternoon — so holding them on one history meant releasing either one dragged
the other along, and "what changed in the provider app this month" had to be
answered by reading past everything else.

Nothing is lost. This history is the history of both halves up to that date,
and each new repository's `CHANGELOG.md` picks up from `1.1.0`, which is the
state recorded here.

**Do not commit here.** Open a pull request against whichever of the two
repositories above the change belongs in. Both are generated from the working
copy by `scripts/sync-to-github.mjs`, so read their `CONTRIBUTING.md` first —
editing a file in a checkout looks like it worked right up until the next sync
reverts it.

---

<details>
<summary>The README as it stood when this repository was frozen</summary>

Home-healthcare and senior-care booking for India. A family searches for a
carer near them, books a visit, and can see where that carer is on the way;
the carer runs their day from their own app; an agency manages the carers it
employs; and an administrator approves providers, signs new ones up, sets
prices and watches the money.

Launching in Ahmedabad and Gandhinagar, Gujarat.

| Folder | Stack | What it is |
|---|---|---|
| `apps/customer_app/` | Flutter / Dart | The family's app. Search, book, pay, track, message, SOS. |
| `apps/provider_app/` | Flutter / Dart | The carer's and the agency's app. One binary, two shapes. |
| `backend/` | Node.js 20+, Express 4, MySQL 8 | 145 endpoints, 39 tables, 17 ordered migrations. |
| `admin-portal/` | React 19, TypeScript, Vite | Two portals in one app, separated by role. |
| `docs/` | — | Architecture, API contract, schema, ERD, test plans, deployment runbook. |
| `tests/` | Node | 29 integration scripts that drive the real API over HTTP. |
| `scripts/` | PowerShell, Node | Build, packaging, deployment and maintenance tooling. |

Versions at the time of freezing: API and admin console 1.1.0, customer app
1.1.0+2, provider app 1.1.0+2. Three languages throughout — English, Hindi and
Gujarati — including the apps' own screens.

The full README, the changelog, the architecture documents and `SECURITY.md`
are all in the two repositories above, kept current.

</details>
