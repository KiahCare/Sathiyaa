# Contributing — Sathiyaa

## The one rule that is not obvious

**Nothing in this repository is edited directly.**

It is generated. The working copy lives on the build machine, and
`scripts/sync-to-github.mjs` copies the publishable part of it here. Edit a file
here and the next sync overwrites it from the laptop and silently reverts the
work — the file is there, git sees the change, and then it is gone.

Two files are the exception, because git itself reads them and they have no
meaning outside a repository: `.gitignore` and `.gitattributes`. Everything
else a human writes — this file, the README, `CHANGELOG.md`, `SECURITY.md`, the
architecture docs — is authored on the laptop under `_docs\` and copied in.

The sync works from an allowlist, not an ignore list: a file is copied because
a rule names it. Then every copied file is scanned for the live secret values —
read at run time from a file that is never published — plus seven patterns for
cloud keys, private key blocks and provider tokens. A hit aborts the sync
before anything is staged. **If it refuses, fix the source.** Do not weaken the
check to get past it.

```
scripts\sync-to-github.ps1 -DryRun     see what would change
scripts\sync-to-github.ps1             do it
```

It prints what was added, changed and removed, file by file, which is what a
commit message should be written from.

## The split that is coming

The Flutter apps and the platform ship on completely different clocks — an APK
goes through store review and a user may be versions behind for a month, while
the API and the console go out together in an afternoon. So the project is
being split in two:

| | |
|---|---|
| `sathiyaa-apps` | `apps/customer_app`, `apps/provider_app` |
| `sathiyaa-platform` | `backend`, `admin-portal`, `tests`, deployment |

Both are already prepared and staged locally with their own READMEs and
changelogs, waiting on the repositories being created on GitHub. **Until that
happens this repository is the live one**, and the sync writes here by default:

```
scripts\sync-to-github.ps1                   this repository (the default)
scripts\sync-to-github.ps1 -Only apps        the staged sathiyaa-apps
scripts\sync-to-github.ps1 -Only platform    the staged sathiyaa-platform
```

Work normally here. The split is a move, not a rewrite; nothing you do now has
to anticipate it.

## Before you commit

**Record the change in `CHANGELOG.md`.** Every change, however small. A typo
fix is one line. "No visible change" is itself worth saying, because somebody
will later be working out why a build behaves differently and the absence of an
entry tells them nothing.

Write it for the person who will read it in six months, not for the person who
just made it:

- Say what somebody can now do, or what no longer happens. Not which function
  was edited.
- For a fix, say what went wrong and **what the symptom was**. A fix with no
  symptom described cannot be recognised by whoever hits it again.
- Four things ship from here and they version independently, so say which — the
  API, the console, the customer app, the provider app, or several.
- Put it under `Added`, `Changed`, `Fixed`, `Removed`, `Deprecated`, `Security`,
  `Documentation` or `Repository`, under `## [Unreleased]`, and move it into a
  release heading when it ships.

Then run whatever covers what you touched:

```bash
cd admin-portal  && npx tsc -b && npx oxlint src
cd tests         && pwsh run-all.ps1
cd apps/customer_app && flutter analyze && flutter test
cd apps/provider_app && flutter analyze && flutter test
```

`tsc -b`, `flutter analyze` and the integration suite are the three that catch
real problems. Run the whole integration suite, not just the script matching
the file you touched — most of what has gone wrong here has gone wrong two
modules away from the edit.

`tsc -b` must be silent, `flutter analyze` must be clean on both apps, and
`oxlint` must report no errors. It currently reports **ten warnings**, and they
are known rather than ignored — do not add an eleventh without reading these:

- Nine are `react(set-state-in-effect)` on `useEffect(() => { load(); }, [])`,
  where `load()` clears the error state before fetching. The rule's advice is to
  derive the value during render, which cannot be done for an asynchronous
  fetch; this is the ordinary mount-time load pattern and is correct as written.
- One is `react-hooks(exhaustive-deps)` in `Tracking.tsx`, for a cleanup
  function reading `markersRef.current`. That ref holds a `Map` created once and
  never reassigned, so the value the cleanup sees is the value it meant.

The rules are left switched **on** rather than configured away, because
switching one off would also hide the next genuine instance.

## Versioning

Four components, versioned where they are defined and nowhere else:

| Component | File | Bump with |
|---|---|---|
| Backend API | `backend/package.json` | `npm version <level> --no-git-tag-version` |
| Admin console | `admin-portal/package.json` | the same |
| Customer app | `apps/customer_app/pubspec.yaml` | by hand |
| Provider app | `apps/provider_app/pubspec.yaml` | by hand |

The API and the console share one number and move together. Bump in the same
commit as the change.

**API and console**, from the point of view of the installed app builds that
are the real clients:

| | when |
|---|---|
| patch | a fix that changes no request or response shape |
| minor | a new endpoint, or a new optional field; every existing build keeps working |
| major | anything an installed APK would break on |

A removal or a rename is **major** even when every current app build has
already stopped using it, because an APK on somebody's handset cannot be made
to send a field it was never built to send.

**Apps**, as `<semver>+<build>`:

| | when |
|---|---|
| patch | a fix with no visible change to how the app is used |
| minor | a new screen, a new field, a visible change somebody would notice |
| major | a redesign, or a release that will not work against an older API |

**The build number after the `+` increases on every build that leaves this
machine**, including a rebuild of the same version, because that is the number
a crash report carries and two different binaries claiming the same build
number cannot be told apart afterwards.

Each version is readable at run time, from the manifest, so no copy can go
stale: the API at `GET /health`, the console in its sidebar footer, both apps
on the Server screen.

## Writing code here

Match what is already there. Three things in particular:

**Comments explain why, not what.** The codebase is full of comments that
record a decision and the bug that forced it, and they are worth more than the
code around them. If you fix something subtle, write down what the symptom was.
`backend/src/services/providerMatching.js` and
`backend/src/services/providerAccounts.js` are the house style.

**One place per decision.** The expensive bugs in this project's history are
all the same shape: the same rule written out in two places, and then one of
them changed. An approval status was compared in three places and two of them
were wrong, so an approved carer was shown a red "Not approved" chip. Creating a
provider wrote thirty columns from three separate INSERTs, and they drifted.
Before adding a second copy of something, move the first one somewhere both can
reach.

**Validation belongs where the client is known.** `/auth/provider/register` is
deliberately permissive because installed APKs call it. `/admin/providers` is
strict because only the console does, and the console is served fresh on every
page load. Do not "tidy up" the first one to match the second.

## Database changes

Migrations are numbered, ordered and never edited once they have run anywhere.
Add `0NN_what_it_does.sql` in `backend/src/db/migrations/` and nothing else —
`migrate.js` picks it up by name. Then update `docs/schema.sql` and the ERD so
the documentation and the database do not drift.

A new column the apps will send needs a line in
`controllers/providerSelfController.js`'s field map **and** in
`services/providerAccounts.js`, or it will be accepted on update and dropped on
create. That has happened twice.

## The apps

Two things will otherwise surprise you:

**The two apps share files, and the sync goes one way: customer → provider.**
`scripts/sync-design.ps1` copies the theme, widgets, i18n plumbing and the
service-area gate from `apps/customer_app` into `apps/provider_app` on every
build. **Edit a shared file in `customer_app`.** Edit it in `provider_app` and
the next build silently reverts it. Anything that belongs only to the provider
app needs its own file — `provider_app/lib/utils/approval.dart` exists for
exactly this reason and says so at the top.

**Translations are keyed by their English sentence**, not by an identifier, so
rewording the English orphans the Hindi and Gujarati silently. A test catches
the orphan but not the missing translation — when you add or change a string,
add it to `lib/i18n/strings_hi.dart` and `lib/i18n/strings_gu.dart` in the same
edit. Interpolation is `t('Version {v}', {'v': x})`, never concatenation,
because word order differs between the three languages.

## Security

Read [`SECURITY.md`](SECURITY.md) before touching authentication, uploads, the
access key or the audit log. It lists what is deliberately not finished yet and
why, so a gap that is known is not "fixed" into something worse by accident.
