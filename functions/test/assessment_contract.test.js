import assert from 'node:assert/strict';
import test from 'node:test';

import {
  AssessmentContractError,
  validateSafetyAssessment,
} from '../src/assessment_contract.js';
import {
  AssessmentStorageError,
  persistSafetyAssessment,
} from '../src/assessment_storage.js';

const now = 1_800_000_000_500;

function assessment(overrides = {}) {
  return {
    schemaVersion: '1.0',
    assessmentId: 'event_1',
    eventId: 'event_1',
    helmetId: 'helmet001',
    sourceSchemaVersion: '2.0',
    deviceTimestamp: now - 100,
    sourceServerReceivedAt: now - 50,
    assessedAt: now,
    modelBundleVersion: 'phase-a.1',
    fall: {
      status: 'evaluated',
      probability: 0.1,
      threshold: 0.46,
      modelVersion: 'sisfall-kfall.1',
    },
    gas: {
      status: 'evaluated',
      classification: 'NoGas',
      confidence: 0.9,
      probabilities: { Mixture: 0.02, NoGas: 0.9, Perfume: 0.05, Smoke: 0.03 },
      modelVersion: 'mq7-mq135.1',
      outOfDistribution: false,
    },
    environment: {
      status: 'evaluated',
      temperatureRisk: 'normal',
      humidityRisk: 'normal',
      heatIndexRisk: 'normal',
    },
    overallRisk: 'safe',
    reasonCodes: ['GAS_NO_GAS'],
    recommendationCodes: ['NO_IMMEDIATE_ACTION'],
    ...overrides,
  };
}

function setAt(root, path, value) {
  const parts = path.split('/').filter(Boolean);
  let target = root;
  for (const part of parts.slice(0, -1)) target = target[part] ??= {};
  target[parts.at(-1)] = structuredClone(value);
}

function getAt(root, path) {
  return path.split('/').filter(Boolean).reduce((value, part) => value?.[part], root);
}

class FakeDatabase {
  constructor() {
    this.data = {
      readings: {
        helmet001: {
          event_0: {
            schemaVersion: '2.0', eventId: 'event_0', helmetId: 'helmet001',
            deviceTimestamp: now - 1100, serverReceivedAt: now - 50,
          },
          event_1: {
            schemaVersion: '2.0', eventId: 'event_1', helmetId: 'helmet001',
            deviceTimestamp: now - 100, serverReceivedAt: now - 50,
          },
          event_2: {
            schemaVersion: '2.0', eventId: 'event_2', helmetId: 'helmet001',
            deviceTimestamp: now + 900, serverReceivedAt: now - 50,
          },
        },
      },
    };
  }
  ref(path) {
    const database = this;
    return {
      async get() {
        const value = structuredClone(getAt(database.data, path));
        return { val: () => value };
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

test('validates and freezes the canonical assessment contract', () => {
  const result = validateSafetyAssessment(assessment());
  assert.equal(result.overallRisk, 'safe');
  assert.equal(Object.isFrozen(result), true);
  assert.equal(Object.isFrozen(result.gas), true);
});
test('safe is rejected for unavailable or out-of-distribution inputs', () => {
  for (const value of [
    assessment({ fall: { status: 'unavailable' } }),
    assessment({ gas: { status: 'unavailable' } }),
    assessment({ gas: { ...assessment().gas, outOfDistribution: true } }),
  ]) {
    assert.throws(
      () => validateSafetyAssessment(value),
      (error) => error instanceof AssessmentContractError &&
        error.code === 'UNSAFE_SAFE_CLASSIFICATION',
    );
  }
});

test('rejects invented recommendation text and invalid probability distributions', () => {
  assert.throws(
    () => validateSafetyAssessment({ ...assessment(), recommendationText: 'Do anything' }),
    (error) => error instanceof AssessmentContractError && error.code === 'UNKNOWN_FIELD',
  );
  const value = assessment();
  value.gas.probabilities.NoGas = 0.5;
  assert.throws(
    () => validateSafetyAssessment(value),
    (error) => error instanceof AssessmentContractError && error.field === 'gas.probabilities',
  );
});
test('persistence is idempotent and keeps current assessment order-aware', async () => {
  const database = new FakeDatabase();
  const first = assessment();
  const stored = await persistSafetyAssessment(database, first);
  assert.equal(stored.duplicate, false);
  assert.equal(getAt(database.data, 'helmets/helmet001/currentAssessment/eventId'), 'event_1');

  const duplicate = await persistSafetyAssessment(database, first);
  assert.equal(duplicate.duplicate, true);

  const older = assessment({
    assessmentId: 'event_0',
    eventId: 'event_0',
    deviceTimestamp: first.deviceTimestamp - 1000,
  });
  await persistSafetyAssessment(database, older);
  assert.equal(getAt(database.data, 'helmets/helmet001/currentAssessment/eventId'), 'event_1');

  const newer = assessment({
    assessmentId: 'event_2',
    eventId: 'event_2',
    deviceTimestamp: first.deviceTimestamp + 1000,
  });
  await persistSafetyAssessment(database, newer);
  assert.equal(getAt(database.data, 'helmets/helmet001/currentAssessment/eventId'), 'event_2');
});

test('same event ID with different assessment is rejected', async () => {
  const database = new FakeDatabase();
  await persistSafetyAssessment(database, assessment());
  await assert.rejects(
    persistSafetyAssessment(database, assessment({ overallRisk: 'warning' })),
    (error) => error instanceof AssessmentStorageError &&
      error.code === 'ASSESSMENT_EVENT_CONFLICT',
  );
});

test('persistence rejects missing and mismatched source telemetry', async () => {
  const database = new FakeDatabase();
  const missing = assessment({ assessmentId: 'missing', eventId: 'missing' });
  await assert.rejects(
    persistSafetyAssessment(database, missing),
    (error) => error instanceof AssessmentStorageError &&
      error.code === 'ASSESSMENT_SOURCE_NOT_FOUND',
  );
  await assert.rejects(
    persistSafetyAssessment(database, assessment({ sourceSchemaVersion: '1.0' })),
    (error) => error instanceof AssessmentStorageError &&
      error.code === 'ASSESSMENT_SOURCE_MISMATCH',
  );
});
