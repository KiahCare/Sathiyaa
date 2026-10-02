# Architecture — Sathiyaa apps

Two Flutter apps that are deliberately built the same way. Read this before the
code; most of what would otherwise look odd is explained here.

The API they talk to is documented in `docs/api-contract.md` and the platform's
own `ARCHITECTURE.md` — in this repository while the project is one, and in
**sathiyaa-platform** once the split lands.

## The two apps

| | `customer_app` | `provider_app` |
|---|---|---|
| Who | the family | the carer, and the agency |
| Does | search, book, pay, track, message, SOS | accept work, run the visit, get paid, manage staff |
| Shapes | one | **two** — a freelance carer sees their own day; an organisation sees its people |

The provider app being one binary with two shapes is the single biggest thing
to hold in your head. `ProviderProfile.isOrganisation` decides it, and
`screens/organization/` is the half that only an agency ever reaches.

## The layout, in both apps

```
lib/
  main.dart              app entry, theme, routing
  backend.dart           ★ the seam: interface + which implementation is in use
  api/
    api_client.dart      HTTP, headers, error translation
    api_backend.dart     the only file that knows the API's JSON shapes
  mock_data.dart         a full in-memory dataset for demo mode
  models.dart            the domain types
  screens/               one file per screen, or per cluster of related screens
  widgets/               shared presentation pieces
  theme/                 palette + the design system
  i18n/                  l10n plumbing and the Hindi/Gujarati string tables
  services/              device info, geocoding, location
  utils/                 dates, money, formatting
```

## The seam: `backend.dart`

Everything a screen is allowed to ask for is declared on one abstract class.
Two implementations satisfy it:

```
SathiyaaProviderBackend  (abstract)
  ├── MockBackend        in memory, full demo dataset, no server at all
  └── ApiBackend         the real Express + MySQL API
```

Screens only ever touch `Backend.instance`. What decides which one is whether
an API address was compiled in (`--dart-define=API_BASE_URL=...`), and there is
a Server screen in both apps for pointing a build at a different one at
runtime.

**This matters more than it looks.** Demo mode is what gets shown to people —
on a plane, in a meeting, with no network. A new API call that has no mock
implementation does not fail loudly; it loses a screen in the demo. Add both.

## Talking to the API

`api_backend.dart` is the only file that knows what the server's JSON looks
like. Everything above it deals in `models.dart` types.

Two conventions it follows, both learned the hard way:

- **Reads are tolerant.** `pick(m, ['providerKind', 'provider_kind'])` accepts
  either spelling, because read endpoints hand back database rows and write
  endpoints take camelCase, and both shapes have been seen for the same field.
- **Local file paths are never sent as URLs.** The registration form holds
  paths on the phone until the account exists, because uploading needs a
  signed-in caller. `_isLocalFile()` is what keeps a phone's own filename from
  being stored as if it were a server path.

### Registration is two calls, and that is deliberate

`completeRegistration()` posts the account, then uploads each document with the
token it just received, then PUTs the results. A document that fails to upload
**must not fail the registration** — the account already exists on the server,
and throwing would leave somebody with an account they cannot see and a screen
that says it failed. Failures are collected in
`lastRegistrationUploadFailures` so the screen can name what to add again.

As of API 1.1.0 the registration endpoint stores the document dates itself, so
the follow-up PUT is now redundant rather than load-bearing. It can be removed
once the oldest supported build has caught up.

## The design system, and the one-way sync

Both apps share these **file for file**:

```
theme/sathiyaa_theme.dart     widgets/sathiyaa_ui.dart
widgets/common.dart           widgets/motion.dart
widgets/osm_map.dart          i18n/l10n.dart
service_area.dart             city_defaults.dart
```

`scripts/sync-design.ps1` copies them **customer → provider** on every build,
comparing hashes so unchanged files keep their timestamps.

**So: edit a shared file in `customer_app`.** Edit it in `provider_app` and the
next build silently reverts it. Anything that belongs only to the provider app
needs its own file — `provider_app/lib/utils/approval.dart` exists for exactly
this reason and says so at the top.

`theme/palette.dart` and the string tables are deliberately **excluded** from
that sync: the two apps differ there on purpose.

## Translations

Three languages, including the apps' own screens, keyed by the English
sentence:

```dart
t('Awaiting approval')
t('Version {v}', {'v': DeviceInfo.appVersion})
```

- Reword the English and the Hindi and Gujarati silently orphan. A test walks
  `lib/` and fails on any key no longer present in the source.
- Interpolation is by named placeholder, never concatenation, because word
  order differs between the three.
- `strings_hi.dart` and `strings_gu.dart` are the tables. Add to both in the
  same edit as the English.

## State

There is no state-management package. Screens hold their own `State`, call
`Backend.instance`, and `setState`. `Backend.instance` holds the signed-in
profile and the current bookings synchronously, because nearly every screen
reads them while building; `refresh()` is what actually goes and fetches.

This is a deliberate choice for an app this size, and it is the thing most
likely to need revisiting if the apps grow much further.

## Device identity

`services/device_info.dart` reads the handset's make, model and OS, and the
app's own version, once at startup and caches them. They go out as `X-Device-*`
and `X-App-Version` headers on every request, and the API records them against
the account — which is what the console's Devices page and the provider's
one-handset binding are built on.

What is collected is what the handset tells any installed app about itself.
Nothing that follows a person between apps: no advertising id, no IMEI.

Every field is optional. A platform that will not answer, or a plugin that
throws on a device nobody anticipated, leaves the header out rather than
stopping the app from starting.

## Maps

`flutter_map` with OpenStreetMap tiles — no API key, no billing. Routing and
geocoding are done by the server, not here, so the fair-use limit on those
public endpoints is enforced in one place.

## What to be careful of

- **`flutter analyze` is clean on both apps.** Keep it that way; it is the only
  automated check that covers the UI.
- **The provider app's two shapes** mean a change to a shared screen has to be
  checked in both — a freelancer and an organisation often reach the same
  widget with very different data (an organisation has no gender and no date of
  birth, and a company's `dob` really is null).
- **Approval status strings** come from the API as `pending` / `approved` /
  `hold` / `rejected`. The mock backend still says `active`. Both spellings are
  accepted in `utils/approval.dart`, in one place, because they were once
  compared in three and two of them were wrong.
