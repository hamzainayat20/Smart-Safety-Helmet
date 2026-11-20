import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import test from 'node:test';

import {
  AdminValidationError,
  createAdminService,
} from '../src/admin_service.js';
import { DEVICE_AUTH_HEADERS, signDeviceRequest } from '../src/device_auth.js';
import { createTelemetryIngestionHandler } from '../src/telemetry_ingestion.js';

const NOW = 1775900000000;
const actor = { uid: 'admin-actor' };

// ---------------------------------------------------------------------------
// In-memory fakes, matching the style of the other function test suites.

function getAt(root, path) {
  return path.split('/').filter(Boolean).reduce((value, part) => value?.[part], root);
}

function setAt(root, path, value) {
  const parts = path.split('/').filter(Boolean);
  let target = root;
  for (const part of parts.slice(0, -1)) target = target[part] ??= {};
  const key = parts.at(-1);
  if (key === undefined) return;
  if (value === null || value === undefined) delete target[key];
  else target[key] = structuredClone(value);
}

class FakeReference {
  constructor(database, path) {
    this.database = database;
    this.path = path;
  }

  get key() {
    return this.path.split('/').filter(Boolean).at(-1) ?? null;
  }

  async get() {
    return { val: () => structuredClone(getAt(this.database.data, this.path)) };
  }

  async set(value) {
    setAt(this.database.data, this.path, value);
  }

  async update(updates) {
    for (const [childPath, value] of Object.entries(updates)) {
      setAt(this.database.data, this.path ? `${this.path}/${childPath}` : childPath, value);
    }
  }

  async remove() {
    setAt(this.database.data, this.path, null);
  }

  push() {
    this.database.pushCounter += 1;
    const key = `-fakePush${this.database.pushCounter}`;
    return new FakeReference(this.database, this.path ? `${this.path}/${key}` : key);
  }

  async transaction(updater) {
    const current = structuredClone(getAt(this.database.data, this.path));
    const next = updater(current);
    if (next === undefined) {
      return { committed: false, snapshot: { val: () => current } };
    }
    setAt(this.database.data, this.path, next);
    return { committed: true, snapshot: { val: () => structuredClone(next) } };
  }
}

class FakeDatabase {
  constructor(data = {}) {
    this.data = data;
    this.pushCounter = 0;
  }

  ref(path = '') {
    return new FakeReference(this, path);
  }
}

class FakeAuth {
  constructor() {
    this.users = new Map();
    this.claims = new Map();
    this.sequence = 0;
  }

  seed(uid, email, displayName = `User ${uid}`) {
    this.users.set(uid, { uid, email, displayName, disabled: false });
  }

  async createUser({ email, displayName }) {
    for (const user of this.users.values()) {
      if (user.email === email) {
        const error = new Error('The email address is already in use by another account.');
        error.code = 'auth/email-already-exists';
        throw error;
      }
    }
    this.sequence += 1;
    const uid = `fake-uid-${this.sequence}`;
    this.users.set(uid, { uid, email, displayName, disabled: false });
    return { uid, email, displayName };
  }

  async generatePasswordResetLink(email) {
    const exists = [...this.users.values()].some((user) => user.email === email);
    if (!exists) {
      const error = new Error('There is no user record corresponding to the email.');
      error.code = 'auth/user-not-found';
      throw error;
    }
    return `https://example.test/reset?email=${encodeURIComponent(email)}`;
  }

  async setCustomUserClaims(uid, claims) {
    if (!this.users.has(uid)) {
      const error = new Error('There is no user record for the provided uid.');
      error.code = 'auth/user-not-found';
      throw error;
    }
    this.claims.set(uid, { ...claims });
  }

  async updateUser(uid, properties) {
    const user = this.users.get(uid);
    if (!user) {
      const error = new Error('There is no user record for the provided uid.');
      error.code = 'auth/user-not-found';
      throw error;
    }
    Object.assign(user, properties);
    return { ...user };
  }

  async deleteUser(uid) {
    if (!this.users.delete(uid)) {
      const error = new Error('There is no user record for the provided uid.');
      error.code = 'auth/user-not-found';
      throw error;
    }
    this.claims.delete(uid);
  }
}

function makeService(data = {}) {
  const database = new FakeDatabase(data);
  const auth = new FakeAuth();
  const service = createAdminService({ database, auth, now: () => NOW });
  return { database, auth, service };
}

function seedUserRecord(database, uid, overrides = {}) {
  database.data.users ??= {};
  database.data.users[uid] = {
    schemaVersion: '1.0',
    uid,
    name: `User ${uid}`,
    email: `${uid}@example.test`,
    role: 'worker',
    active: true,
    siteIds: {},
    authorizedHelmetIds: {},
    authorizedSupervisorIds: {},
    updatedAt: NOW,
    ...overrides,
  };
  return database.data.users[uid];
}

function auditEntries(database) {
  return Object.values(database.data.adminAudit ?? {});
}

async function assertAdminError(promise, code) {
  await assert.rejects(promise, (error) => {
    assert.ok(error instanceof AdminValidationError, `expected AdminValidationError, got ${error}`);
    assert.equal(error.code, code);
    return true;
  });
}

// ---------------------------------------------------------------------------
// User operations

test('createUser writes the record, role claim and audit entry, and returns a setup link', async () => {
  const { database, auth, service } = makeService();
  const result = await service.createUser(actor, {
    email: 'supervisor@example.test',
    name: 'Sana Supervisor',
    role: 'supervisor',
    organizationName: 'SafeSite Co',
    siteIds: ['site-alpha'],
  });

  assert.equal(typeof result.uid, 'string');
  assert.equal(result.user.email, 'supervisor@example.test');
  assert.equal(result.user.name, 'Sana Supervisor');
  assert.equal(result.user.role, 'supervisor');
  assert.equal(result.user.active, true);
  assert.equal(result.user.schemaVersion, '1.0');
  assert.equal(result.user.organizationName, 'SafeSite Co');
  assert.deepEqual(result.user.siteIds, { 'site-alpha': true });
  assert.deepEqual(result.user.authorizedHelmetIds, {});
  assert.deepEqual(result.user.authorizedSupervisorIds, {});
  assert.equal(typeof result.passwordSetupLink, 'string');
  assert.ok(result.passwordSetupLink.includes('supervisor%40example.test'));

  assert.deepEqual(getAt(database.data, `users/${result.uid}`), result.user);
  assert.deepEqual(auth.claims.get(result.uid), { role: 'supervisor' });
  assert.equal(auth.users.get(result.uid).displayName, 'Sana Supervisor');

  const entries = auditEntries(database);
  assert.equal(entries.length, 1);
  assert.equal(entries[0].actorUid, actor.uid);
  assert.equal(entries[0].action, 'createUser');
  assert.equal(entries[0].targetType, 'user');
  assert.equal(entries[0].targetId, result.uid);
  assert.equal(entries[0].before, null);
  assert.equal(entries[0].after.email, 'supervisor@example.test');
  assert.equal(entries[0].at, NOW);
});

test('createUser rejects invalid input and duplicate emails', async () => {
  const { service } = makeService();
  await assertAdminError(
    service.createUser(actor, { email: 'not-an-email', name: 'X', role: 'worker' }),
    'invalid-argument',
  );
  await assertAdminError(
    service.createUser(actor, { email: 'a@example.test', name: '  ', role: 'worker' }),
    'invalid-argument',
  );
  await assertAdminError(
    service.createUser(actor, { email: 'a@example.test', name: 'X', role: 'owner' }),
    'invalid-argument',
  );
  await service.createUser(actor, { email: 'dup@example.test', name: 'First', role: 'worker' });
  await assertAdminError(
    service.createUser(actor, { email: 'dup@example.test', name: 'Second', role: 'worker' }),
    'already-exists',
  );
});

test('setUserRole updates claim and record and refuses the last active administrator', async () => {
  const { database, auth, service } = makeService();
  seedUserRecord(database, 'solo-admin', { role: 'administrator' });
  auth.seed('solo-admin', 'solo-admin@example.test');

  // solo-admin is the only active administrator: demotion is refused.
  await assertAdminError(
    service.setUserRole(actor, { uid: 'solo-admin', role: 'supervisor' }),
    'failed-precondition',
  );

  // With a second active administrator present the demotion succeeds.
  seedUserRecord(database, 'second-admin', { role: 'administrator' });
  const { user } = await service.setUserRole(actor, { uid: 'solo-admin', role: 'supervisor' });
  assert.equal(user.role, 'supervisor');
  assert.deepEqual(auth.claims.get('solo-admin'), { role: 'supervisor' });
  assert.equal(getAt(database.data, 'users/solo-admin/role'), 'supervisor');
});

test('setUserRole and setUserActive refuse to target the actor themselves', async () => {
  const { database, service } = makeService();
  seedUserRecord(database, actor.uid, { role: 'administrator' });
  seedUserRecord(database, 'other-admin', { role: 'administrator' });
  await assertAdminError(
    service.setUserRole(actor, { uid: actor.uid, role: 'worker' }),
    'permission-denied',
  );
  await assertAdminError(
    service.setUserActive(actor, { uid: actor.uid, active: false }),
    'permission-denied',
  );
  await assertAdminError(
    service.deleteUser(actor, { uid: actor.uid }),
    'permission-denied',
  );
});

test('setUserActive disables the auth account and refuses the last active administrator', async () => {
  const { database, auth, service } = makeService();
  seedUserRecord(database, 'only-admin', { role: 'administrator' });
  auth.seed('only-admin', 'only-admin@example.test');
  await assertAdminError(
    service.setUserActive(actor, { uid: 'only-admin', active: false }),
    'failed-precondition',
  );

  seedUserRecord(database, 'worker-1');
  auth.seed('worker-1', 'worker-1@example.test');
  const { user } = await service.setUserActive(actor, { uid: 'worker-1', active: false });
  assert.equal(user.active, false);
  assert.equal(auth.users.get('worker-1').disabled, true);
  const reactivated = await service.setUserActive(actor, { uid: 'worker-1', active: true });
  assert.equal(reactivated.user.active, true);
  assert.equal(auth.users.get('worker-1').disabled, false);
});

test('updateUserProfile renames the record and the auth display name', async () => {
  const { database, auth, service } = makeService();
  seedUserRecord(database, 'worker-1');
  auth.seed('worker-1', 'worker-1@example.test', 'Old Name');
  const { user } = await service.updateUserProfile(actor, {
    uid: 'worker-1',
    name: 'New Name',
    organizationName: 'BuildWell',
  });
  assert.equal(user.name, 'New Name');
  assert.equal(user.organizationName, 'BuildWell');
  assert.equal(auth.users.get('worker-1').displayName, 'New Name');
});

test('updateUserAssignments stores maps and validates referenced records', async () => {
  const { database, service } = makeService();
  seedUserRecord(database, 'supervisor-1', { role: 'supervisor' });
  database.data.sites = { 'site-1': { siteId: 'site-1', name: 'Alpha' } };
  database.data.helmets = { helmet001: { meta: { helmetId: 'helmet001' } } };

  const { user } = await service.updateUserAssignments(actor, {
    uid: 'supervisor-1',
    siteIds: ['site-1'],
    authorizedHelmetIds: ['helmet001'],
  });
  assert.deepEqual(user.siteIds, { 'site-1': true });
  assert.deepEqual(user.authorizedHelmetIds, { helmet001: true });

  await assertAdminError(
    service.updateUserAssignments(actor, { uid: 'supervisor-1', siteIds: ['missing-site'] }),
    'not-found',
  );
  await assertAdminError(
    service.updateUserAssignments(actor, {
      uid: 'supervisor-1',
      authorizedHelmetIds: ['missing-helmet'],
    }),
    'not-found',
  );
});

test('deleteUser removes the auth account and the record', async () => {
  const { database, auth, service } = makeService();
  seedUserRecord(database, 'worker-1');
  auth.seed('worker-1', 'worker-1@example.test');
  const result = await service.deleteUser(actor, { uid: 'worker-1' });
  assert.deepEqual(result, { deleted: true });
  assert.equal(auth.users.has('worker-1'), false);
  assert.equal(getAt(database.data, 'users/worker-1'), undefined);
  const entries = auditEntries(database);
  assert.equal(entries.at(-1).action, 'deleteUser');
  assert.equal(entries.at(-1).after, null);
});

// ---------------------------------------------------------------------------
// Helmet operations

test('registerHelmet creates meta and device secret; the audit never contains the secret', async () => {
  const { database, service } = makeService();
  const result = await service.registerHelmet(actor, {
    helmetId: 'helmet100',
    label: 'Helmet 100',
  });

  assert.equal(result.deviceSecret.keyVersion, 'v1');
  assert.equal(Buffer.from(result.deviceSecret.secretBase64, 'base64').length, 32);

  const stored = getAt(database.data, 'deviceSecrets/helmet100');
  assert.equal(stored.keyVersion, 'v1');
  assert.equal(stored.secretBase64, result.deviceSecret.secretBase64);
  assert.equal(stored.createdBy, actor.uid);

  const meta = getAt(database.data, 'helmets/helmet100/meta');
  assert.equal(meta.provisioningStatus, 'provisioned');
  assert.equal(meta.active, true);
  assert.equal(meta.label, 'Helmet 100');
  assert.equal(meta.registeredBy, actor.uid);
  assert.deepEqual(result.helmet, meta);

  const entries = auditEntries(database);
  assert.equal(entries.length, 1);
  assert.equal(entries[0].action, 'registerHelmet');
  assert.equal(entries[0].after.keyVersion, 'v1');
  assert.ok(
    !JSON.stringify(entries[0]).includes(result.deviceSecret.secretBase64),
    'audit entry leaked the device secret',
  );

  await assertAdminError(
    service.registerHelmet(actor, { helmetId: 'helmet100' }),
    'already-exists',
  );
  await assertAdminError(
    service.registerHelmet(actor, { helmetId: 'bad id!' }),
    'invalid-argument',
  );
});

test('assignHelmet keeps worker authorizedHelmetIds in sync in both directions', async () => {
  const { database, service } = makeService();
  await service.registerHelmet(actor, { helmetId: 'helmet100' });
  seedUserRecord(database, 'worker-1');
  seedUserRecord(database, 'worker-2');
  seedUserRecord(database, 'supervisor-1', { role: 'supervisor' });

  const assigned = await service.assignHelmet(actor, {
    helmetId: 'helmet100',
    workerUid: 'worker-1',
  });
  assert.equal(assigned.helmet.assignedWorkerId, 'worker-1');
  assert.equal(
    getAt(database.data, 'users/worker-1/authorizedHelmetIds/helmet100'),
    true,
  );

  const reassigned = await service.assignHelmet(actor, {
    helmetId: 'helmet100',
    workerUid: 'worker-2',
  });
  assert.equal(reassigned.helmet.assignedWorkerId, 'worker-2');
  assert.equal(
    getAt(database.data, 'users/worker-1/authorizedHelmetIds/helmet100'),
    undefined,
  );
  assert.equal(
    getAt(database.data, 'users/worker-2/authorizedHelmetIds/helmet100'),
    true,
  );

  const unassigned = await service.assignHelmet(actor, {
    helmetId: 'helmet100',
    workerUid: null,
  });
  assert.equal(unassigned.helmet.assignedWorkerId, null);
  assert.equal(
    getAt(database.data, 'users/worker-2/authorizedHelmetIds/helmet100'),
    undefined,
  );

  await assertAdminError(
    service.assignHelmet(actor, { helmetId: 'helmet100', workerUid: 'supervisor-1' }),
    'failed-precondition',
  );
  await assertAdminError(
    service.assignHelmet(actor, { helmetId: 'missing', workerUid: 'worker-1' }),
    'not-found',
  );
});

test('setHelmetSite moves a helmet and retireHelmet revokes it and deletes its secret', async () => {
  const { database, service } = makeService();
  database.data.sites = { 'site-1': { siteId: 'site-1', name: 'Alpha' } };
  await service.registerHelmet(actor, { helmetId: 'helmet100' });
  seedUserRecord(database, 'worker-1');
  await service.assignHelmet(actor, { helmetId: 'helmet100', workerUid: 'worker-1' });

  const moved = await service.setHelmetSite(actor, { helmetId: 'helmet100', siteId: 'site-1' });
  assert.equal(moved.helmet.siteId, 'site-1');
  await assertAdminError(
    service.setHelmetSite(actor, { helmetId: 'helmet100', siteId: 'missing-site' }),
    'not-found',
  );

  const retired = await service.retireHelmet(actor, { helmetId: 'helmet100' });
  assert.equal(retired.helmet.provisioningStatus, 'revoked');
  assert.equal(retired.helmet.assignedWorkerId, null);
  assert.equal(getAt(database.data, 'deviceSecrets/helmet100'), undefined);
  assert.equal(
    getAt(database.data, 'users/worker-1/authorizedHelmetIds/helmet100'),
    undefined,
  );
});

test('rotateHelmetSecret increments the key version and returns the new secret once', async () => {
  const { database, service } = makeService();
  const registered = await service.registerHelmet(actor, { helmetId: 'helmet100' });
  const rotated = await service.rotateHelmetSecret(actor, { helmetId: 'helmet100' });
  assert.equal(rotated.deviceSecret.keyVersion, 'v2');
  assert.notEqual(rotated.deviceSecret.secretBase64, registered.deviceSecret.secretBase64);
  assert.equal(
    Buffer.from(rotated.deviceSecret.secretBase64, 'base64').length,
    32,
  );
  assert.equal(getAt(database.data, 'deviceSecrets/helmet100/keyVersion'), 'v2');
  assert.equal(
    getAt(database.data, 'deviceSecrets/helmet100/secretBase64'),
    rotated.deviceSecret.secretBase64,
  );

  const rotateAudit = auditEntries(database).find((entry) => entry.action === 'rotateHelmetSecret');
  assert.deepEqual(rotateAudit.before, { keyVersion: 'v1' });
  assert.deepEqual(rotateAudit.after, { keyVersion: 'v2' });
  assert.ok(!JSON.stringify(rotateAudit).includes(rotated.deviceSecret.secretBase64));

  const again = await service.rotateHelmetSecret(actor, { helmetId: 'helmet100' });
  assert.equal(again.deviceSecret.keyVersion, 'v3');

  await service.retireHelmet(actor, { helmetId: 'helmet100' });
  await assertAdminError(
    service.rotateHelmetSecret(actor, { helmetId: 'helmet100' }),
    'failed-precondition',
  );
});

// ---------------------------------------------------------------------------
// Site operations

test('upsertSite creates a model-shaped record and updates preserve supervisors', async () => {
  const { database, service } = makeService();
  const { site } = await service.upsertSite(actor, { name: 'North Yard' });
  assert.match(site.siteId, /^north-yard-[a-f0-9]{6}$/);
  assert.equal(site.schemaVersion, '1.0');
  assert.equal(site.name, 'North Yard');
  assert.equal(site.active, true);
  assert.deepEqual(site.zones, []);
  assert.deepEqual(site.supervisors, {});
  assert.equal(site.updatedAt, NOW);
  assert.deepEqual(getAt(database.data, `sites/${site.siteId}`), site);

  seedUserRecord(database, 'supervisor-1', { role: 'supervisor' });
  await service.setSiteSupervisors(actor, {
    siteId: site.siteId,
    supervisorUids: ['supervisor-1'],
  });
  const updated = await service.upsertSite(actor, {
    siteId: site.siteId,
    name: 'North Yard Phase 2',
  });
  assert.equal(updated.site.name, 'North Yard Phase 2');
  assert.deepEqual(updated.site.supervisors, { 'supervisor-1': true });
});

test('setSiteSupervisors syncs site.supervisors and each supervisor siteIds', async () => {
  const { database, service } = makeService();
  const { site } = await service.upsertSite(actor, { name: 'Depot' });
  seedUserRecord(database, 'supervisor-1', { role: 'supervisor' });
  seedUserRecord(database, 'supervisor-2', { role: 'administrator' });
  seedUserRecord(database, 'worker-1');

  const result = await service.setSiteSupervisors(actor, {
    siteId: site.siteId,
    supervisorUids: ['supervisor-1', 'supervisor-2'],
  });
  assert.deepEqual(result.site.supervisors, { 'supervisor-1': true, 'supervisor-2': true });
  assert.equal(getAt(database.data, `users/supervisor-1/siteIds/${site.siteId}`), true);
  assert.equal(getAt(database.data, `users/supervisor-2/siteIds/${site.siteId}`), true);

  const cleared = await service.setSiteSupervisors(actor, {
    siteId: site.siteId,
    supervisorUids: [],
  });
  assert.deepEqual(cleared.site.supervisors, {});
  assert.equal(getAt(database.data, `sites/${site.siteId}/supervisors`), undefined);
  assert.equal(getAt(database.data, `users/supervisor-1/siteIds/${site.siteId}`), undefined);

  await assertAdminError(
    service.setSiteSupervisors(actor, { siteId: site.siteId, supervisorUids: ['worker-1'] }),
    'failed-precondition',
  );
  await assertAdminError(
    service.setSiteSupervisors(actor, { siteId: 'missing-site', supervisorUids: [] }),
    'not-found',
  );
});

// ---------------------------------------------------------------------------
// Thresholds

const validThresholds = {
  temperatureWarningC: 35,
  temperatureCriticalC: 40,
  humidityCriticalLowPct: 10,
  humidityWarningLowPct: 20,
  humidityWarningHighPct: 80,
  humidityCriticalHighPct: 90,
  gasWarningPpm: 50,
  gasCriticalPpm: 100,
  fallImpactThresholdG: 2.0,
  fallDuplicateCooldownSeconds: 30,
  normalPollingIntervalSeconds: 5,
  gasWarmUpHours: 1,
};

test('setHelmetThresholds writes the config record with updatedBy and updatedAt', async () => {
  const { database, service } = makeService();
  const { thresholds } = await service.setHelmetThresholds(actor, {
    helmetId: 'helmet100',
    thresholds: validThresholds,
  });
  assert.equal(thresholds.helmetId, 'helmet100');
  assert.equal(thresholds.updatedBy, actor.uid);
  assert.equal(thresholds.updatedAt, NOW);
  assert.equal(thresholds.temperatureWarningC, 35);
  assert.deepEqual(getAt(database.data, 'config/helmets/helmet100'), thresholds);
  const entries = auditEntries(database);
  assert.equal(entries.at(-1).action, 'setHelmetThresholds');
  assert.equal(entries.at(-1).targetType, 'config');
});

test('setHelmetThresholds rejects unsafe ordering and missing fields', async () => {
  const { service } = makeService();
  await assertAdminError(
    service.setHelmetThresholds(actor, {
      helmetId: 'helmet100',
      thresholds: { ...validThresholds, temperatureWarningC: 40 },
    }),
    'invalid-argument',
  );
  await assertAdminError(
    service.setHelmetThresholds(actor, {
      helmetId: 'helmet100',
      thresholds: { ...validThresholds, humidityWarningLowPct: 5 },
    }),
    'invalid-argument',
  );
  await assertAdminError(
    service.setHelmetThresholds(actor, {
      helmetId: 'helmet100',
      thresholds: { ...validThresholds, gasWarningPpm: 100 },
    }),
    'invalid-argument',
  );
  await assertAdminError(
    service.setHelmetThresholds(actor, {
      helmetId: 'helmet100',
      thresholds: { ...validThresholds, fallImpactThresholdG: 0 },
    }),
    'invalid-argument',
  );
  const { gasWarmUpHours, ...missingField } = validThresholds;
  await assertAdminError(
    service.setHelmetThresholds(actor, { helmetId: 'helmet100', thresholds: missingField }),
    'invalid-argument',
  );
});

// ---------------------------------------------------------------------------
// Device-secret registry merge: env registry first, /deviceSecrets fallback.

const envSecret = Buffer.alloc(32, 0x11);
const envRegistry = JSON.stringify({
  helmet001: { keyVersion: 'v1', secretBase64: envSecret.toString('base64') },
});

function telemetryPayload(helmetId, overrides = {}) {
  return {
    schemaVersion: '1.0',
    eventId: `${helmetId}_test_1`,
    helmetId,
    deviceTimestamp: NOW,
    firmwareVersion: '0.2.0-staging',
    temperatureC: 25,
    humidityPct: 50,
    heatIndexC: 25.5,
    accelXG: 0,
    accelYG: 0,
    accelZG: 1,
    gyroXDegreesPerSecond: 0,
    gyroYDegreesPerSecond: 0,
    gyroZDegreesPerSecond: 0,
    gasWarmUp: true,
    fallStatus: 'notEvaluated',
    sensorFaults: [
      'mq7ReadFailed',
      'mq7Uncalibrated',
      'mq7HeaterStateUnknown',
      'gpsUnavailable',
      'batteryUnavailable',
    ],
    ...overrides,
  };
}

function signedIngestionRequest(helmetId, secret, payload, {
  nonce = 'nonce_1234567890abcdef',
  keyVersion = 'v1',
  requestTimestamp = NOW,
} = {}) {
  const rawBody = Buffer.from(JSON.stringify(payload));
  return {
    method: 'POST',
    rawBody,
    headers: {
      'content-type': 'application/json',
      [DEVICE_AUTH_HEADERS.helmetId]: helmetId,
      [DEVICE_AUTH_HEADERS.timestamp]: String(requestTimestamp),
      [DEVICE_AUTH_HEADERS.nonce]: nonce,
      [DEVICE_AUTH_HEADERS.keyVersion]: keyVersion,
      [DEVICE_AUTH_HEADERS.signature]: signDeviceRequest(
        { helmetId, timestamp: requestTimestamp, nonce, rawBody },
        secret,
      ),
    },
    get(name) { return this.headers[name.toLowerCase()]; },
  };
}

function fakeIngestionResponse() {
  return {
    statusCode: null,
    body: null,
    set() { return this; },
    status(code) { this.statusCode = code; return this; },
    json(value) { this.body = value; return this; },
  };
}

async function ingest(database, helmetId, secret, payload, options = {}) {
  const handler = createTelemetryIngestionHandler({
    database,
    secretRegistryValue: () => envRegistry,
    clock: () => NOW,
  });
  const response = fakeIngestionResponse();
  await handler(signedIngestionRequest(helmetId, secret, payload, options), response);
  return response;
}

test('registry merge: a helmet in the env registry still verifies against the env secret', async () => {
  const database = new FakeDatabase({
    helmets: { helmet001: { meta: { active: true, provisioningStatus: 'provisioned' } } },
  });
  const response = await ingest(
    database,
    'helmet001',
    envSecret,
    telemetryPayload('helmet001'),
  );
  assert.equal(response.statusCode, 202);
  assert.equal(getAt(database.data, 'helmets/helmet001/current/eventId'), 'helmet001_test_1');
});

test('registry merge: the env registry wins when a helmet exists in both registries', async () => {
  const databaseSecret = Buffer.alloc(32, 0x22);
  const database = new FakeDatabase({
    helmets: { helmet001: { meta: { active: true, provisioningStatus: 'provisioned' } } },
    deviceSecrets: {
      helmet001: { keyVersion: 'v1', secretBase64: databaseSecret.toString('base64') },
    },
  });
  const envResponse = await ingest(
    database,
    'helmet001',
    envSecret,
    telemetryPayload('helmet001'),
  );
  assert.equal(envResponse.statusCode, 202);

  const databaseResponse = await ingest(
    database,
    'helmet001',
    databaseSecret,
    telemetryPayload('helmet001', { eventId: 'helmet001_test_2' }),
    { nonce: 'nonce_env_precedence_01' },
  );
  assert.equal(databaseResponse.statusCode, 401);
  assert.equal(databaseResponse.body.error.code, 'INVALID_DEVICE_AUTH');
});

test('registry merge: a helmet registered only in /deviceSecrets verifies end to end', async () => {
  const { database, service } = makeService();
  const { deviceSecret } = await service.registerHelmet(actor, { helmetId: 'helmetDb' });
  const secret = Buffer.from(deviceSecret.secretBase64, 'base64');

  const response = await ingest(
    database,
    'helmetDb',
    secret,
    telemetryPayload('helmetDb'),
  );
  assert.equal(response.statusCode, 202);
  assert.equal(getAt(database.data, 'helmets/helmetDb/current/eventId'), 'helmetDb_test_1');
  assert.equal(getAt(database.data, 'readings/helmetDb/helmetDb_test_1/accelZG'), 1);
});

test('registry merge: wrong secret and wrong key version fail for a /deviceSecrets helmet', async () => {
  const { database, service } = makeService();
  const { deviceSecret } = await service.registerHelmet(actor, { helmetId: 'helmetDb' });
  const secret = Buffer.from(deviceSecret.secretBase64, 'base64');

  const wrongSecret = await ingest(
    database,
    'helmetDb',
    Buffer.alloc(32, 0x33),
    telemetryPayload('helmetDb'),
    { nonce: 'nonce_wrong_secret_001' },
  );
  assert.equal(wrongSecret.statusCode, 401);
  assert.equal(wrongSecret.body.error.code, 'INVALID_DEVICE_AUTH');

  const wrongVersion = await ingest(
    database,
    'helmetDb',
    secret,
    telemetryPayload('helmetDb'),
    { nonce: 'nonce_wrong_version_01', keyVersion: 'v9' },
  );
  assert.equal(wrongVersion.statusCode, 401);
  assert.equal(wrongVersion.body.error.code, 'INVALID_DEVICE_AUTH');
});

test('registry merge: a retired helmet has no /deviceSecrets entry and is rejected', async () => {
  const { database, service } = makeService();
  const { deviceSecret } = await service.registerHelmet(actor, { helmetId: 'helmetDb' });
  const secret = Buffer.from(deviceSecret.secretBase64, 'base64');

  const accepted = await ingest(
    database,
    'helmetDb',
    secret,
    telemetryPayload('helmetDb'),
    { nonce: 'nonce_before_retire_01' },
  );
  assert.equal(accepted.statusCode, 202);

  await service.retireHelmet(actor, { helmetId: 'helmetDb' });
  assert.equal(getAt(database.data, 'deviceSecrets/helmetDb'), undefined);

  const rejected = await ingest(
    database,
    'helmetDb',
    secret,
    telemetryPayload('helmetDb', { eventId: 'helmetDb_test_2' }),
    { nonce: 'nonce_after_retire_001' },
  );
  assert.equal(rejected.statusCode, 401);
  assert.equal(rejected.body.error.code, 'INVALID_DEVICE_AUTH');
});

test('registry merge: a rotated /deviceSecrets secret verifies with its new key version', async () => {
  const { database, service } = makeService();
  await service.registerHelmet(actor, { helmetId: 'helmetDb' });
  const rotated = await service.rotateHelmetSecret(actor, { helmetId: 'helmetDb' });
  const secret = Buffer.from(rotated.deviceSecret.secretBase64, 'base64');

  const response = await ingest(
    database,
    'helmetDb',
    secret,
    telemetryPayload('helmetDb'),
    { keyVersion: rotated.deviceSecret.keyVersion },
  );
  assert.equal(response.statusCode, 202);
});
