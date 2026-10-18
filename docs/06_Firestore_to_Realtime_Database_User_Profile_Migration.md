# User-profile migration: Firestore to Realtime Database

## Scope and security invariant

The current Flutter adapter reads `users/{uid}` from Cloud Firestore. The target architecture stores authorization projections in Firebase Realtime Database (RTDB). Migration must not copy a client-selected role into a trusted role. Firebase Authentication remains the identity provider; custom claims and administrator-controlled assignment records remain the authorization authorities.

Supervisor and administrator claims must be issued only by a privileged Cloud Function or administrator service using the Firebase Admin SDK. Worker profiles may be created by the controlled signup path, but they start with no site or helmet assignments. Client applications cannot write `role`, `active`, `siteIds`, `authorizedHelmetIds`, or `authorizedSupervisorIds`.

## Target record

`/users/{uid}` in RTDB contains:

```json
{
  "schemaVersion": 1,
  "uid": "firebase-auth-uid",
  "name": "Display name",
  "email": "worker@example.com",
  "organization": "Optional display value",
  "role": "worker",
  "active": true,
  "siteIds": { "site-a": true },
  "authorizedHelmetIds": { "helmet-001": true },
  "authorizedSupervisorIds": { "supervisor-uid": true },
  "pushAlertsEnabled": true,
  "criticalAlertsOnly": false,
  "vibrationEnabled": true,
  "updatedAt": 1767225600000
}
```

Lists from the legacy Firestore document are converted to keyed boolean maps so RTDB Rules can authorize a single path without downloading a collection. `authorizedSupervisorIds` is a server-maintained reverse assignment used when a supervisor reads a worker profile.

## Required migration procedure

1. Export and back up the Firestore `users` collection. Record document counts and a checksum of each source document.
2. Join every source UID to Firebase Authentication. Quarantine orphaned documents, duplicate emails, invalid roles, and records missing `active`.
3. Treat every legacy supervisor or administrator role as untrusted until an administrator verifies the invitation or assignment. Issue the matching custom claim only through the privileged backend. Never infer a privileged claim from the Firestore role string.
4. Rebuild `siteIds`, `authorizedHelmetIds`, and `authorizedSupervisorIds` from the authoritative site, helmet, and worker-assignment records. Do not copy assignments supplied by a client.
5. Write transformed records with an Admin SDK migration job. The job must be idempotent, use a migration version, preserve an audit log, and reject unknown fields.
6. Compare source and target counts; verify UID, active state, role/claim consistency, and every forward and reverse assignment. Test disabled and unverified accounts explicitly.
7. Deploy and pass the Firebase Emulator Security Rules suite before enabling target reads.
8. Release an RTDB `UserRepository` behind a remotely controlled rollout flag. During observation, compare Firestore and RTDB reads server-side; do not merge authorization values on the client.
9. Stop Firestore profile writes, run a final delta migration, and switch all clients to RTDB. Keep Firestore read-only for the rollback window.
10. After the retention and audit window, delete the legacy profiles using the approved data-retention process and update the privacy inventory.

## Rollback

Rollback switches the repository flag back to the read-only Firestore adapter. It does not copy RTDB claims or assignments back from a client session. Any administrator changes made during the rollout must be replayed from the server audit log before Firestore becomes authoritative again.

## Not implemented in Phase 2

Phase 3 adds the RTDB profile adapter and makes it the production composition root. The legacy Firestore adapter remains available only for controlled migration compatibility. The privileged invitation/claim service, migration job, dual-read verification, production telemetry ingestion, and administrator console remain future backend work. Production accounts must not be enabled until their canonical `/users/{uid}` records and assignment projections have been migrated and verified.
