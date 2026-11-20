# Admin Console (Module M15) — what was added, how to run it

Built 2026-11-20 on top of the live repo HEAD `907e909`. **Not committed or pushed anywhere** — delivered as a project ZIP at Huzaifa's request. Everything below was verified in Muse's VM: Flutter analyze clean, **Flutter 189/189 tests**, **Cloud Functions 100/100 tests** (baselines before this module: 177 and 78 — nothing pre-existing broke).

## Run it right now (demo mode — no Firebase needed)

The project runs exactly like before, with one extra demo account:

1. Open the project in Android Studio (or VS Code).
2. Add the demo flag to the run configuration: **Run → Edit Configurations → Additional run args:** `--dart-define=USE_DEMO_DATA=true` (command line: `flutter run --dart-define=USE_DEMO_DATA=true`).
3. The app opens on the **"Choose your workspace"** screen. Pick the **Administrator** card (third card — scroll the list if needed) and tap **Continue as Administrator**.
4. On the sign-in screen, log in with **`admin@example.test`** and **any password** (demo accounts accept any non-empty password, same as `supervisor@example.test` / `worker@example.test`). The Admin Console opens directly and is fully usable on demo data for the session.

**Admin accounts can never be created from sign-up.** The sign-up flow only ever creates worker accounts; the Administrator (and Supervisor) login screens say "accounts are invite-only" and offer no registration. A new administrator is created either by an existing administrator (Users tab → New user) or by the one-time bootstrap script below. Signing in through the wrong portal (e.g. the admin account via Supervisor) is rejected with a role-mismatch message.
4. The Admin Console opens directly — Overview, Users, Helmets, Sites, Thresholds, Audit — fully working against the demo dataset: create users, register a helmet (you'll get a demo device secret), assign it, change thresholds, and watch every action land in the Audit tab. Changes last for the session only.

Why there is no "Administrator" button on the *Choose your workspace* screen: that screen only appears for accounts whose role has not been assigned yet, and it only offers Supervisor/Worker because **an administrator is never self-selected** — the role is assigned to the account (demo account above, bootstrap script below, or by another admin in the console). An account whose assigned role is `administrator` skips that screen entirely and lands in the console. That is deliberate: a self-service "make me admin" option would defeat the role system.

For the live backend path (real accounts, real data), see "First administrator" and "Deploy" below — those need the functions deployed, which needs Blaze.

## Live database connection (real-time data) — works on the free Spark plan

Added 2026-11-20. The console's reads were already `onValue` streams, but in live mode every list screen failed with "Something went wrong": RTDB rules do not cascade upward, so reading the whole `/users`, `/sites`, `/helmets` collection (or unfiltered `/alerts`) was denied even for an administrator, and the stream guard did not map the error. Fixed:

- **Rules (`database.rules.json`):** administrator-only `.read` on `/users`, `/sites`, `/helmets`; administrators may also run a fleet-wide alert query (`orderByChild('serverReceivedAt').limitToLast(≤500)`). Nothing else changed; client writes are still denied. Covered by a new emulator test.
- **Repository (`lib/data/admin_repository.dart`):** stream errors are now mapped properly (`_guardAdminStream`); alert counts use the bounded query and fall back to "—" instead of failing the overview; new `watchLiveFleet()`, `watchRecentAlerts()`, `watchBackendConnection()`.
- **New Live tab (`lib/presentation/admin/admin_live_screen.dart`):** every helmet's latest temperature / humidity / CO / fall / battery with Safe-Warning-Critical-Stale-Offline state, ages ticking every second, the 20 newest alerts, and a database-connection indicator.

To see live data:

1. `firebase deploy --only database` (rules only — no Blaze needed).
2. Create the first administrator once: `cd functions && npm install && node scripts/bootstrap_admin.mjs <serviceAccount.json> <email> "<name>"`, then open the printed link and set the password (Admin SDK script — no Blaze needed).
3. Run the app **without** `USE_DEMO_DATA`, choose Administrator, sign in with that email → Overview / Live / Users / Helmets / Sites / Audit now stream from the live database.

Write actions (create user, register helmet, …) still call the `admin*` Cloud Functions and need the functions deployed (Blaze).

## What the module does

An `administrator` role already existed in the database rules, the alert logic and the app — but admins landed on a placeholder screen ("The mobile administrator portal is not part of this phase") and provisioning was done by hand-run scripts with a service account. This module replaces both:

- **App:** signing in as an administrator now opens a real Admin Console (Overview, Users, Helmets, Sites, Thresholds, Audit) in the Midnight Signal design system, replacing the placeholder branch in `lib/main.dart`. Non-admin flows are untouched.
- **Backend:** 14 administrator-only callable functions perform every privileged action server-side and write an **audit log** entry for each one.
- **Provisioning:** registering a helmet in the console generates its HMAC device secret and stores it in a backend-only database node; telemetry ingestion now checks that node for helmets that are not in the `HELMET_DEVICE_SECRETS` environment registry. Helmets already in the env registry behave exactly as before (env wins if a helmet is in both).

## Backend — new callables (`functions/index.js`, logic in `functions/src/admin_service.js`)

All require an active `administrator` (enforced by the existing `requireActiveUser`):

| Callable | What it does |
|---|---|
| `adminCreateUser` | Creates Auth user + role claim + `/users` record; returns a one-time `passwordSetupLink` (the new user sets their own password — the admin never knows it) |
| `adminSetUserRole` | Changes role (claim + record). Refuses: changing your own role, demoting the last active administrator |
| `adminSetUserActive` | Activates/deactivates (also disables the Auth account). Same self/last-admin guards |
| `adminUpdateUserProfile` | Name / organization |
| `adminUpdateUserAssignments` | Sites, authorized helmets, authorized supervisors (validates referenced records exist) |
| `adminDeleteUser` | Deletes Auth user + record. Same guards |
| `adminRegisterHelmet` | Creates helmet meta + generates the device secret; secret returned **exactly once** |
| `adminAssignHelmet` | Assigns helmet → worker, keeping the worker's `authorizedHelmetIds` in sync both ways |
| `adminSetHelmetSite` | Moves a helmet to a site |
| `adminRetireHelmet` | Marks helmet revoked, unassigns it, deletes its device secret (it can no longer ingest) |
| `adminRotateHelmetSecret` | New secret, keyVersion bumps (v1 → v2 …); new secret returned once |
| `adminUpsertSite` | Creates/updates a site |
| `adminSetSiteSupervisors` | Sets a site's supervisors and syncs their `siteIds` |
| `adminSetHelmetThresholds` | Writes `/config/helmets/{id}` with the same ordering validation the rules enforce |

**Audit:** every successful operation appends `/adminAudit/{key}` = actor, action, target, human summary, before/after, timestamp. Device secret values are **never** written to the audit log (only the keyVersion). `fcmTokenRefs` are stripped from user before/after snapshots.

**Rules (`database.rules.json`) — additions only, no existing rule changed:**
- `/adminAudit`: readable only by an active administrator token; client writes denied (Admin SDK only).
- `/deviceSecrets`: no client read or write at all.

## App — new files

- `lib/data/admin_repository.dart` — reads (users, helmet meta, sites, thresholds, audit, overview counts) via RTDB under the admin's token; writes via the callables; password reset for existing users via `FirebaseAuth.sendPasswordResetEmail`.
- `lib/data/mock_admin_repository.dart` — the demo-mode counterpart: a fully functional in-memory admin backend over the demo dataset, with the same guards as the server (self-protection, last-admin, duplicate checks) and its own in-memory audit log. Demo administrator: `admin@example.test` (in `MockDataSet`, any password).
- `lib/presentation/admin/` — console shell + Overview (account/helmet/alert counts), Users (search + role filter; create form shows the password-setup link once; edit form with role/active/assignments, self-protection: you can't change your own role/active/delete from the UI either), Helmets (fleet list; register → one-time secret sheet with copy button; assign worker/site; rotate; retire), Sites (create/edit + supervisor assignment), Thresholds (all 12 fields with warning < critical validation before saving), Audit (filterable log).

## First administrator (one-time bootstrap)

The console needs one administrator to exist before anyone can use it. Run once, with a service-account JSON for the project (never commit that file):

```bash
cd functions
node scripts/bootstrap_admin.mjs <serviceAccount.json> <admin email> "<Admin name>"
```

It prints a password-setup link — open it, set the password, then sign in to the app with that email. From then on, everything is done in the console.

## Deploy (when billing allows)

Deploying Cloud Functions requires the Blaze plan, which is **still blocked** (OR_BACR2_31, 19 Nov) — so this code is complete and tested, but not yet deployed:

```bash
firebase deploy --only database   # rules: adminAudit + deviceSecrets nodes
firebase deploy --only functions  # admin callables + ingestion secret fallback
```

Then run the bootstrap script once, and build/run the app as usual.

## Files changed vs the live repo

- New: `functions/src/admin_service.js`, `functions/test/admin_service.test.js`, `functions/scripts/bootstrap_admin.mjs`, `lib/data/admin_repository.dart`, `lib/data/mock_admin_repository.dart`, `lib/presentation/admin/` (9 files), `test/admin_console_test.dart`, `test/mock_admin_repository_test.dart`, `test/role_selection_admin_test.dart`, this README.
- Edited: `functions/index.js`, `functions/src/telemetry_ingestion.js` (secret-registry fallback only), `database.rules.json` (two added nodes), `lib/main.dart` (administrator branch only), `lib/application/app_dependencies.dart` (added `admin` repository), `lib/data/mock_repositories.dart` (added the `admin@example.test` demo administrator), `lib/role_selection_screen.dart` (added the Administrator card to workspace selection; the continue button now uses the selected role's label), `lib/login_screen.dart` (the invite-only note now names the selected role instead of always saying Supervisor).
- Untouched: firmware, inference service, `aws/`, all non-admin app screens, telemetry contract, assessment pipeline, alert logic.
