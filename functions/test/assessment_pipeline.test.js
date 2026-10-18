import assert from 'node:assert/strict';
import test from 'node:test';

import {
  AssessmentPipelineError,
  createAssessmentEventHandler,
  createAssessmentProcessor,
} from '../src/assessment_pipeline.js';
import {
  assessmentInputFromTelemetry,
  createInferenceClient,
  InferenceServiceError,
} from '../src/inference_client.js';

const now = 1_800_000_000_500;

function telemetry(overrides = {}) {
  return {
    schemaVersion: '2.0', eventId: 'event_1', helmetId: 'helmet001',
    deviceTimestamp: now - 100, serverReceivedAt: now - 50,
    firmwareVersion: '0.3.0-staging', sensorFaults: [],
    mq7Raw: 575, mq135Raw: 443, mq7WarmUp: false, mq135WarmUp: false,
    temperatureC: 27, humidityPct: 55, heatIndexC: 28,
    fallFeatures: {
      acc_mean: 1, acc_std: 0.05, acc_min: 0.9, acc_max: 1.1,
      gyro_mean: 1, gyro_std: 0.2, gyro_max: 2,
      jerk_mean: 0.1, jerk_max: 0.3,
    },
    samplingRateHz: 50, windowSamples: 100, windowEndTimestamp: now - 100,
    connectivity: 'online', severity: 'unassessed',
    ...overrides,
  };
}

function assessment(overrides = {}) {
  return {
    schemaVersion: '1.0', assessmentId: 'event_1', eventId: 'event_1',
    helmetId: 'helmet001', sourceSchemaVersion: '2.0',
    deviceTimestamp: now - 100, sourceServerReceivedAt: now - 50,
    assessedAt: now - 50, modelBundleVersion: 'phase-a.1',
    fall: { status: 'evaluated', probability: 0.1, threshold: 0.46, modelVersion: '2.0' },
    gas: {
      status: 'evaluated', classification: 'NoGas', confidence: 0.9,
      probabilities: { Mixture: 0.02, NoGas: 0.9, Perfume: 0.05, Smoke: 0.03 },
      modelVersion: '1.0', outOfDistribution: false,
    },
    environment: {
      status: 'evaluated', temperatureRisk: 'normal',
      humidityRisk: 'normal', heatIndexRisk: 'normal',
    },
    overallRisk: 'safe', reasonCodes: ['GAS_NO_GAS'],
    recommendationCodes: ['NO_IMMEDIATE_ACTION'],
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
  target[parts.at(-1)] = structuredClone(value);
}

class FakeDatabase {
  constructor(record = telemetry()) {
    this.data = { readings: { helmet001: { event_1: structuredClone(record) } } };
  }
  ref(path) {
    const database = this;
    return {
      async get() {
        const value = structuredClone(getAt(database.data, path));
        return { val: () => value };
      },
      async update(patch) {
        for (const [key, value] of Object.entries(patch)) {
          setAt(database.data, `${path}/${key}`, value);
        }
      },
      async transaction(updater) {
        const current = structuredClone(getAt(database.data, path));
        const next = updater(current);
        if (next === undefined) {
          return { committed: false, snapshot: { val: () => current } };
        }
        setAt(database.data, path, next);
        return { committed: true, snapshot: { val: () => structuredClone(next) } };
      },
    };
  }
}

test('inference input includes only the canonical model fields', () => {
  const input = assessmentInputFromTelemetry(telemetry());
  assert.equal(input.mq7Raw, 575);
  assert.equal(input.mq135Raw, 443);
  assert.equal(input.connectivity, undefined);
  assert.equal(input.severity, undefined);
  assert.deepEqual(Object.keys(input), [
    'schemaVersion', 'eventId', 'helmetId', 'deviceTimestamp', 'serverReceivedAt',
    'firmwareVersion', 'sensorFaults', 'mq7Raw', 'mq135Raw', 'mq7WarmUp',
    'mq135WarmUp', 'temperatureC', 'humidityPct', 'heatIndexC', 'fallFeatures',
    'samplingRateHz', 'windowSamples', 'windowEndTimestamp',
  ]);
});

test('private client sends a bearer token and validates the returned contract', async () => {
  let captured;
  const client = createInferenceClient({
    endpoint: 'https://inference.example.test',
    authorizationHeaderProvider: async (audience) => {
      assert.equal(audience, 'https://inference.example.test');
      return 'Bearer test-identity-token';
    },
    fetchImpl: async (url, options) => {
      captured = { url, options };
      return new Response(JSON.stringify(assessment()), {
        status: 200, headers: { 'content-type': 'application/json' },
      });
    },
  });
  const result = await client.assess(telemetry());
  assert.equal(result.overallRisk, 'safe');
  assert.equal(captured.url, 'https://inference.example.test/v1/assess');
  assert.equal(captured.options.headers.authorization, 'Bearer test-identity-token');
});

test('insecure remote inference endpoints are rejected', async () => {
  const client = createInferenceClient({
    endpoint: 'http://inference.example.test', fetchImpl: async () => null,
  });
  await assert.rejects(
    client.assess(telemetry()),
    (error) => error instanceof InferenceServiceError &&
      error.code === 'INFERENCE_URL_INSECURE' && error.retryable === false,
  );
});

test('pipeline stores assessment history/current and is idempotent', async () => {
  const database = new FakeDatabase();
  let calls = 0;
  const processor = createAssessmentProcessor({
    database, clock: () => now,
    inferenceClient: { async assess() { calls += 1; return assessment(); } },
  });
  const first = await processor(telemetry());
  assert.equal(first.status, 'completed');
  assert.equal(first.duplicate, false);
  assert.equal(getAt(database.data, 'assessments/helmet001/event_1/overallRisk'), 'safe');
  assert.equal(getAt(database.data, 'helmets/helmet001/currentAssessment/eventId'), 'event_1');
  assert.equal(getAt(database.data, 'assessmentJobs/helmet001/event_1/status'), 'completed');

  const duplicate = await processor(telemetry());
  assert.equal(duplicate.duplicate, true);
  assert.equal(calls, 1);
});

test('pipeline records a safe error code and never creates a fake assessment', async () => {
  const database = new FakeDatabase();
  const processor = createAssessmentProcessor({
    database, clock: () => now,
    inferenceClient: {
      async assess() {
        throw new InferenceServiceError('INFERENCE_UNAVAILABLE', 'secret internal detail');
      },
    },
  });
  await assert.rejects(
    processor(telemetry()),
    (error) => error instanceof AssessmentPipelineError &&
      error.code === 'INFERENCE_UNAVAILABLE',
  );
  assert.equal(getAt(database.data, 'assessments/helmet001/event_1'), undefined);
  assert.deepEqual(
    getAt(database.data, 'assessmentJobs/helmet001/event_1'),
    {
      status: 'failed', attemptCount: 1, firstAttemptAt: now,
      lastAttemptAt: now, lastErrorCode: 'INFERENCE_UNAVAILABLE', failedAt: now,
    },
  );
});

test('database event handler stops retrying a permanent source/path mismatch', async () => {
  const messages = [];
  const handler = createAssessmentEventHandler({
    processor: async () => null,
    logger: { error: (...values) => messages.push(values) },
  });
  const result = await handler({
    data: { val: () => telemetry() },
    params: { helmetId: 'helmet002', eventId: 'event_1' },
  });
  assert.deepEqual(result, {
    status: 'rejected', code: 'ASSESSMENT_SOURCE_PATH_MISMATCH',
  });
  assert.equal(messages.length, 1);
});

test('database event handler retries transient failures but acknowledges permanent ones', async () => {
  const event = {
    data: { val: () => telemetry() },
    params: { helmetId: 'helmet001', eventId: 'event_1' },
  };
  const transient = createAssessmentEventHandler({
    processor: async () => { throw new AssessmentPipelineError('TEMPORARY', 'failed'); },
    logger: { error() {} },
  });
  await assert.rejects(transient(event), { code: 'TEMPORARY' });

  const permanent = createAssessmentEventHandler({
    processor: async () => {
      throw new AssessmentPipelineError('INVALID_MODEL_RESPONSE', 'failed', {
        retryable: false,
      });
    },
    logger: { error() {} },
  });
  assert.deepEqual(await permanent(event), {
    status: 'failed', code: 'INVALID_MODEL_RESPONSE',
  });
});
