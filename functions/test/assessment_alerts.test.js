import assert from 'node:assert/strict';
import test from 'node:test';

import { canonicalAlertId } from '../src/alert_logic.js';
import {
  ASSESSMENT_ALERT_COOLDOWN_MS,
  alertCandidateFromAssessment,
  createAlertFromAssessment,
} from '../src/assessment_alerts.js';

const now = 1_800_000_000_500;

function reading(overrides = {}) {
  return {
    schemaVersion: '2.0', eventId: 'event_1', helmetId: 'helmet001',
    deviceTimestamp: now - 100, serverReceivedAt: now - 50,
    temperatureC: 30.6, humidityPct: 41.4, heatIndexC: 30.6,
    ...overrides,
  };
}

function assessment(overrides = {}) {
  return {
    schemaVersion: '1.0', assessmentId: 'event_1', eventId: 'event_1',
    helmetId: 'helmet001', sourceSchemaVersion: '2.0',
    fall: { status: 'evaluated', probability: 0.00003, threshold: 0.46, modelVersion: '2.0' },
    gas: { status: 'unavailable' },
    environment: {
      status: 'evaluated', temperatureRisk: 'normal',
      humidityRisk: 'normal', heatIndexRisk: 'normal',
    },
    overallRisk: 'unknown',
    reasonCodes: ['GAS_MODEL_UNAVAILABLE', 'SENSOR_FAULT'],
    recommendationCodes: ['VERIFY_SENSORS'],
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
  if (value === null || value === undefined) delete target[parts.at(-1)];
  else target[parts.at(-1)] = structuredClone(value);
}

class FakeDatabase {
  constructor(meta = { siteId: 'site-main', assignedWorkerId: 'workerUid1', active: true }) {
    this.data = { helmets: { helmet001: { meta } } };
    this.failAlertWrites = false;
  }
  ref(path) {
    const database = this;
    return {
      async get() {
        const value = structuredClone(getAt(database.data, path) ?? null);
        return { val: () => value };
      },
      async set(value) { setAt(database.data, path, value); },
      async transaction(update) {
        if (database.failAlertWrites && path.startsWith('alerts/')) {
          throw new Error('write failed');
        }
        const current = structuredClone(getAt(database.data, path) ?? null);
        const next = update(current);
        if (next === undefined) {
          return { committed: false, snapshot: { val: () => current } };
        }
        setAt(database.data, path, next);
        return { committed: true, snapshot: { val: () => structuredClone(next) } };
      },
    };
  }
  alerts() { return Object.values(this.data.alerts ?? {}); }
}

const temperatureWarning = () => assessment({
  environment: {
    status: 'evaluated', temperatureRisk: 'warning',
    humidityRisk: 'normal', heatIndexRisk: 'normal',
  },
  overallRisk: 'warning',
  reasonCodes: ['GAS_MODEL_UNAVAILABLE', 'SENSOR_FAULT', 'TEMPERATURE_WARNING'],
});

test('no alert for unknown, safe, or partial-check assessments', async () => {
  for (const overallRisk of ['unknown', 'safe']) {
    const database = new FakeDatabase();
    const result = await createAlertFromAssessment({
      database, assessment: assessment({ overallRisk }), reading: reading(), clock: () => now,
    });
    assert.equal(result.status, 'none');
    assert.deepEqual(database.alerts(), []);
  }
});

test('a temperature warning creates one app-compatible alert record', async () => {
  const database = new FakeDatabase();
  const source = reading({ temperatureC: 37.2, heatIndexC: 36.4 });
  const result = await createAlertFromAssessment({
    database, assessment: temperatureWarning(), reading: source, clock: () => now,
  });
  assert.equal(result.status, 'created');
  const [alert] = database.alerts();
  assert.deepEqual(alert, {
    schemaVersion: '1.0',
    alertId: canonicalAlertId('helmet001', 'event_1'),
    eventId: 'event_1',
    helmetId: 'helmet001',
    siteId: 'site-main',
    workerId: 'workerUid1',
    alertType: 'temperature',
    severity: 'warning',
    sensorValue: 37.2,
    unit: 'degreesCelsius',
    evidence: {
      temperatureC: 37.2, humidityPct: 41.4, heatIndexC: 36.4,
      fallProbability: 0.00003, fallThreshold: 0.46,
    },
    deviceTimestamp: now - 100,
    serverReceivedAt: now,
    status: 'created',
  });
  // No threshold is invented and no notification bookkeeping is written.
  assert.equal('threshold' in alert, false);
  assert.equal('notificationDelivery' in alert, false);
});

test('a detected fall is a critical fall alert without a fabricated measurement', async () => {
  const database = new FakeDatabase();
  await createAlertFromAssessment({
    database,
    assessment: assessment({
      fall: { status: 'evaluated', probability: 0.91, threshold: 0.46, modelVersion: '2.0' },
      overallRisk: 'critical',
      reasonCodes: ['FALL_DETECTED', 'GAS_MODEL_UNAVAILABLE'],
    }),
    reading: reading(),
    clock: () => now,
  });
  const [alert] = database.alerts();
  assert.equal(alert.alertType, 'fall');
  assert.equal(alert.severity, 'critical');
  assert.equal('sensorValue' in alert, false);
  assert.equal('unit' in alert, false);
  assert.equal(alert.evidence.fallProbability, 0.91);
});

test('the most severe hazard is chosen and fall wins ties', () => {
  const candidate = alertCandidateFromAssessment(assessment({
    fall: { status: 'evaluated', probability: 0.91, threshold: 0.46, modelVersion: '2.0' },
    environment: {
      status: 'evaluated', temperatureRisk: 'critical',
      humidityRisk: 'normal', heatIndexRisk: 'normal',
    },
    overallRisk: 'critical',
    reasonCodes: ['FALL_DETECTED', 'TEMPERATURE_CRITICAL'],
  }), reading({ temperatureC: 43.7 }));
  assert.equal(candidate.alertType, 'fall');

  const heat = alertCandidateFromAssessment(assessment({
    environment: {
      status: 'evaluated', temperatureRisk: 'warning',
      humidityRisk: 'normal', heatIndexRisk: 'critical',
    },
    overallRisk: 'critical',
    reasonCodes: ['TEMPERATURE_WARNING', 'HEAT_INDEX_CRITICAL'],
  }), reading({ temperatureC: 39, heatIndexC: 55 }));
  assert.deepEqual(
    { type: heat.alertType, severity: heat.severity, value: heat.sensorValue },
    { type: 'temperature', severity: 'critical', value: 55 },
  );
});

test('gas alerts never carry ppm and need a confident in-range classification', () => {
  const smoke = (confidence, extraReasons = []) => assessment({
    gas: {
      status: 'evaluated', classification: 'Smoke', confidence,
      probabilities: {}, modelVersion: '1.0', outOfDistribution: false,
    },
    overallRisk: 'critical',
    reasonCodes: ['GAS_SMOKE', ...extraReasons],
  });
  const candidate = alertCandidateFromAssessment(smoke(0.9), reading());
  assert.equal(candidate.alertType, 'gas');
  assert.equal(candidate.severity, 'critical');
  assert.equal(candidate.unit, undefined);
  assert.equal(candidate.sensorValue, undefined);
  assert.equal(
    alertCandidateFromAssessment(smoke(0.5, ['GAS_MODEL_UNAVAILABLE']), reading()),
    null,
  );
});

test('repeated readings of the same hazard are suppressed during the cooldown', async () => {
  const database = new FakeDatabase();
  let time = now;
  const run = (eventId) => createAlertFromAssessment({
    database, assessment: temperatureWarning(),
    reading: reading({ eventId, temperatureC: 37 }), clock: () => time,
  });
  assert.equal((await run('event_1')).status, 'created');
  time += 5_000;
  assert.equal((await run('event_2')).status, 'suppressed');
  time += ASSESSMENT_ALERT_COOLDOWN_MS;
  assert.equal((await run('event_3')).status, 'created');
  assert.equal(database.alerts().length, 2);
});

test('escalation from warning to critical is alerted immediately', async () => {
  const database = new FakeDatabase();
  await createAlertFromAssessment({
    database, assessment: temperatureWarning(), reading: reading({ temperatureC: 37 }),
    clock: () => now,
  });
  const result = await createAlertFromAssessment({
    database,
    assessment: assessment({
      environment: {
        status: 'evaluated', temperatureRisk: 'critical',
        humidityRisk: 'normal', heatIndexRisk: 'normal',
      },
      overallRisk: 'critical',
      reasonCodes: ['TEMPERATURE_CRITICAL'],
    }),
    reading: reading({ eventId: 'event_2', temperatureC: 43.7 }),
    clock: () => now + 5_000,
  });
  assert.equal(result.status, 'created');
  assert.deepEqual(database.alerts().map((a) => a.severity).sort(), ['critical', 'warning']);
});

test('the same event never creates a duplicate alert', async () => {
  const database = new FakeDatabase();
  const run = (time) => createAlertFromAssessment({
    database, assessment: temperatureWarning(), reading: reading(), clock: () => time,
  });
  await run(now);
  const second = await run(now + ASSESSMENT_ALERT_COOLDOWN_MS + 1);
  assert.equal(second.status, 'exists');
  assert.equal(database.alerts().length, 1);
});

test('helmets without a known site are skipped and an unassigned worker is omitted', async () => {
  const noSite = new FakeDatabase({ active: true });
  assert.equal((await createAlertFromAssessment({
    database: noSite, assessment: temperatureWarning(), reading: reading(), clock: () => now,
  })).reason, 'HELMET_SITE_UNKNOWN');
  assert.deepEqual(noSite.alerts(), []);

  const unassigned = new FakeDatabase({ siteId: 'site-main', active: true });
  await createAlertFromAssessment({
    database: unassigned, assessment: temperatureWarning(), reading: reading(), clock: () => now,
  });
  assert.equal('workerId' in unassigned.alerts()[0], false);
});

test('a failed alert write restores the cooldown so the next reading retries', async () => {
  const database = new FakeDatabase();
  database.failAlertWrites = true;
  await assert.rejects(createAlertFromAssessment({
    database, assessment: temperatureWarning(), reading: reading(), clock: () => now,
  }));
  database.failAlertWrites = false;
  const retry = await createAlertFromAssessment({
    database, assessment: temperatureWarning(),
    reading: reading({ eventId: 'event_2' }), clock: () => now + 5_000,
  });
  assert.equal(retry.status, 'created');
});
