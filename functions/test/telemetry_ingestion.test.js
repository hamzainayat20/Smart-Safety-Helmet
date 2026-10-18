import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import test from 'node:test';

import { DEVICE_AUTH_HEADERS, signDeviceRequest } from '../src/device_auth.js';
import { createTelemetryIngestionHandler } from '../src/telemetry_ingestion.js';

const initialNow = 1775900000000;
const secret = randomBytes(32);
const registry = JSON.stringify({
  helmet001: { keyVersion: 'v1', secretBase64: secret.toString('base64') },
});

function validPayload(overrides = {}) {
  return {
    schemaVersion: '1.0',
    eventId: 'helmet001_test_1',
    helmetId: 'helmet001',
    deviceTimestamp: initialNow,
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

function getAt(root, path) {
  return path.split('/').filter(Boolean).reduce((value, part) => value?.[part], root);
}

function setAt(root, path, value) {
  const parts = path.split('/').filter(Boolean);
  let target = root;
  for (const part of parts.slice(0, -1)) target = target[part] ??= {};
  const key = parts.at(-1);
  if (value === null) delete target[key];
  else target[key] = structuredClone(value);
}

class FakeDatabase {
  constructor() {
    this.data = {
      helmets: { helmet001: { meta: { active: true, provisioningStatus: 'provisioned' } } },
    };
    this.failTransactionOnce = new Set();
  }

  ref(path = '') {
    const database = this;
    const query = { orderBy: null, endAt: null, limit: null };
    const reference = {
      orderByChild(field) { query.orderBy = field; return reference; },
      endAt(value) { query.endAt = value; return reference; },
      limitToFirst(value) { query.limit = value; return reference; },
      async get() {
        let value = structuredClone(getAt(database.data, path));
        if (query.orderBy && value && typeof value === 'object') {
          value = Object.fromEntries(
            Object.entries(value)
              .filter(([, child]) => child?.[query.orderBy] <= query.endAt)
              .sort(([, left], [, right]) => left[query.orderBy] - right[query.orderBy])
              .slice(0, query.limit),
          );
        }
        return { val: () => value };
      },
      async update(updates) {
        for (const [childPath, value] of Object.entries(updates)) {
          setAt(database.data, path ? `${path}/${childPath}` : childPath, value);
        }
      },
      async transaction(updater) {
        if (database.failTransactionOnce.delete(path)) {
          throw new Error(`simulated transaction failure at ${path}`);
        }
        const current = structuredClone(getAt(database.data, path));
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

function signedRequest(
  payload,
  { nonce = 'nonce_1234567890abcdef', requestTimestamp = initialNow } = {},
) {
  const rawBody = Buffer.from(JSON.stringify(payload));
  return {
    method: 'POST',
    rawBody,
    headers: {
      'content-type': 'application/json',
      [DEVICE_AUTH_HEADERS.helmetId]: 'helmet001',
      [DEVICE_AUTH_HEADERS.timestamp]: String(requestTimestamp),
      [DEVICE_AUTH_HEADERS.nonce]: nonce,
      [DEVICE_AUTH_HEADERS.keyVersion]: 'v1',
      [DEVICE_AUTH_HEADERS.signature]: signDeviceRequest({
        helmetId: 'helmet001', timestamp: requestTimestamp, nonce, rawBody,
      }, secret),
    },
    get(name) { return this.headers[name.toLowerCase()]; },
  };
}

function fakeResponse() {
  return {
    statusCode: null,
    body: null,
    set() { return this; },
    status(code) { this.statusCode = code; return this; },
    json(value) { this.body = value; return this; },
  };
}

async function invoke(
  database,
  payload,
  { now = initialNow, rateLimit, ...requestOptions } = {},
) {
  const response = fakeResponse();
  const handler = createTelemetryIngestionHandler({
    database,
    secretRegistryValue: () => registry,
    clock: () => now,
    ...(rateLimit === undefined ? {} : { rateLimit }),
  });
  await handler(signedRequest(payload, {
    requestTimestamp: now,
    ...requestOptions,
  }), response);
  return response;
}

test('valid telemetry writes current, history and a stable dedupe timestamp', async () => {
  const database = new FakeDatabase();
  const response = await invoke(database, validPayload());
  assert.equal(response.statusCode, 202);
  assert.equal(getAt(database.data, 'helmets/helmet001/current/accelXG'), 0);
  assert.equal(getAt(database.data, 'helmets/helmet001/current/severity'), 'unassessed');
  assert.equal(getAt(database.data, 'readings/helmet001/helmet001_test_1/accelZG'), 1);
  assert.deepEqual(getAt(database.data, 'dedupe/helmet001/helmet001_test_1'), {
    semanticHash: getAt(database.data, 'dedupe/helmet001/helmet001_test_1/semanticHash'),
    status: 'stored',
    firstReceivedAt: initialNow,
  });
});

test('duplicate repair reuses serverReceivedAt and restores missing projections', async () => {
  const database = new FakeDatabase();
  assert.equal((await invoke(database, validPayload())).statusCode, 202);
  setAt(database.data, 'helmets/helmet001/current', null);
  setAt(database.data, 'readings/helmet001/helmet001_test_1', null);

  const retry = await invoke(database, validPayload(), {
    now: initialNow + 1000,
    nonce: 'nonce_abcdef1234567890',
  });
  assert.equal(retry.statusCode, 200);
  assert.equal(retry.body.duplicate, true);
  assert.equal(getAt(database.data, 'helmets/helmet001/current/serverReceivedAt'), initialNow);
  assert.equal(
    getAt(database.data, 'readings/helmet001/helmet001_test_1/serverReceivedAt'),
    initialNow,
  );
});

test('partial operation retry repairs current and retains first receipt time', async () => {
  const database = new FakeDatabase();
  database.failTransactionOnce.add('helmets/helmet001/current');
  const failed = await invoke(database, validPayload());
  assert.equal(failed.statusCode, 503);
  assert.equal(getAt(database.data, 'readings/helmet001/helmet001_test_1/serverReceivedAt'), initialNow);
  assert.equal(getAt(database.data, 'dedupe/helmet001/helmet001_test_1/status'), 'pending');

  const repaired = await invoke(database, validPayload(), {
    now: initialNow + 2000,
    nonce: 'nonce_partial_retry_1234',
  });
  assert.equal(repaired.statusCode, 200);
  assert.equal(getAt(database.data, 'helmets/helmet001/current/serverReceivedAt'), initialNow);
  assert.equal(getAt(database.data, 'dedupe/helmet001/helmet001_test_1/status'), 'stored');
});

test('older history never replaces current and a newer event does', async () => {
  const database = new FakeDatabase();
  const newer = validPayload({ eventId: 'event_newer', deviceTimestamp: initialNow + 1000 });
  assert.equal((await invoke(database, newer)).statusCode, 202);
  const older = validPayload({ eventId: 'event_older', deviceTimestamp: initialNow - 1000 });
  assert.equal((await invoke(database, older, { nonce: 'nonce_older_123456789' })).statusCode, 202);
  assert.equal(getAt(database.data, 'helmets/helmet001/current/eventId'), 'event_newer');
  assert.equal(getAt(database.data, 'readings/helmet001/event_older/eventId'), 'event_older');

  const newest = validPayload({ eventId: 'event_newest', deviceTimestamp: initialNow + 2000 });
  assert.equal((await invoke(database, newest, { nonce: 'nonce_newest_12345678' })).statusCode, 202);
  assert.equal(getAt(database.data, 'helmets/helmet001/current/eventId'), 'event_newest');
});

test('equal timestamps use greater ASCII event ID as deterministic winner', async () => {
  const database = new FakeDatabase();
  assert.equal((await invoke(database, validPayload({ eventId: 'event_B' }))).statusCode, 202);
  assert.equal((await invoke(database, validPayload({ eventId: 'event_A' }), {
    nonce: 'nonce_equal_a_1234567',
  })).statusCode, 202);
  assert.equal(getAt(database.data, 'helmets/helmet001/current/eventId'), 'event_B');
  assert.equal((await invoke(database, validPayload({ eventId: 'event_C' }), {
    nonce: 'nonce_equal_c_1234567',
  })).statusCode, 202);
  assert.equal(getAt(database.data, 'helmets/helmet001/current/eventId'), 'event_C');
});

test('identical event is idempotent but conflicting data is rejected', async () => {
  const database = new FakeDatabase();
  assert.equal((await invoke(database, validPayload())).statusCode, 202);
  const duplicate = await invoke(database, validPayload(), {
    now: initialNow + 1000,
    nonce: 'nonce_duplicate_123456',
  });
  assert.equal(duplicate.statusCode, 200);
  const conflict = await invoke(database, validPayload({ accelXG: 0.5 }), {
    now: initialNow + 2000,
    nonce: 'nonce_conflict_1234567',
  });
  assert.equal(conflict.statusCode, 409);
  assert.equal(conflict.body.error.code, 'EVENT_ID_CONFLICT');
});

test('replayed nonce is rejected', async () => {
  const database = new FakeDatabase();
  assert.equal((await invoke(database, validPayload())).statusCode, 202);
  const replay = await invoke(database, validPayload());
  assert.equal(replay.statusCode, 409);
  assert.equal(replay.body.error.code, 'REPLAYED_REQUEST');
});

test('wrong payload helmet and unprovisioned helmet are denied', async () => {
  const database = new FakeDatabase();
  assert.equal((await invoke(database, validPayload({ helmetId: 'helmet002' }))).statusCode, 403);
  database.data.helmets.helmet001.meta.provisioningStatus = 'unprovisioned';
  const inactive = await invoke(database, validPayload(), {
    nonce: 'nonce_inactive_1234567',
  });
  assert.equal(inactive.statusCode, 403);
  assert.equal(inactive.body.error.code, 'DEVICE_NOT_ACTIVE');
});

test('rate limit rejects excess telemetry without storing it', async () => {
  const database = new FakeDatabase();
  const response = await invoke(database, validPayload(), { rateLimit: 0 });
  assert.equal(response.statusCode, 429);
  assert.equal(response.body.error.code, 'RATE_LIMITED');
});
