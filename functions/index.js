import { getApps, initializeApp } from 'firebase-admin/app';
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
  buildAlertRecord,
  canonicalAlertId,
  validateAlertDecision,
  validateAlertPayload,
} from './src/alert_logic.js';
import { createTelemetryIngestionHandler } from './src/telemetry_ingestion.js';
import {
  createAssessmentEventHandler,
  createAssessmentProcessor,
} from './src/assessment_pipeline.js';
import { createInferenceClient } from './src/inference_client.js';
import { createAlertDelivery } from './src/alert_delivery.js';

if (getApps().length === 0) initializeApp();

const database = getDatabase();
const messaging = getMessaging();
const deliverAlert = createAlertDelivery({ database, messaging });
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
  if (error instanceof AlertValidationError) {
    return new HttpsError(error.code, error.message);
  }
  logger.error('Alert operation failed', {
    name: error?.name,
    code: error?.code,
  });
  return new HttpsError('internal', 'The alert operation could not be completed.');
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

