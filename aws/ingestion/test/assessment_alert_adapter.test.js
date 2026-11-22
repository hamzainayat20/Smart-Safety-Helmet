import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import test from 'node:test';

import { DEVICE_AUTH_HEADERS, signDeviceRequest } from '../../../functions/src/device_auth.js';
import { createAwsTelemetryHandler } from '../api_adapter.js';

const now = 1775900000000;
const secret = randomBytes(32);
const registry = JSON.stringify({
  helmet001: { keyVersion: 'v1', secretBase64: secret.toString('base64') },
});

function payload(overrides = {}) {
  return {
    schemaVersion: '2.0',
    eventId: 'helmet001_window_1',
    helmetId: 'helmet001',
    deviceTimestamp: now,
    firmwareVersion: '0.3.0-staging',
    temperatureC: 37.4,
    humidityPct: 22,
    heatIndexC: 36.1,
    accelXG: 0, accelYG: 0, accelZG: 1,
    gyroXDegreesPerSecond: 0, gyroYDegreesPerSecond: 0, gyroZDegreesPerSecond: 0,
    mq7Raw: 2700,
    mq7WarmUp: true,
    mq135WarmUp: false,
    fallFeatures: {
      acc_mean: 1, acc_std: 0.01, acc_min: 0.98, acc_max: 1.02,
      gyro_mean: 0.2, gyro_std: 0.1, gyro_max: 0.5, jerk_mean: 0.1, jerk_max: 0.3,
    },
    samplingRateHz: 50,
    windowSamples: 100,
    windowEndTimestamp: now,
    sensorFaults: [
      'batteryUnavailable', 'gpsUnavailable', 'mq135HeaterStateUnknown',
      'mq135ReadFailed', 'mq135Uncalibrated', 'mq7HeaterStateUnknown', 'mq7Uncalibrated',
    ],
    ...overrides,
  };
}

function getAt(root, path) {
  return path.split('/').filter(Boolean).reduce((value, part) => value?.[part], root);
}

function setAt(root, path, value) {
  const parts = path.split('/').filter(Boolean);
  let target = root;
  for (const part of parts.slice(0, -1)) target = target[part] ??= {};
  const key = parts.at(-1);
  if (value === null || value === undefined) delete target[key];
  else target[key] = structuredClone(value);
}

class FakeDatabase {
  constructor() {
    this.data = {
      helmets: {
        helmet001: {
          meta: {
            active: true, provisioningStatus: 'provisioned',
            siteId: 'site-main', assignedWorkerId: 'workerUid1',
          },
        },
      },
    };
  }

  ref(path = '') {
    const database = this;
    const query = { orderBy: null, endAt: null, limit: null };
    const reference = {
      orderByChild(field) { query.orderBy = field; return reference; },
      endAt(value) { query.endAt = value; return reference; },
      limitToFirst(value) { query.limit = value; return reference; },
      async get() {
        let value = structuredClone(getAt(database.data, path) ?? null);
        if (query.orderBy && value && typeof value === 'object') {
          value = Object.fromEntries(
            Object.entries(value)
              .filter(([, child]) => child?.[query.orderBy] <= query.endAt)
              .slice(0, query.limit),
          );
        }
        return { val: () => value };
      },
      async set(value) { setAt(database.data, path, value); },
      async update(updates) {
        for (const [childPath, value] of Object.entries(updates)) {
          setAt(database.data, path ? `${path}/${childPath}` : childPath, value);
        }
      },
      async transaction(updater) {
        const current = structuredClone(getAt(database.data, path) ?? null);
        const next = updater(current);
        if (next === undefined) {
          return { committed: false, snapshot: { val: () => current } };
        }
        setAt(database.data, path, next);
        return { committed: true, snapshot: { val: () => structuredClone(next) } };
      },
    };
    return reference;
  }
}

function inferenceClientReturning(risk) {
  return {
    async assess(record) {
      const warning = risk === 'warning';
      return {
        schemaVersion: '1.0',
        assessmentId: record.eventId,
        eventId: record.eventId,
        helmetId: record.helmetId,
        sourceSchemaVersion: '2.0',
        deviceTimestamp: record.deviceTimestamp,
        sourceServerReceivedAt: record.serverReceivedAt,
        assessedAt: record.serverReceivedAt + 10,
        modelBundleVersion: 'phase-a.1',
        gasInputMode: record.gasInputMode ?? 'baselineLearning',
        mq7Ratio: record.mq7Ratio ?? null,
        mq135Ratio: record.mq135Ratio ?? null,
        gasThresholdRisk: record.gasInputMode === 'baselineMapped' ? 'safe' : 'unknown',
        gasThresholdConsecutive: record.gasThresholdConsecutive ?? 0,
        fall: { status: 'evaluated', probability: 0.00003, threshold: 0.46, modelVersion: '2.0' },
        gas: { status: 'unavailable' },
        environment: {
          status: 'evaluated',
          temperatureRisk: warning ? 'warning' : 'normal',
          humidityRisk: 'normal',
          heatIndexRisk: 'normal',
        },
        overallRisk: warning ? 'warning' : 'unknown',
        reasonCodes: warning
          ? ['GAS_MODEL_UNAVAILABLE', 'SENSOR_FAULT', 'TEMPERATURE_WARNING']
          : ['GAS_MODEL_UNAVAILABLE', 'SENSOR_FAULT'],
        recommendationCodes: warning
          ? ['MOVE_TO_SAFE_TEMPERATURE', 'VERIFY_SENSORS']
          : ['VERIFY_SENSORS'],
      };
    },
  };
}

function gatewayEvent(body, nonce = 'nonce_1234567890abcdef') {
  const rawBody = Buffer.from(JSON.stringify(body));
  return {
    body: rawBody.toString('utf8'),
    isBase64Encoded: false,
    requestContext: { http: { method: 'POST' } },
    headers: {
      'content-type': 'application/json',
      [DEVICE_AUTH_HEADERS.helmetId]: 'helmet001',
      [DEVICE_AUTH_HEADERS.timestamp]: String(now),
      [DEVICE_AUTH_HEADERS.nonce]: nonce,
      [DEVICE_AUTH_HEADERS.keyVersion]: 'v1',
      [DEVICE_AUTH_HEADERS.signature]: signDeviceRequest({
        helmetId: 'helmet001', timestamp: now, nonce, rawBody,
      }, secret),
    },
  };
}

function handlerFor(database, risk, extra = {}) {
  return createAwsTelemetryHandler({
    database,
    secretRegistryValue: () => registry,
    inferenceClient: inferenceClientReturning(risk),
    clock: () => now,
    ...extra,
  });
}

test('a warning assessment creates exactly one in-app alert record', async () => {
  const database = new FakeDatabase();
  const response = await handlerFor(database, 'warning')(gatewayEvent(payload()));
  assert.equal(response.statusCode, 202);
  assert.equal(JSON.parse(response.body).assessmentStatus, 'completed');
  const alerts = Object.values(database.data.alerts ?? {});
  assert.equal(alerts.length, 1);
  assert.equal(alerts[0].alertType, 'temperature');
  assert.equal(alerts[0].severity, 'warning');
  assert.equal(alerts[0].sensorValue, 37.4);
  assert.equal(alerts[0].siteId, 'site-main');
  assert.equal(alerts[0].workerId, 'workerUid1');
  assert.equal(alerts[0].status, 'created');
});

test('a non-hazard assessment creates no alert and the response is unchanged', async () => {
  const database = new FakeDatabase();
  const response = await handlerFor(database, 'unknown')(gatewayEvent(payload({ temperatureC: 30 })));
  assert.equal(response.statusCode, 202);
  assert.equal(JSON.parse(response.body).assessmentStatus, 'completed');
  assert.equal(database.data.alerts, undefined);
});

test('an alert failure never changes the device response or stored data', async () => {
  const database = new FakeDatabase();
  const response = await handlerFor(database, 'warning', {
    alertWriter: async () => { throw new Error('alert store unavailable'); },
  })(gatewayEvent(payload()));
  assert.equal(response.statusCode, 202);
  assert.equal(JSON.parse(response.body).assessmentStatus, 'completed');
  assert.ok(getAt(database.data, 'readings/helmet001/helmet001_window_1'));
  assert.equal(
    getAt(database.data, 'assessments/helmet001/helmet001_window_1/overallRisk'),
    'warning',
  );
  assert.equal(database.data.alerts, undefined);
});

test('a push failure never changes a successful ingestion response', async () => {
  const database = new FakeDatabase();
  let attempts = 0;
  const response = await handlerFor(database, 'warning', {
    alertDelivery: async () => {
      attempts += 1;
      throw new Error('messaging unavailable');
    },
  })(gatewayEvent(payload()));
  assert.equal(response.statusCode, 202);
  assert.equal(JSON.parse(response.body).assessmentStatus, 'completed');
  assert.equal(attempts, 1);
  assert.equal(Object.values(database.data.alerts ?? {}).length, 1);
});
