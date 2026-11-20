import { randomBytes } from 'node:crypto';

// Administrative operations for the Admin Console (module M15).
//
// Every operation is invoked from a thin onCall wrapper in index.js that has
// already authorised the actor as an active administrator via
// requireActiveUser(request, ['administrator']). Each successful operation
// writes an audit entry to /adminAudit. Device secret values are only ever
// stored in /deviceSecrets and returned exactly once by registerHelmet /
// rotateHelmetSecret; they are never written to the audit log.

export class AdminValidationError extends Error {
  constructor(message, code = 'invalid-argument') {
    super(message);
    this.name = 'AdminValidationError';
    this.code = code;
  }
}

const ROLES = Object.freeze(['worker', 'supervisor', 'administrator']);
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const HELMET_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;
const SAFE_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;
const KEY_VERSION_PATTERN = /^v(\d+)$/;
const USER_SCHEMA_VERSION = '1.0';
const SITE_SCHEMA_VERSION = '1.0';
const HELMET_META_SCHEMA_VERSION = '1.0';
const CONFIG_SCHEMA_VERSION = '1.0';
const DEFAULT_CONFIG_VERSION = 'admin-1';

// The threshold fields of /config/helmets/{helmetId}, mirroring the RTDB
// rules validation and the app HelmetConfiguration model.
const THRESHOLD_FIELDS = Object.freeze([
  'temperatureWarningC',
  'temperatureCriticalC',
  'humidityCriticalLowPct',
  'humidityWarningLowPct',
  'humidityWarningHighPct',
  'humidityCriticalHighPct',
  'gasWarningPpm',
  'gasCriticalPpm',
  'fallImpactThresholdG',
  'fallDuplicateCooldownSeconds',
  'normalPollingIntervalSeconds',
  'gasWarmUpHours',
]);

function fail(code, message) {
  throw new AdminValidationError(message, code);
}

function isRecord(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function requireInputObject(input) {
  if (!isRecord(input)) fail('invalid-argument', 'A request object is required.');
  return input;
}

function validateEmail(value) {
  if (typeof value !== 'string' || value.length > 254 || !EMAIL_PATTERN.test(value)) {
    fail('invalid-argument', 'A valid email address is required.');
  }
  return value;
}

function validateName(value, field = 'name') {
  if (typeof value !== 'string') fail('invalid-argument', `A ${field} is required.`);
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > 100) {
    fail('invalid-argument', `The ${field} must be between 1 and 100 characters.`);
  }
  return trimmed;
}

function validateOptionalText(value, field) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string' || value.trim().length > 200) {
    fail('invalid-argument', `The ${field} must be a string of at most 200 characters.`);
  }
  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
}

function validateRole(value) {
  if (!ROLES.includes(value)) {
    fail('invalid-argument', `Role must be one of: ${ROLES.join(', ')}.`);
  }
  return value;
}

function validateUid(value, field = 'uid') {
  if (typeof value !== 'string' || !SAFE_ID_PATTERN.test(value)) {
    fail('invalid-argument', `A valid ${field} is required.`);
  }
  return value;
}

function validateHelmetId(value) {
  if (typeof value !== 'string' || !HELMET_ID_PATTERN.test(value)) {
    fail('invalid-argument', 'A valid helmetId is required.');
  }
  return value;
}

function validateIdArray(value, field) {
  if (!Array.isArray(value)) {
    fail('invalid-argument', `${field} must be an array of IDs.`);
  }
  const ids = [];
  for (const entry of value) {
    if (typeof entry !== 'string' || !SAFE_ID_PATTERN.test(entry)) {
      fail('invalid-argument', `${field} contains an invalid ID.`);
    }
    if (!ids.includes(entry)) ids.push(entry);
  }
  return ids;
}

function idsToMap(ids) {
  return Object.fromEntries(ids.map((id) => [id, true]));
}

function mapKeys(map) {
  if (!isRecord(map)) return [];
  return Object.keys(map).filter((key) => map[key] === true).sort();
}

// User records carry no secret material, but fcmTokenRefs keys are hashes of
// live FCM registration tokens; keep them out of the audit trail.
function auditUserRecord(record) {
  if (!isRecord(record)) return null;
  const { fcmTokenRefs, ...rest } = record;
  return rest;
}

function mapAuthError(error) {
  if (error instanceof AdminValidationError) return error;
  switch (error?.code) {
    case 'auth/email-already-exists':
      return new AdminValidationError(
        'An account with this email address already exists.',
        'already-exists',
      );
    case 'auth/user-not-found':
      return new AdminValidationError('The auth account no longer exists.', 'not-found');
    case 'auth/invalid-email':
      return new AdminValidationError('The email address is invalid.', 'invalid-argument');
    case 'auth/invalid-display-name':
      return new AdminValidationError('The display name is invalid.', 'invalid-argument');
    default:
      return error;
  }
}

async function callAuth(operation) {
  try {
    return await operation();
  } catch (error) {
    throw mapAuthError(error);
  }
}

export function createAdminService({ database, auth, now } = {}) {
  if (!database || typeof database.ref !== 'function') {
    throw new TypeError('createAdminService requires a database.');
  }
  if (!auth) throw new TypeError('createAdminService requires an auth service.');

  const nowMs = () => {
    const value = typeof now === 'function' ? now() : now;
    return Number.isSafeInteger(value) ? value : Date.now();
  };

  function requireActor(actor) {
    if (!isRecord(actor) || typeof actor.uid !== 'string' || actor.uid.length === 0) {
      fail('permission-denied', 'An administrator actor is required.');
    }
    return actor;
  }

  async function readValue(path) {
    return (await database.ref(path).get()).val() ?? null;
  }

  async function readUser(uid) {
    return readValue(`users/${uid}`);
  }

  async function readHelmetMeta(helmetId) {
    return readValue(`helmets/${helmetId}/meta`);
  }

  async function readSite(siteId) {
    return readValue(`sites/${siteId}`);
  }

  async function requireUser(uid) {
    const user = await readUser(uid);
    if (!user) fail('not-found', 'User not found.');
    return user;
  }

  async function requireHelmetMeta(helmetId) {
    const meta = await readHelmetMeta(helmetId);
    if (!meta) fail('not-found', 'Helmet not found.');
    return meta;
  }

  async function requireSite(siteId) {
    const site = await readSite(siteId);
    if (!site) fail('not-found', 'Site not found.');
    return site;
  }

  async function countActiveAdministrators() {
    const users = (await readValue('users')) ?? {};
    return Object.values(users)
      .filter((user) => isRecord(user) && user.role === 'administrator' && user.active === true)
      .length;
  }

  async function guardNotLastActiveAdministrator(target) {
    if (target.role === 'administrator' && target.active === true &&
        (await countActiveAdministrators()) <= 1) {
      fail(
        'failed-precondition',
        'This is the last active administrator and cannot lose that status.',
      );
    }
  }

  async function writeAudit(actor, { action, targetType, targetId, summary, before, after }) {
    await database.ref('adminAudit').push().set({
      actorUid: actor.uid,
      action,
      targetType,
      targetId,
      summary,
      before: before ?? null,
      after: after ?? null,
      at: nowMs(),
    });
  }

  async function createUser(actor, input) {
    requireActor(actor);
    const data = requireInputObject(input);
    const email = validateEmail(data.email);
    const name = validateName(data.name);
    const role = validateRole(data.role);
    const organizationName = validateOptionalText(data.organizationName, 'organizationName');
    const siteIds = data.siteIds === undefined ? [] : validateIdArray(data.siteIds, 'siteIds');
    const at = nowMs();

    const created = await callAuth(() => auth.createUser({ email, displayName: name }));
    const uid = created?.uid;
    if (typeof uid !== 'string' || uid.length === 0) {
      throw new Error('Auth did not return a uid for the new user.');
    }
    const record = {
      schemaVersion: USER_SCHEMA_VERSION,
      uid,
      name,
      email,
      role,
      active: true,
      ...(organizationName ? { organizationName } : {}),
      siteIds: idsToMap(siteIds),
      authorizedHelmetIds: {},
      authorizedSupervisorIds: {},
      updatedAt: at,
    };
    let passwordSetupLink;
    try {
      // No password is set by the admin: the new user sets their own through
      // this password-setup (reset) link, shared with them out-of-band.
      passwordSetupLink = await callAuth(() => auth.generatePasswordResetLink(email));
      await callAuth(() => auth.setCustomUserClaims(uid, { role }));
      await database.ref(`users/${uid}`).set(record);
    } catch (error) {
      try {
        await auth.deleteUser(uid);
      } catch {
        // Best-effort rollback; the original error is the one that matters.
      }
      throw error;
    }
    await writeAudit(actor, {
      action: 'createUser',
      targetType: 'user',
      targetId: uid,
      summary: `Created ${role} account for ${email}.`,
      before: null,
      after: auditUserRecord(record),
    });
    return { uid, user: record, passwordSetupLink };
  }

  async function setUserRole(actor, input) {
    requireActor(actor);
    const data = requireInputObject(input);
    const uid = validateUid(data.uid);
    const role = validateRole(data.role);
    if (uid === actor.uid) {
      fail('permission-denied', 'You cannot change your own role.');
    }
    const before = await requireUser(uid);
    if (before.role === 'administrator' && role !== 'administrator') {
      await guardNotLastActiveAdministrator(before);
    }
    await callAuth(() => auth.setCustomUserClaims(uid, { role }));
    const after = { ...before, role, updatedAt: nowMs() };
    await database.ref(`users/${uid}`).set(after);
    await writeAudit(actor, {
      action: 'setUserRole',
      targetType: 'user',
      targetId: uid,
      summary: `Changed role of ${before.email ?? uid} from ${before.role} to ${role}.`,
      before: auditUserRecord(before),
      after: auditUserRecord(after),
    });
    return { user: after };
  }

  async function setUserActive(actor, input) {
    requireActor(actor);
    const data = requireInputObject(input);
    const uid = validateUid(data.uid);
    if (typeof data.active !== 'boolean') {
      fail('invalid-argument', 'active must be a boolean.');
    }
    const active = data.active;
    if (uid === actor.uid && active === false) {
      fail('permission-denied', 'You cannot deactivate your own account.');
    }
    const before = await requireUser(uid);
    if (active === false) await guardNotLastActiveAdministrator(before);
    await callAuth(() => auth.updateUser(uid, { disabled: !active }));
    const after = { ...before, active, updatedAt: nowMs() };
    await database.ref(`users/${uid}`).set(after);
    await writeAudit(actor, {
      action: 'setUserActive',
      targetType: 'user',
      targetId: uid,
      summary: `${active ? 'Activated' : 'Deactivated'} account ${before.email ?? uid}.`,
      before: auditUserRecord(before),
      after: auditUserRecord(after),
    });
    return { user: after };
  }

  async function updateUserProfile(actor, input) {
    requireActor(actor);
    const data = requireInputObject(input);
    const uid = validateUid(data.uid);
    const before = await requireUser(uid);
    const after = { ...before, updatedAt: nowMs() };
    if (data.name !== undefined) {
      after.name = validateName(data.name);
      await callAuth(() => auth.updateUser(uid, { displayName: after.name }));
    }
    if (data.organizationName !== undefined) {
      const organizationName = validateOptionalText(
        data.organizationName,
        'organizationName',
      );
      if (organizationName) after.organizationName = organizationName;
      else delete after.organizationName;
    }
    await database.ref(`users/${uid}`).set(after);
    await writeAudit(actor, {
      action: 'updateUserProfile',
      targetType: 'user',
      targetId: uid,
      summary: `Updated profile of ${before.email ?? uid}.`,
      before: auditUserRecord(before),
      after: auditUserRecord(after),
    });
    return { user: after };
  }

  async function updateUserAssignments(actor, input) {
    requireActor(actor);
    const data = requireInputObject(input);
    const uid = validateUid(data.uid);
    const before = await requireUser(uid);
    const after = { ...before, updatedAt: nowMs() };
    if (data.siteIds !== undefined) {
      const siteIds = validateIdArray(data.siteIds, 'siteIds');
      for (const siteId of siteIds) await requireSite(siteId);
      after.siteIds = idsToMap(siteIds);
    }
    if (data.authorizedHelmetIds !== undefined) {
      const helmetIds = validateIdArray(data.authorizedHelmetIds, 'authorizedHelmetIds');
      for (const helmetId of helmetIds) await requireHelmetMeta(helmetId);
      after.authorizedHelmetIds = idsToMap(helmetIds);
    }
    if (data.authorizedSupervisorIds !== undefined) {
      const supervisorIds = validateIdArray(
        data.authorizedSupervisorIds,
        'authorizedSupervisorIds',
      );
      for (const supervisorId of supervisorIds) await requireUser(supervisorId);
      after.authorizedSupervisorIds = idsToMap(supervisorIds);
    }
    await database.ref(`users/${uid}`).set(after);
    await writeAudit(actor, {
      action: 'updateUserAssignments',
      targetType: 'user',
      targetId: uid,
      summary: `Updated assignments for ${before.email ?? uid}.`,
      before: auditUserRecord(before),
      after: auditUserRecord(after),
    });
    return { user: after };
  }

  async function deleteUser(actor, input) {
    requireActor(actor);
    const data = requireInputObject(input);
    const uid = validateUid(data.uid);
    if (uid === actor.uid) {
      fail('permission-denied', 'You cannot delete your own account.');
    }
    const before = await requireUser(uid);
    await guardNotLastActiveAdministrator(before);
    try {
      await auth.deleteUser(uid);
    } catch (error) {
      // A record whose auth account is already gone is still deleted.
      if (error?.code !== 'auth/user-not-found') throw mapAuthError(error);
    }
    await database.ref(`users/${uid}`).remove();
    await writeAudit(actor, {
      action: 'deleteUser',
      targetType: 'user',
      targetId: uid,
      summary: `Deleted ${before.role} account ${before.email ?? uid}.`,
      before: auditUserRecord(before),
      after: null,
    });
    return { deleted: true };
  }

  async function registerHelmet(actor, input) {
    requireActor(actor);
    const data = requireInputObject(input);
    const helmetId = validateHelmetId(data.helmetId);
    const label = validateOptionalText(data.label, 'label');
    let siteId = null;
    if (data.siteId !== undefined && data.siteId !== null) {
      siteId = validateUid(data.siteId, 'siteId');
      await requireSite(siteId);
    }
    if (await readHelmetMeta(helmetId)) {
      fail('already-exists', 'A helmet with this ID is already registered.');
    }
    const at = nowMs();
    const keyVersion = 'v1';
    // The generated secret is stored only in /deviceSecrets and returned
    // exactly once, in this response, so the admin can provision the helmet.
    const secretBase64 = randomBytes(32).toString('base64');
    await database.ref(`deviceSecrets/${helmetId}`).set({
      keyVersion,
      secretBase64,
      createdAt: at,
      createdBy: actor.uid,
    });
    const meta = {
      schemaVersion: HELMET_META_SCHEMA_VERSION,
      helmetId,
      siteId,
      assignedWorkerId: null,
      label,
      active: true,
      provisioningStatus: 'provisioned',
      registeredAt: at,
      registeredBy: actor.uid,
      updatedAt: at,
    };
    await database.ref(`helmets/${helmetId}/meta`).set(meta);
    await writeAudit(actor, {
      action: 'registerHelmet',
      targetType: 'helmet',
      targetId: helmetId,
      summary: `Registered helmet ${helmetId} with device key ${keyVersion}.`,
      before: null,
      after: { ...meta, keyVersion },
    });
    return { helmet: meta, deviceSecret: { keyVersion, secretBase64 } };
  }

  async function assignHelmet(actor, input) {
    requireActor(actor);
    const data = requireInputObject(input);
    const helmetId = validateHelmetId(data.helmetId);
    const before = await requireHelmetMeta(helmetId);
    let workerUid = null;
    if (data.workerUid !== undefined && data.workerUid !== null) {
      workerUid = validateUid(data.workerUid, 'workerUid');
      const worker = await requireUser(workerUid);
      if (worker.role !== 'worker') {
        fail('failed-precondition', 'Only a user with the worker role can be assigned a helmet.');
      }
    }
    const previousWorkerId = before.assignedWorkerId ?? null;
    const at = nowMs();
    const updates = {
      [`helmets/${helmetId}/meta/assignedWorkerId`]: workerUid,
      [`helmets/${helmetId}/meta/updatedAt`]: at,
    };
    if (previousWorkerId && previousWorkerId !== workerUid) {
      updates[`users/${previousWorkerId}/authorizedHelmetIds/${helmetId}`] = null;
    }
    if (workerUid) {
      updates[`users/${workerUid}/authorizedHelmetIds/${helmetId}`] = true;
    }
    await database.ref().update(updates);
    const after = { ...before, assignedWorkerId: workerUid, updatedAt: at };
    await writeAudit(actor, {
      action: 'assignHelmet',
      targetType: 'helmet',
      targetId: helmetId,
      summary: workerUid
        ? `Assigned helmet ${helmetId} to worker ${workerUid}.`
        : `Unassigned helmet ${helmetId}.`,
      before,
      after,
    });
    return { helmet: after };
  }

  async function setHelmetSite(actor, input) {
    requireActor(actor);
    const data = requireInputObject(input);
    const helmetId = validateHelmetId(data.helmetId);
    const before = await requireHelmetMeta(helmetId);
    let siteId = null;
    if (data.siteId !== undefined && data.siteId !== null) {
      siteId = validateUid(data.siteId, 'siteId');
      await requireSite(siteId);
    }
    const at = nowMs();
    const after = { ...before, siteId, updatedAt: at };
    await database.ref(`helmets/${helmetId}/meta`).set(after);
    await writeAudit(actor, {
      action: 'setHelmetSite',
      targetType: 'helmet',
      targetId: helmetId,
      summary: siteId
        ? `Moved helmet ${helmetId} to site ${siteId}.`
        : `Removed helmet ${helmetId} from its site.`,
      before,
      after,
    });
    return { helmet: after };
  }

  async function retireHelmet(actor, input) {
    requireActor(actor);
    const data = requireInputObject(input);
    const helmetId = validateHelmetId(data.helmetId);
    const before = await requireHelmetMeta(helmetId);
    const previousWorkerId = before.assignedWorkerId ?? null;
    const at = nowMs();
    const after = {
      ...before,
      active: false,
      provisioningStatus: 'revoked',
      assignedWorkerId: null,
      updatedAt: at,
    };
    const updates = {
      [`helmets/${helmetId}/meta`]: after,
      [`deviceSecrets/${helmetId}`]: null,
    };
    if (previousWorkerId) {
      updates[`users/${previousWorkerId}/authorizedHelmetIds/${helmetId}`] = null;
    }
    await database.ref().update(updates);
    await writeAudit(actor, {
      action: 'retireHelmet',
      targetType: 'helmet',
      targetId: helmetId,
      summary: `Retired helmet ${helmetId} and deleted its device secret.`,
      before,
      after,
    });
    return { helmet: after };
  }

  async function rotateHelmetSecret(actor, input) {
    requireActor(actor);
    const data = requireInputObject(input);
    const helmetId = validateHelmetId(data.helmetId);
    const meta = await requireHelmetMeta(helmetId);
    if (meta.provisioningStatus === 'revoked') {
      fail('failed-precondition', 'A revoked helmet cannot receive a new device secret.');
    }
    const existing = await readValue(`deviceSecrets/${helmetId}`);
    const match = typeof existing?.keyVersion === 'string'
      ? KEY_VERSION_PATTERN.exec(existing.keyVersion)
      : null;
    const previousVersion = match ? Number.parseInt(match[1], 10) : (existing ? 1 : 0);
    const keyVersion = `v${previousVersion + 1}`;
    const at = nowMs();
    // Returned exactly once, in this response; never audited or logged.
    const secretBase64 = randomBytes(32).toString('base64');
    await database.ref(`deviceSecrets/${helmetId}`).set({
      keyVersion,
      secretBase64,
      createdAt: at,
      createdBy: actor.uid,
    });
    await writeAudit(actor, {
      action: 'rotateHelmetSecret',
      targetType: 'helmet',
      targetId: helmetId,
      summary: `Rotated device secret for helmet ${helmetId} to key ${keyVersion}.`,
      before: { keyVersion: existing?.keyVersion ?? null },
      after: { keyVersion },
    });
    return { deviceSecret: { keyVersion, secretBase64 } };
  }

  async function upsertSite(actor, input) {
    requireActor(actor);
    const data = requireInputObject(input);
    const name = validateName(data.name);
    const description = data.description === undefined
      ? undefined
      : validateOptionalText(data.description, 'description');
    let siteId;
    let before = null;
    if (data.siteId !== undefined && data.siteId !== null) {
      siteId = validateUid(data.siteId, 'siteId');
      before = await readSite(siteId);
    } else {
      const slug = name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') ||
        'site';
      for (let attempt = 0; attempt < 5 && !siteId; attempt += 1) {
        const candidate = `${slug}-${randomBytes(3).toString('hex')}`;
        if (!(await readSite(candidate))) siteId = candidate;
      }
      if (!siteId) throw new Error('Could not allocate a unique site ID.');
    }
    const at = nowMs();
    const after = {
      ...(before ?? {}),
      schemaVersion: SITE_SCHEMA_VERSION,
      siteId,
      name,
      updatedAt: at,
    };
    if (after.active === undefined) after.active = true;
    if (!Array.isArray(after.zones)) after.zones = [];
    if (!isRecord(after.supervisors)) after.supervisors = {};
    if (description !== undefined) {
      if (description) after.description = description;
      else delete after.description;
    }
    await database.ref(`sites/${siteId}`).set(after);
    await writeAudit(actor, {
      action: 'upsertSite',
      targetType: 'site',
      targetId: siteId,
      summary: before ? `Updated site ${name}.` : `Created site ${name}.`,
      before,
      after,
    });
    return { site: after };
  }

  async function setSiteSupervisors(actor, input) {
    requireActor(actor);
    const data = requireInputObject(input);
    const siteId = validateUid(data.siteId, 'siteId');
    const supervisorUids = validateIdArray(data.supervisorUids, 'supervisorUids');
    const before = await requireSite(siteId);
    for (const uid of supervisorUids) {
      const user = await requireUser(uid);
      if (user.role !== 'supervisor' && user.role !== 'administrator') {
        fail(
          'failed-precondition',
          `User ${uid} must be a supervisor or administrator to supervise a site.`,
        );
      }
    }
    const previousSupervisors = mapKeys(before.supervisors);
    const at = nowMs();
    const supervisors = idsToMap(supervisorUids);
    const updates = {
      [`sites/${siteId}/supervisors`]: supervisorUids.length > 0 ? supervisors : null,
      [`sites/${siteId}/updatedAt`]: at,
    };
    for (const uid of supervisorUids) {
      if (!previousSupervisors.includes(uid)) {
        updates[`users/${uid}/siteIds/${siteId}`] = true;
      }
    }
    for (const uid of previousSupervisors) {
      if (!supervisorUids.includes(uid)) {
        updates[`users/${uid}/siteIds/${siteId}`] = null;
      }
    }
    await database.ref().update(updates);
    const after = { ...before, supervisors, updatedAt: at };
    await writeAudit(actor, {
      action: 'setSiteSupervisors',
      targetType: 'site',
      targetId: siteId,
      summary: `Set ${supervisorUids.length} supervisor(s) for site ${siteId}.`,
      before,
      after,
    });
    return { site: after };
  }

  async function setHelmetThresholds(actor, input) {
    requireActor(actor);
    const data = requireInputObject(input);
    const helmetId = validateHelmetId(data.helmetId);
    if (!isRecord(data.thresholds)) {
      fail('invalid-argument', 'A thresholds object is required.');
    }
    const thresholds = {};
    for (const field of THRESHOLD_FIELDS) {
      const value = data.thresholds[field];
      if (typeof value !== 'number' || !Number.isFinite(value)) {
        fail('invalid-argument', `Threshold ${field} must be a finite number.`);
      }
      thresholds[field] = value;
    }
    // The same ordering rules the RTDB rules enforce on /config/helmets.
    if (!(thresholds.temperatureWarningC < thresholds.temperatureCriticalC)) {
      fail('invalid-argument', 'temperatureWarningC must be below temperatureCriticalC.');
    }
    if (!(thresholds.humidityCriticalLowPct < thresholds.humidityWarningLowPct &&
          thresholds.humidityWarningLowPct < thresholds.humidityWarningHighPct &&
          thresholds.humidityWarningHighPct < thresholds.humidityCriticalHighPct)) {
      fail(
        'invalid-argument',
        'Humidity thresholds must satisfy critical-low < warning-low < warning-high < critical-high.',
      );
    }
    if (!(thresholds.gasWarningPpm < thresholds.gasCriticalPpm)) {
      fail('invalid-argument', 'gasWarningPpm must be below gasCriticalPpm.');
    }
    if (!(thresholds.fallImpactThresholdG > 0)) {
      fail('invalid-argument', 'fallImpactThresholdG must be greater than 0.');
    }
    if (!(thresholds.fallDuplicateCooldownSeconds > 0)) {
      fail('invalid-argument', 'fallDuplicateCooldownSeconds must be greater than 0.');
    }
    if (!(thresholds.normalPollingIntervalSeconds > 0)) {
      fail('invalid-argument', 'normalPollingIntervalSeconds must be greater than 0.');
    }
    if (!(thresholds.gasWarmUpHours >= 0)) {
      fail('invalid-argument', 'gasWarmUpHours must be at least 0.');
    }
    const before = await readValue(`config/helmets/${helmetId}`);
    const at = nowMs();
    const after = {
      schemaVersion: before?.schemaVersion ?? CONFIG_SCHEMA_VERSION,
      configVersion: before?.configVersion ?? DEFAULT_CONFIG_VERSION,
      helmetId,
      ...thresholds,
      updatedBy: actor.uid,
      updatedAt: at,
    };
    await database.ref(`config/helmets/${helmetId}`).set(after);
    await writeAudit(actor, {
      action: 'setHelmetThresholds',
      targetType: 'config',
      targetId: helmetId,
      summary: `Updated thresholds for helmet ${helmetId}.`,
      before,
      after,
    });
    return { thresholds: after };
  }

  return Object.freeze({
    createUser,
    setUserRole,
    setUserActive,
    updateUserProfile,
    updateUserAssignments,
    deleteUser,
    registerHelmet,
    assignHelmet,
    setHelmetSite,
    retireHelmet,
    rotateHelmetSecret,
    upsertSite,
    setSiteSupervisors,
    setHelmetThresholds,
  });
}
