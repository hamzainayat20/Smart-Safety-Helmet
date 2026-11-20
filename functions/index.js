import { getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getDatabase } from 'firebase-admin/database';
import { getMessaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onRequest } from 'firebase-functions/v2/https';
import { onValueCreated } from 'firebase-functions/v2/database';
import { defineSecret, defineString } from 'firebase-functions/params';
import { GoogleAuth } from 'google-auth-library';

import {
  AlertValidationError,
  acknowledgeTransition,
  buildAlertRecord,
  canonicalAlertId,
  resolveTransition,
  safeNotificationPayload,
  sanitizeResolutionNote,
  registrationTokenHash,
  tokenAssociationUpdates,
  tokenRemovalUpdates,
  userCanAccessAlert,
  validateAlertDecision,
  validateAlertPayload,
  viewedTransition,
} from './src/alert_logic.js';
import { createTelemetryIngestionHandler } from './src/telemetry_ingestion.js';
import {
  createAssessmentEventHandler,
  createAssessmentProcessor,
} from './src/assessment_pipeline.js';
import { createInferenceClient } from './src/inference_client.js';
import {
  AdminValidationError,
  createAdminService,
} from './src/admin_service.js';

if (getApps().length === 0) initializeApp();

const database = getDatabase();
const auth = getAuth();
const messaging = getMessaging();
const helmetDeviceSecrets = defineSecret('HELMET_DEVICE_SECRETS');
const inferenceServiceUrl = defineString('INFERENCE_SERVICE_URL');
const googleAuth = new GoogleAuth();

async function privateInferenceAuthorization(audience) {
  const client = await googleAuth.getIdTokenClient(audience);
  const headers = await client.getRequestHeaders();
  const value = headers?.get?.('authorization') ??
    headers?.authorization ?? headers?.Authorization;
  return value;
}

const inferenceClient = createInferenceClient({
  endpoint: () => inferenceServiceUrl.value(),
  authorizationHeaderProvider: privateInferenceAuthorization,
});
const assessmentProcessor = createAssessmentProcessor({
  database,
  inferenceClient,
});
const adminService = createAdminService({
  database,
  auth,
  now: () => Date.now(),
});

export const ingestTelemetry = onRequest(
  {
    secrets: [helmetDeviceSecrets],
    timeoutSeconds: 15,
    memory: '256MiB',
    maxInstances: 10,
    concurrency: 20,
    cors: false,
  },
  createTelemetryIngestionHandler({
    database,
    secretRegistryValue: () => helmetDeviceSecrets.value(),
  }),
);

export const assessTelemetry = onValueCreated(
  {
    ref: '/readings/{helmetId}/{eventId}',
    region: 'us-central1',
    timeoutSeconds: 30,
    memory: '512MiB',
    maxInstances: 10,
    concurrency: 10,
    retry: true,
  },
  createAssessmentEventHandler({
    processor: assessmentProcessor,
    logger,
  }),
);

function callableError(error) {
  if (error instanceof HttpsError) return error;
  if (error instanceof AlertValidationError || error instanceof AdminValidationError) {
    return new HttpsError(error.code, error.message);
  }
  logger.error('Alert operation failed', {
    name: error?.name,
    code: error?.code,
  });
  return new HttpsError('internal', 'The alert operation could not be completed.');
}

async function requireActiveUser(request, allowedRoles) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Authentication is required.');
  const uid = request.auth.uid;
  const snapshot = await database.ref(`users/${uid}`).get();
  const user = snapshot.val();
  if (!user || user.active !== true) {
    throw new HttpsError('permission-denied', 'The account is disabled or unavailable.');
  }
  const claimedRole = request.auth.token.role;
  const effectiveRole = claimedRole ?? (user.role === 'worker' ? 'worker' : null);
  if (!effectiveRole || user.role !== effectiveRole || !allowedRoles.includes(effectiveRole)) {
    throw new HttpsError('permission-denied', 'Trusted role authorization is missing.');
  }
  return { uid, user, role: effectiveRole };
}

async function requireAlertAccess(request, allowedRoles) {
  const actor = await requireActiveUser(request, allowedRoles);
  const alertId = request.data?.alertId;
  if (typeof alertId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(alertId)) {
    throw new HttpsError('invalid-argument', 'A valid alertId is required.');
  }
  const reference = database.ref(`alerts/${alertId}`);
  const snapshot = await reference.get();
  const alert = snapshot.val();
  if (!alert) throw new HttpsError('not-found', 'Alert not found.');
  if (!userCanAccessAlert(actor.user, alert, actor.uid, actor.role)) {
    throw new HttpsError('permission-denied', 'The alert is outside the assigned scope.');
  }
  return { ...actor, alertId, alert, reference };
}

async function supervisorTokensFor(alert) {
  const supervisors = (await database.ref(`sites/${alert.siteId}/supervisors`).get()).val() ?? {};
  const result = [];
  for (const uid of Object.keys(supervisors).sort()) {
    if (supervisors[uid] !== true) continue;
    const user = (await database.ref(`users/${uid}`).get()).val();
    if (!user ||
        user.active !== true ||
        user.role !== 'supervisor' ||
        user.siteIds?.[alert.siteId] !== true ||
        user.authorizedHelmetIds?.[alert.helmetId] !== true ||
        user.pushAlertsEnabled === false ||
        (user.criticalAlertsOnly === true && alert.severity !== 'critical')) {
      continue;
    }
    const tokenRecords = (await database.ref(`notificationTokens/${uid}`).get()).val() ?? {};
    for (const [tokenHash, tokenRecord] of Object.entries(tokenRecords)) {
      if (typeof tokenRecord?.token === 'string' && tokenRecord.token.length > 0) {
        result.push({ uid, tokenHash, token: tokenRecord.token });
      }
    }
  }
  return result;
}

async function updateDeliveryAudit(alertId, patch) {
  await database.ref(`alerts/${alertId}/notificationDelivery`).update({
    ...patch,
    lastAttemptAt: Date.now(),
  });
}

async function deliverAlert(alert) {
  const targets = await supervisorTokensFor(alert);
  if (targets.length === 0) {
    await updateDeliveryAudit(alert.alertId, {
      successCount: 0,
      failureCount: 0,
      lastErrorCode: 'NO_AUTHORIZED_TOKENS',
    });
    return (await database.ref(`alerts/${alert.alertId}`).get()).val();
  }
  const safePayload = safeNotificationPayload(alert);
  try {
    const response = await messaging.sendEachForMulticast({
      tokens: targets.map((target) => target.token),
      ...safePayload,
      android: {
        priority: 'high',
        notification: {
          channelId: 'safehelmet_alerts',
          visibility: 'private',
        },
      },
      apns: {
        headers: { 'apns-priority': '10' },
        payload: { aps: { sound: 'default' } },
      },
    });
    const cleanup = {};
    let lastErrorCode = null;
    response.responses.forEach((item, index) => {
      const code = item.error?.code;
      if (code) lastErrorCode = code;
      if (code === 'messaging/invalid-registration-token' ||
          code === 'messaging/registration-token-not-registered') {
        const target = targets[index];
        cleanup[`notificationTokens/${target.uid}/${target.tokenHash}`] = null;
        cleanup[`users/${target.uid}/fcmTokenRefs/${target.tokenHash}`] = null;
        cleanup[`notificationTokenOwners/${target.tokenHash}`] = null;
      }
    });
    if (Object.keys(cleanup).length > 0) await database.ref().update(cleanup);
    const deliveredAt = Date.now();
    if (response.successCount > 0) {
      await database.ref(`alerts/${alert.alertId}`).transaction((current) => {
        if (!current) return current;
        return {
          ...current,
          status: current.status === 'created' ? 'delivered' : current.status,
          deliveredAt: current.deliveredAt ?? deliveredAt,
        };
      });
    }
    await updateDeliveryAudit(alert.alertId, {
      successCount: response.successCount,
      failureCount: response.failureCount,
      lastErrorCode,
    });
  } catch (error) {
    await updateDeliveryAudit(alert.alertId, {
      successCount: 0,
      failureCount: targets.length,
      lastErrorCode: error?.code ?? 'MESSAGING_ERROR',
    });
    logger.error('FCM fan-out failed', {
      alertId: alert.alertId,
      code: error?.code,
      targetCount: targets.length,
    });
  }
  return (await database.ref(`alerts/${alert.alertId}`).get()).val();
}

export const submitAlert = onCall(async (request) => {
  try {
    if (!request.auth ||
        request.auth.token.device !== true ||
        typeof request.auth.token.helmetId !== 'string') {
      throw new HttpsError('permission-denied', 'A helmet-bound device identity is required.');
    }
    const now = Date.now();
    const payload = validateAlertPayload(request.data, {
      claimedHelmetId: request.auth.token.helmetId,
      now,
    });
    const meta = (await database.ref(`helmets/${payload.helmetId}/meta`).get()).val();
    if (!meta || meta.active !== true || meta.provisioningStatus !== 'provisioned') {
      throw new HttpsError('permission-denied', 'Helmet is inactive or not provisioned.');
    }
    const [defaultsSnapshot, overrideSnapshot] = await Promise.all([
      database.ref('config/defaults').get(),
      database.ref(`config/helmets/${payload.helmetId}`).get(),
    ]);
    validateAlertDecision(payload, {
      ...(defaultsSnapshot.val() ?? {}),
      ...(overrideSnapshot.val() ?? {}),
    });
    const alert = buildAlertRecord(payload, meta, now);
    const reference = database.ref(`alerts/${alert.alertId}`);
    const transaction = await reference.transaction((current) => {
      if (current) return undefined;
      return alert;
    });
    const canonical = transaction.snapshot.val();
    const duplicate = transaction.committed === false;
    await database.ref(`dedupe/${payload.helmetId}/${canonicalAlertId(payload.helmetId, payload.eventId)}`).set({
      alertId: alert.alertId,
      createdAt: canonical.serverReceivedAt,
    });
    if (duplicate) return { alert: canonical, duplicate: true };
    return { alert: await deliverAlert(canonical), duplicate: false };
  } catch (error) {
    throw callableError(error);
  }
});

export const markAlertViewed = onCall(async (request) => {
  try {
    const actor = await requireAlertAccess(request, ['worker', 'supervisor', 'administrator']);
    const now = Date.now();
    const result = await actor.reference.transaction((current) =>
      current ? viewedTransition(current, actor.uid, now) : current,
    );
    return { alert: result.snapshot.val() };
  } catch (error) {
    throw callableError(error);
  }
});

export const acknowledgeAlert = onCall(async (request) => {
  try {
    const actor = await requireAlertAccess(request, ['supervisor', 'administrator']);
    const now = Date.now();
    const result = await actor.reference.transaction((current) =>
      current ? acknowledgeTransition(current, actor.uid, now) : current,
    );
    return { alert: result.snapshot.val() };
  } catch (error) {
    throw callableError(error);
  }
});

export const resolveAlert = onCall(async (request) => {
  try {
    const actor = await requireAlertAccess(request, ['supervisor', 'administrator']);
    const note = sanitizeResolutionNote(request.data?.resolutionNote);
    const current = (await database.ref(`helmets/${actor.alert.helmetId}/current`).get()).val();
    const now = Date.now();
    const result = await actor.reference.transaction((alert) =>
      alert ? resolveTransition(alert, actor.uid, note, current, now) : alert,
    );
    return { alert: result.snapshot.val() };
  } catch (error) {
    throw callableError(error);
  }
});

export const retryAlertDelivery = onCall(async (request) => {
  try {
    const actor = await requireAlertAccess(request, ['supervisor', 'administrator']);
    return { alert: await deliverAlert(actor.alert) };
  } catch (error) {
    throw callableError(error);
  }
});

export const registerFcmToken = onCall(async (request) => {
  try {
    const actor = await requireActiveUser(request, ['supervisor']);
    const token = request.data?.token;
    const platform = request.data?.platform;
    if (typeof token !== 'string' || token.length < 16 || token.length > 4096) {
      throw new HttpsError('invalid-argument', 'A valid FCM registration token is required.');
    }
    if (!['android', 'ios', 'macos', 'web', 'windows', 'linux'].includes(platform)) {
      throw new HttpsError('invalid-argument', 'Unsupported notification platform.');
    }
    const tokenHash = registrationTokenHash(token);
    const now = Date.now();
    const existing = (await database.ref(`notificationTokens/${actor.uid}/${tokenHash}`).get()).val();
    const previousOwner = (await database.ref(`notificationTokenOwners/${tokenHash}`).get()).val();
    const { updates } = tokenAssociationUpdates({
      uid: actor.uid,
      token,
      platform,
      now,
      existingCreatedAt: existing?.createdAt,
      previousOwner,
    });
    await database.ref().update(updates);
    return { tokenRef: tokenHash };
  } catch (error) {
    throw callableError(error);
  }
});

export const removeFcmToken = onCall(async (request) => {
  try {
    const actor = await requireActiveUser(request, ['supervisor']);
    const token = request.data?.token;
    if (typeof token !== 'string' || token.length < 16 || token.length > 4096) {
      throw new HttpsError('invalid-argument', 'A valid FCM registration token is required.');
    }
    const tokenHash = registrationTokenHash(token);
    const ownerReference = database.ref(`notificationTokenOwners/${tokenHash}`);
    const owner = (await ownerReference.get()).val();
    const { updates } = tokenRemovalUpdates({
      uid: actor.uid,
      token,
      owner,
    });
    await database.ref().update(updates);
    return { removed: true };
  } catch (error) {
    throw callableError(error);
  }
});

// ---------------------------------------------------------------------------
// Admin Console (module M15) — thin administrator-only wrappers around
// createAdminService. Every operation is audited inside the service.

export const adminCreateUser = onCall(async (request) => {
  try {
    const actor = await requireActiveUser(request, ['administrator']);
    return await adminService.createUser(actor, request.data ?? {});
  } catch (error) {
    throw callableError(error);
  }
});

export const adminSetUserRole = onCall(async (request) => {
  try {
    const actor = await requireActiveUser(request, ['administrator']);
    return await adminService.setUserRole(actor, request.data ?? {});
  } catch (error) {
    throw callableError(error);
  }
});

export const adminSetUserActive = onCall(async (request) => {
  try {
    const actor = await requireActiveUser(request, ['administrator']);
    return await adminService.setUserActive(actor, request.data ?? {});
  } catch (error) {
    throw callableError(error);
  }
});

export const adminUpdateUserProfile = onCall(async (request) => {
  try {
    const actor = await requireActiveUser(request, ['administrator']);
    return await adminService.updateUserProfile(actor, request.data ?? {});
  } catch (error) {
    throw callableError(error);
  }
});

export const adminUpdateUserAssignments = onCall(async (request) => {
  try {
    const actor = await requireActiveUser(request, ['administrator']);
    return await adminService.updateUserAssignments(actor, request.data ?? {});
  } catch (error) {
    throw callableError(error);
  }
});

export const adminDeleteUser = onCall(async (request) => {
  try {
    const actor = await requireActiveUser(request, ['administrator']);
    return await adminService.deleteUser(actor, request.data ?? {});
  } catch (error) {
    throw callableError(error);
  }
});

export const adminRegisterHelmet = onCall(async (request) => {
  try {
    const actor = await requireActiveUser(request, ['administrator']);
    return await adminService.registerHelmet(actor, request.data ?? {});
  } catch (error) {
    throw callableError(error);
  }
});

export const adminAssignHelmet = onCall(async (request) => {
  try {
    const actor = await requireActiveUser(request, ['administrator']);
    return await adminService.assignHelmet(actor, request.data ?? {});
  } catch (error) {
    throw callableError(error);
  }
});

export const adminSetHelmetSite = onCall(async (request) => {
  try {
    const actor = await requireActiveUser(request, ['administrator']);
    return await adminService.setHelmetSite(actor, request.data ?? {});
  } catch (error) {
    throw callableError(error);
  }
});

export const adminRetireHelmet = onCall(async (request) => {
  try {
    const actor = await requireActiveUser(request, ['administrator']);
    return await adminService.retireHelmet(actor, request.data ?? {});
  } catch (error) {
    throw callableError(error);
  }
});

export const adminRotateHelmetSecret = onCall(async (request) => {
  try {
    const actor = await requireActiveUser(request, ['administrator']);
    return await adminService.rotateHelmetSecret(actor, request.data ?? {});
  } catch (error) {
    throw callableError(error);
  }
});

export const adminUpsertSite = onCall(async (request) => {
  try {
    const actor = await requireActiveUser(request, ['administrator']);
    return await adminService.upsertSite(actor, request.data ?? {});
  } catch (error) {
    throw callableError(error);
  }
});

export const adminSetSiteSupervisors = onCall(async (request) => {
  try {
    const actor = await requireActiveUser(request, ['administrator']);
    return await adminService.setSiteSupervisors(actor, request.data ?? {});
  } catch (error) {
    throw callableError(error);
  }
});

export const adminSetHelmetThresholds = onCall(async (request) => {
  try {
    const actor = await requireActiveUser(request, ['administrator']);
    return await adminService.setHelmetThresholds(actor, request.data ?? {});
  } catch (error) {
    throw callableError(error);
  }
});
