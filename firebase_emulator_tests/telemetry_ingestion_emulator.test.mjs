import assert from 'node:assert/strict';
import { createHmac, createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import test from 'node:test';

const requireFunctions = createRequire(
  new URL('../functions/package.json', import.meta.url),
);
const { deleteApp, initializeApp } = requireFunctions('firebase-admin/app');
const { getDatabase } = requireFunctions('firebase-admin/database');

const projectId = process.env.GCLOUD_PROJECT ?? 'smart-safety-rules-test';
const functionsHost =
  process.env.FUNCTIONS_EMULATOR_HOST ?? '127.0.0.1:5001';
const endpoint = `http://${functionsHost}/${projectId}/us-central1/ingestTelemetry`;
const emulatorFirebaseConfig = JSON.parse(process.env.FIREBASE_CONFIG ?? '{}');
const app = initializeApp({
  projectId,
  databaseURL: emulatorFirebaseConfig.databaseURL ??
    `https://${projectId}.firebaseio.com`,
}, 'telemetry-ingestion-emulator-test');
const database = getDatabase(app);

const secrets = {
  helmet001: Buffer.alloc(32, 0x11),
  helmetRevoked: Buffer.alloc(32, 0x33),
  helmetRate: Buffer.alloc(32, 0x22),
};

function payload({ helmetId = 'helmet001', eventId, deviceTimestamp, ...overrides }) {
  return {
    schemaVersion: '1.0',
    eventId,
    helmetId,
    deviceTimestamp,
    firmwareVersion: '0.2.0-emulator-test',
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

function signedRequest(body, {
  nonce,
  requestTimestamp = Date.now(),
  signatureOverride,
} = {}) {
  const rawBody = JSON.stringify(body);
  const helmetId = body.helmetId;
  const requestNonce = nonce ?? `nonce_${createHash('sha256')
    .update(`${body.eventId}:${requestTimestamp}:${Math.random()}`)
    .digest('hex').slice(0, 32)}`;
  const bodyHash = createHash('sha256').update(rawBody).digest('hex');
  const canonical = [
    'POST',
    `/ingest/v1/helmets/${helmetId}/telemetry`,
    String(requestTimestamp),
    requestNonce,
    bodyHash,
  ].join('\n');
  const signature = createHmac('sha256', secrets[helmetId])
    .update(canonical)
    .digest('hex');
  return {
    rawBody,
    headers: {
      'content-type': 'application/json',
      'x-smart-safety-helmet-id': helmetId,
      'x-smart-safety-timestamp': String(requestTimestamp),
      'x-smart-safety-nonce': requestNonce,
      'x-smart-safety-key-version': 'v1',
      'x-smart-safety-signature': signatureOverride ?? signature,
    },
  };
}

async function send(request) {
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: request.headers,
    body: request.rawBody,
  });
  return { status: response.status, body: await response.json() };
}

async function value(path) {
  return (await database.ref(path).get()).val();
}

test('actual Functions and RTDB emulators enforce telemetry ingestion', async (t) => {
  const baseTime = Date.now() - 10000;
  await database.ref().set({
    helmets: {
      helmet001: { meta: { active: true, provisioningStatus: 'provisioned' } },
      helmetRevoked: { meta: { active: true, provisioningStatus: 'provisioned' } },
      helmetRate: { meta: { active: true, provisioningStatus: 'provisioned' } },
    },
  });

  await t.test('valid signed HTTPS-style request', async () => {
    const body = payload({ eventId: 'valid_event', deviceTimestamp: baseTime });
    const result = await send(signedRequest(body));
    assert.equal(result.status, 202, JSON.stringify({
      response: result.body,
      dedupe: await value('dedupe/helmet001/valid_event'),
    }));
    assert.equal((await value('helmets/helmet001/current')).eventId, 'valid_event');
    assert.equal((await value('readings/helmet001/valid_event')).severity, 'unassessed');
  });

  await t.test('invalid, revoked and expired authentication', async () => {
    const invalid = payload({ eventId: 'invalid_signature', deviceTimestamp: baseTime });
    assert.equal((await send(signedRequest(invalid, {
      signatureOverride: '00'.repeat(32),
    }))).status, 401);

    const revoked = payload({
      helmetId: 'helmetRevoked', eventId: 'revoked_event', deviceTimestamp: baseTime,
    });
    assert.equal((await send(signedRequest(revoked))).status, 401);

    const expired = payload({ eventId: 'expired_request', deviceTimestamp: baseTime });
    assert.equal((await send(signedRequest(expired, {
      requestTimestamp: Date.now() - 300001,
    }))).status, 401);
  });

  await t.test('nonce replay and semantic duplicate/conflict behavior', async () => {
    const replayBody = payload({ eventId: 'replay_event', deviceTimestamp: baseTime + 1 });
    const replayRequest = signedRequest(replayBody, { nonce: 'nonce_replay_emulator_123456' });
    assert.equal((await send(replayRequest)).status, 202);
    assert.equal((await send(replayRequest)).status, 409);

    const duplicateBody = payload({ eventId: 'duplicate_event', deviceTimestamp: baseTime + 2 });
    assert.equal((await send(signedRequest(duplicateBody))).status, 202);
    const firstServerTime = (await value('readings/helmet001/duplicate_event')).serverReceivedAt;
    await new Promise((resolve) => setTimeout(resolve, 10));
    const duplicate = await send(signedRequest(duplicateBody));
    assert.equal(duplicate.status, 200);
    assert.equal(
      (await value('readings/helmet001/duplicate_event')).serverReceivedAt,
      firstServerTime,
    );

    const conflict = { ...duplicateBody, accelXG: 0.25 };
    const conflictResult = await send(signedRequest(conflict));
    assert.equal(conflictResult.status, 409);
    assert.equal(conflictResult.body.error.code, 'EVENT_ID_CONFLICT');
  });

  await t.test('device-time ordering and deterministic equal-time tie-break', async () => {
    const newer = payload({ eventId: 'order_newer', deviceTimestamp: baseTime + 2000 });
    assert.equal((await send(signedRequest(newer))).status, 202);
    const older = payload({ eventId: 'order_older', deviceTimestamp: baseTime + 1000 });
    assert.equal((await send(signedRequest(older))).status, 202);
    assert.equal((await value('helmets/helmet001/current')).eventId, 'order_newer');
    assert.equal((await value('readings/helmet001/order_older')).eventId, 'order_older');

    const equalA = payload({ eventId: 'equal_A', deviceTimestamp: baseTime + 3000 });
    const equalC = payload({ eventId: 'equal_C', deviceTimestamp: baseTime + 3000 });
    const equalB = payload({ eventId: 'equal_B', deviceTimestamp: baseTime + 3000 });
    assert.equal((await send(signedRequest(equalA))).status, 202);
    assert.equal((await send(signedRequest(equalC))).status, 202);
    assert.equal((await send(signedRequest(equalB))).status, 202);
    assert.equal((await value('helmets/helmet001/current')).eventId, 'equal_C');
  });

  await t.test('stored duplicate repairs missing state without becoming current when older', async () => {
    const repair = payload({ eventId: 'repair_event', deviceTimestamp: baseTime + 4000 });
    assert.equal((await send(signedRequest(repair))).status, 202);
    const originalServerTime = (await value('readings/helmet001/repair_event')).serverReceivedAt;
    const latest = payload({ eventId: 'repair_newer', deviceTimestamp: baseTime + 5000 });
    assert.equal((await send(signedRequest(latest))).status, 202);
    await database.ref('readings/helmet001/repair_event').remove();
    const repaired = await send(signedRequest(repair));
    assert.equal(repaired.status, 200);
    assert.equal((await value('readings/helmet001/repair_event')).serverReceivedAt, originalServerTime);
    assert.equal((await value('helmets/helmet001/current')).eventId, 'repair_newer');

    await database.ref('helmets/helmet001/current').remove();
    assert.equal((await send(signedRequest(latest))).status, 200);
    assert.equal((await value('helmets/helmet001/current')).eventId, 'repair_newer');
  });

  await t.test('backend-owned fields are rejected', async () => {
    const result = await send(signedRequest(payload({
      eventId: 'backend_owned',
      deviceTimestamp: baseTime + 6000,
      severity: 'safe',
    })));
    assert.equal(result.status, 400);
    assert.equal(result.body.error.code, 'BACKEND_OWNED_FIELD');
  });

  await t.test('expired nonce/rate entries are cleaned but active entries remain', async () => {
    const now = Date.now();
    await database.ref().update({
      'ingestionNonces/helmet001/expired_nonce': { expiresAt: now - 1 },
      'ingestionNonces/helmet001/active_nonce': { expiresAt: now + 600000 },
      'ingestionRateLimits/helmet001/expired_window': { expiresAt: now - 1 },
      'ingestionRateLimits/helmet001/active_window': { expiresAt: now + 600000 },
    });
    const cleanup = payload({ eventId: 'cleanup_trigger', deviceTimestamp: baseTime + 7000 });
    assert.equal((await send(signedRequest(cleanup))).status, 202);
    assert.equal(await value('ingestionNonces/helmet001/expired_nonce'), null);
    assert.equal(await value('ingestionRateLimits/helmet001/expired_window'), null);
    assert.notEqual(await value('ingestionNonces/helmet001/active_nonce'), null);
    assert.notEqual(await value('ingestionRateLimits/helmet001/active_window'), null);
  });

  await t.test('rate limiting rejects request 31 in one minute', async () => {
    const outcomes = [];
    for (let index = 0; index < 31; index += 1) {
      const body = payload({
        helmetId: 'helmetRate',
        eventId: `rate_${String(index).padStart(2, '0')}`,
        deviceTimestamp: baseTime + index,
      });
      outcomes.push((await send(signedRequest(body))).status);
    }
    assert.deepEqual(outcomes.slice(0, 30), Array(30).fill(202));
    assert.equal(outcomes[30], 429);
  });
});

test.after(async () => {
  await database.ref().set(null);
  await deleteApp(app);
});
