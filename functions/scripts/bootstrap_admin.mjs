// One-time bootstrap: create the FIRST administrator account.
//
// After this runs once, all further user/helmet/site management happens in
// the app's Admin Console — this script is never needed again.
//
// Usage:
//   node scripts/bootstrap_admin.mjs <serviceAccount.json> <email> <display name>
//
// It creates (or reuses) the Auth user, sets the `role: 'administrator'`
// custom claim, writes the /users/{uid} record in the same shape the
// adminCreateUser callable writes, and prints a password-setup link the
// new administrator uses to set their password. The service-account file
// must never be committed.

import { readFile } from 'node:fs/promises';
import { initializeApp, cert } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getDatabase } from 'firebase-admin/database';

const [serviceAccountPath, email, ...nameParts] = process.argv.slice(2);
const name = nameParts.join(' ').trim();

if (!serviceAccountPath || !email || !name) {
  console.error(
    'Usage: node scripts/bootstrap_admin.mjs <serviceAccount.json> <email> <display name>',
  );
  process.exit(1);
}

const serviceAccount = JSON.parse(await readFile(serviceAccountPath, 'utf8'));
initializeApp({
  credential: cert(serviceAccount),
  databaseURL: `https://${serviceAccount.project_id}-default-rtdb.firebaseio.com`,
});

const auth = getAuth();
const database = getDatabase();

let user;
try {
  user = await auth.getUserByEmail(email);
  console.log(`Reusing existing Auth user ${user.uid}`);
} catch {
  user = await auth.createUser({ email, displayName: name });
  console.log(`Created Auth user ${user.uid}`);
}

await auth.setCustomUserClaims(user.uid, { role: 'administrator' });

const now = Date.now();
await database.ref(`users/${user.uid}`).update({
  schemaVersion: '1.0',
  uid: user.uid,
  name,
  email,
  role: 'administrator',
  active: true,
  siteIds: {},
  authorizedHelmetIds: {},
  authorizedSupervisorIds: {},
  updatedAt: now,
});

const setupLink = await auth.generatePasswordResetLink(email);
console.log('\nAdministrator ready.');
console.log(`UID: ${user.uid}`);
console.log(`Password setup link (share privately, expires): ${setupLink}`);
process.exit(0);
