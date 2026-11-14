import fs from 'node:fs/promises';
import process from 'node:process';

import { cert, deleteApp, initializeApp } from 'firebase-admin/app';
import { getDatabase } from 'firebase-admin/database';

const [serviceAccountPath, workerUid, supervisorUid, mode] = process.argv.slice(2);
const uidPattern = /^[A-Za-z0-9_-]{20,128}$/;

if (!serviceAccountPath || !workerUid || !supervisorUid) {
  throw new Error(
    'Usage: node assign_staging_worker.js <service-account.json> '
      + '<worker-uid> <supervisor-uid> [--apply]',
  );
}
if (!uidPattern.test(workerUid) || !uidPattern.test(supervisorUid)) {
  throw new Error('Worker and supervisor UIDs must be valid Firebase UIDs.');
}
if (workerUid === supervisorUid) {
  throw new Error('Worker and supervisor UIDs must be different accounts.');
}
if (mode !== undefined && mode !== '--apply') {
  throw new Error('The only supported optional mode is --apply.');
}

const serviceAccount = JSON.parse(await fs.readFile(serviceAccountPath, 'utf8'));
if (serviceAccount.type !== 'service_account'
    || serviceAccount.project_id !== 'smart-safety-331d6') {
  throw new Error('The service account does not belong to smart-safety-331d6.');
}

const app = initializeApp({
  credential: cert(serviceAccount),
  databaseURL: 'https://smart-safety-331d6-default-rtdb.firebaseio.com',
}, 'staging-worker-assignment');

try {
  const database = getDatabase(app);
  const rootSnapshot = await database.ref().get();

  const root = rootSnapshot.val() ?? {};
  const worker = root.users?.[workerUid];
  const supervisor = root.users?.[supervisorUid];
  const helmet = root.helmets?.helmet001?.meta;
  const site = root.sites?.['site-main'];

  if (!worker || typeof worker !== 'object' || Array.isArray(worker)) {
    throw new Error('The worker has no trusted RTDB profile. Sign up in the app first.');
  }
  if (worker.uid !== workerUid || worker.role !== 'worker' || worker.active !== true) {
    throw new Error('The target profile is not an active trusted worker profile.');
  }
  if (!supervisor || supervisor.uid !== supervisorUid
      || supervisor.role !== 'supervisor' || supervisor.active !== true) {
    throw new Error('The supplied supervisor profile is not active and trusted.');
  }
  if (supervisor.siteIds?.['site-main'] !== true
      || supervisor.authorizedHelmetIds?.helmet001 !== true) {
    throw new Error('The supervisor is not authorized for site-main and helmet001.');
  }
  if (!site || site.active !== true) {
    throw new Error('site-main is missing or inactive.');
  }
  if (!helmet || helmet.helmetId !== 'helmet001'
      || helmet.siteId !== 'site-main' || helmet.active !== true
      || helmet.provisioningStatus !== 'provisioned') {
    throw new Error('helmet001 is not an active provisioned helmet at site-main.');
  }
  if (helmet.assignedWorkerId && helmet.assignedWorkerId !== workerUid) {
    throw new Error(`helmet001 is already assigned to ${helmet.assignedWorkerId}.`);
  }

  const summary = {
    result: mode === '--apply' ? 'PASS' : 'DRY_RUN_PASS',
    workerUid,
    workerEmail: worker.email,
    supervisorUid,
    siteId: 'site-main',
    helmetId: 'helmet001',
    alreadyAssigned: helmet.assignedWorkerId === workerUid,
  };

  if (mode === '--apply' && !summary.alreadyAssigned) {
    const now = Date.now();
    await database.ref().update({
      [`users/${workerUid}/siteIds/site-main`]: true,
      [`users/${workerUid}/authorizedHelmetIds/helmet001`]: true,
      [`users/${workerUid}/authorizedSupervisorIds/${supervisorUid}`]: true,
      [`users/${workerUid}/updatedAt`]: now,
      'helmets/helmet001/meta/assignedWorkerId': workerUid,
      'helmets/helmet001/meta/updatedAt': now,
    });
  }

  console.log(JSON.stringify(summary, null, 2));
} finally {
  await deleteApp(app);
}
