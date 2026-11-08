import fs from 'node:fs/promises';
import process from 'node:process';

import { cert, deleteApp, initializeApp } from 'firebase-admin/app';
import { getDatabase } from 'firebase-admin/database';

const serviceAccountPath = process.argv[2];
if (!serviceAccountPath) {
  throw new Error('Provide the Firebase service-account JSON path.');
}

const serviceAccount = JSON.parse(await fs.readFile(serviceAccountPath, 'utf8'));
if (serviceAccount.type !== 'service_account' ||
    serviceAccount.project_id !== 'smart-safety-331d6') {
  throw new Error('The service account does not belong to smart-safety-331d6.');
}

const app = initializeApp({
  credential: cert(serviceAccount),
  databaseURL: 'https://smart-safety-331d6-default-rtdb.firebaseio.com',
}, 'aws-staging-provisioner');

try {
  const database = getDatabase(app);
  const reference = database.ref('helmets/helmet001/meta');
  const existing = (await reference.get()).val();

  if (existing !== null && (typeof existing !== 'object' || Array.isArray(existing))) {
    throw new Error('Existing helmet001 metadata is not a valid object.');
  }
  if (existing?.helmetId && existing.helmetId !== 'helmet001') {
    throw new Error('Existing metadata belongs to a different Helmet ID.');
  }
  if (existing?.siteId && existing.siteId !== 'site-main') {
    throw new Error('Existing helmet001 metadata belongs to another site.');
  }

  const now = Date.now();
  const metadata = {
    schemaVersion: existing?.schemaVersion ?? '1.0',
    helmetId: 'helmet001',
    siteId: 'site-main',
    ...(existing?.assignedWorkerId
      ? { assignedWorkerId: existing.assignedWorkerId }
      : {}),
    zone: existing?.zone ?? 'Staging',
    firmwareVersion: existing?.firmwareVersion ?? 'aws-smoke.1',
    active: true,
    provisioningStatus: 'provisioned',
    connectivity: existing?.connectivity ?? 'offline',
    ...(Number.isSafeInteger(existing?.lastSeenAt)
      ? { lastSeenAt: existing.lastSeenAt }
      : {}),
    updatedAt: now,
  };

  await reference.set(metadata);
  console.log(JSON.stringify({
    result: 'PASS',
    path: '/helmets/helmet001/meta',
    helmetId: metadata.helmetId,
    siteId: metadata.siteId,
    active: metadata.active,
    provisioningStatus: metadata.provisioningStatus,
    preservedWorkerAssignment: Boolean(metadata.assignedWorkerId),
  }, null, 2));
} finally {
  await deleteApp(app);
}
