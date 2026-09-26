# The test suite

Eighteen scripts that talk to a real API over HTTP, plus one that only runs
against a deployment-shaped server. Nothing here mocks anything: every script
registers real accounts, takes real bookings and reads them back, which is why
they catch things a unit test would not.

## Running them

```bash
powershell -ExecutionPolicy Bypass -File "C:\Only Forward\Sathiyaa\_tests\run-all.ps1"
```

That is the whole thing. It builds a database called `sathiyaa_test` from the
migrations, seeds it, starts a second API on port 4010 pointed at it, runs all
eighteen scripts, and drops the database afterwards. Your development database
is never touched and nothing is left behind.

| | |
|---|---|
| `run-all.ps1` | everything, on a throwaway database |
| `run-all.ps1 -Only happy-path` | one script, still on a throwaway database |
| `run-all.ps1 -Keep` | leave the database up to look at afterwards |
| `run-all.ps1 -Public` | the AWS configuration, checked before you deploy |
| `run-all.ps1 -Flutter` | the 50 Flutter tests, on a throwaway database |
| `run-all.ps1 -Api https://... -Key ... -AdminPassword ...` | against a deployment |

Logs land in `%TEMP%\sathiyaa-test-run\logs`, one per script, and the runner
prints the path whenever something fails.

### Why a database of its own

The scripts create real accounts, and most of them take a booking. The delete
endpoints refuse an account that has booking history — deliberately, because a
booking is a record somebody may need — so the sweeper could only ever remove
the accounts that never booked. A few hundred test rows had accumulated in the
development database, and the only way back to a clean state was a reseed that
wipes everything, including whatever you created by hand on your phone that
morning.

### The Flutter tests do it too

`api_backend_test.dart` in each app has a group that talks to a real server and
registers real customers on it — the same problem, in the other language. Two
runs of `flutter test` had quietly put six customers and six bookings into the
development database before anyone noticed, because nobody thinks of a widget
test as something that writes to a database.

`run-all.ps1 -Flutter` runs both suites against the throwaway server instead. It
has to pass the address as `--dart-define`, not an environment variable: Dart's
`String.fromEnvironment` is read at compile time, so an environment variable set
in the shell is simply not there when the test runs.

### Why the runner reads the output as well as the exit code

Five of these scripts used to print `FAIL` and exit 0. Anything automated would
have called them green. The runner now checks both and says so loudly when a
script disagrees with itself, because a script that prints a failure and exits 0
has been lying to whoever ran it.

## Running one on its own

Every script still works standalone against whatever is on port 4000:

```bash
C:\sathiyaa-dev\node\node.exe "C:\Only Forward\Sathiyaa\_tests\happy-path.mjs"
```

They all read the same three environment variables, so any of them can be aimed
somewhere else without editing:

- `SATHIYAA_API` (or `API_BASE`) — the API base, default `http://localhost:4000/api/v1`
- `ADMIN_PASSWORD` — default `Admin@123`
- `API_ACCESS_KEY` — sent as `X-Sathiyaa-Key` when set

The last one is applied by `lib/preamble.mjs`, which the runner loads with
`node --import`. It wraps `fetch` and adds the header, so pointing the suite at
a deployment behind a shared key does not mean editing eighteen files. With no
key set it does nothing at all.

## What each one covers

| script | what it proves |
|---|---|
| `happy-path` | the documented flow end to end: register, book, match, accept, pay, rate |
| `full-journey` | the same ground in more detail, from four different devices |
| `practical` | the things a real day is made of — reschedule, transfer, cancel, refund |
| `audit-everything` | every route in the API, exercised once |
| `three-devices` | one account, three handsets, and the device binding that stops sharing |
| `booking-for-dependent` | booking for somebody other than yourself |
| `messages` | the thread on a booking, read from both ends |
| `sos` | the emergency alert: recorded first, then sent |
| `uploads-and-blocks` | file upload limits and calendar blocks |
| `partner-login` | all four ways a business partner can identify themselves |
| `contact-modes` | the preferred-contact field, including what must be refused |
| `admin-contract` | the console's endpoints answer with what the console expects |
| `contract-drift` | the console's TypeScript types still match what the server sends |
| `admin-console-check` | every page in the console answers 200 |
| `admin-actions` | the writes an administrator makes in a normal day |
| `shapes` | dumps the real JSON shape of everything, so Dart parsers match reality |
| `osm` | the maps provider really reaches OpenStreetMap |
| `cleanup-test-rows` | the sweeper itself |
| `public-config` | **only under `-Public`** — the deployed configuration |

## Two things that will bite you

**Seeded carers work Monday to Saturday, 08:00–20:00.** A script that books on a
Sunday matches nobody and fails for a reason that has nothing to do with what it
is testing. Every script skips weekends; a new one must too.

**`toISOString()` is not the local date.** It shifts local midnight back to the
previous UTC day, which is its own way of landing on a Sunday. Build the date
from `getFullYear()` / `getMonth()` / `getDate()`.
