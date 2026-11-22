import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import {
  ALERT_TYPES,
  acknowledgeTransition,
  buildAlertRecord,
  canonicalAlertId,
  resolveTransition,
  safeNotificationPayload,
  registrationTokenHash,
  tokenAssociationUpdates,
  tokenRemovalUpdates,
  userCanAccessAlert,
  viewedTransition,
  validateAlertDecision,
  validateAlertPayload,
} from '../src/alert_logic.js';

const now = 1_800_000_000_000;
const config = {
  gasWarningPpm: 100,
  gasCriticalPpm: 200,
  temperatureWarningC: 40,
  temperatureCriticalC: 50,
  humidityWarningLowPct: 30,
  humidityCriticalLowPct: 20,
  humidityWarningHighPct: 80,
  humidityCriticalHighPct: 90,
  fallImpactThresholdG: 2.5,
};

function payload(overrides = {}) {
  return {
    schemaVersion: '1.0',
    eventId: 'event_123',
    helmetId: 'helmet_A',
    alertType: 'gas',
    severity: 'critical',
    sensorValue: 250,
    threshold: 200,
    unit: 'partsPerMillion',
    evidence: { gasPpm: 250, warmUp: 0 },
    deviceTimestamp: now - 500,
    location: {
      latitude: 31.4629,
      longitude: 74.3181,
      hdop: 1.2,
      capturedAt: now - 700,
      isLastKnown: false,
    },
    ...overrides,
  };
}

function alert(overrides = {}) {
  const validated = validateAlertPayload(payload(), {
    claimedHelmetId: 'helmet_A',
    now,
  });
  return {
    ...buildAlertRecord(validated, {
      siteId: 'site_A',
      assignedWorkerId: 'worker_A',
    }, now),
    deliveredAt: now + 100,
    status: 'delivered',
    ...overrides,
  };
}

describe('alert validation and idempotency', () => {
  test('supports every approved alert type with numeric evidence and units', () => {
    for (const type of ALERT_TYPES) {
      const measured = !['sensor_fault', 'connectivity'].includes(type);
      const input = payload({
        alertType: type,
        ...(measured ? {} : { sensorValue: null, threshold: null, unit: null }),
        ...(type === 'fall' ? {
          severity: 'critical',
          sensorValue: 3.2,
          threshold: 2.5,
          unit: 'standardGravity',
          evidence: {
            freeFallDurationMs: 350,
            impactG: 3.2,
            stillnessDurationMs: 4000,
          },
        } : {}),
      });
      assert.equal(
        validateAlertPayload(input, { claimedHelmetId: 'helmet_A', now }).alertType,
        type,
      );
    }
  });

  test('recomputes deterministic environmental and confirmed-fall decisions', () => {
    const gas = validateAlertPayload(payload(), { claimedHelmetId: 'helmet_A', now });
    assert.equal(validateAlertDecision(gas, config), gas);
    assert.throws(() => validateAlertDecision({ ...gas, severity: 'warning' }, config), /threshold/);

    const fall = validateAlertPayload(payload({
      alertType: 'fall',
      severity: 'critical',
      sensorValue: 3.2,
      threshold: 2.5,
      unit: 'standardGravity',
      evidence: {
        freeFallDurationMs: 350,
        impactG: 3.2,
        stillnessDurationMs: 4000,
      },
    }), { claimedHelmetId: 'helmet_A', now });
    assert.equal(validateAlertDecision(fall, config), fall);
    assert.throws(() => validateAlertPayload(payload({
      alertType: 'fall',
      severity: 'critical',
      sensorValue: 3.2,
      threshold: 2.5,
      unit: 'standardGravity',
      evidence: { impactG: 3.2 },
    }), { claimedHelmetId: 'helmet_A', now }), /freeFallDurationMs/);
  });

  test('duplicate and retry IDs resolve to one canonical alert ID', () => {
    const first = canonicalAlertId('helmet_A', 'event_123');
    const retry = canonicalAlertId('helmet_A', 'event_123');
    assert.equal(first, retry);
    assert.notEqual(first, canonicalAlertId('helmet_A', 'event_124'));
  });

  test('rejects wrong-helmet, invalid GPS, and non-finite evidence', () => {
    assert.throws(() => validateAlertPayload(payload(), {
      claimedHelmetId: 'helmet_B', now,
    }), /not bound/);
    assert.throws(() => validateAlertPayload(payload({
      location: { latitude: 0, longitude: 0, hdop: 1, capturedAt: now, isLastKnown: false },
    }), { claimedHelmetId: 'helmet_A', now }), /0,0/);
    assert.throws(() => validateAlertPayload(payload({ evidence: { gasPpm: Number.NaN } }), {
      claimedHelmetId: 'helmet_A', now,
    }), /finite/);
  });
});

describe('notification privacy and authorization', () => {
  test('lock-screen payload omits exact evidence, GPS, worker, site, and helmet', () => {
    const record = alert();
    const message = safeNotificationPayload(record);
    const serialized = JSON.stringify(message);
    assert.deepEqual(Object.keys(message.data).sort(), ['alertId', 'severity']);
    for (const sensitive of ['31.4629', '74.3181', 'worker_A', 'site_A', 'helmet_A', 'gasPpm']) {
      assert.equal(serialized.includes(sensitive), false);
    }
  });

  test('token creation, refresh ownership, and removal updates are scoped', () => {
    const token = 'fcm-token-value-long-enough';
    const tokenHash = registrationTokenHash(token);
    const associated = tokenAssociationUpdates({
      uid: 'supervisor_B',
      token,
      platform: 'android',
      now,
      existingCreatedAt: now - 100,
      previousOwner: 'supervisor_A',
    });
    assert.equal(associated.tokenHash, tokenHash);
    assert.equal(
      associated.updates[`notificationTokens/supervisor_B/${tokenHash}`].createdAt,
      now - 100,
    );
    assert.equal(associated.updates[`notificationTokens/supervisor_A/${tokenHash}`], null);
    assert.equal(associated.updates[`notificationTokenOwners/${tokenHash}`], 'supervisor_B');

    const removed = tokenRemovalUpdates({
      uid: 'supervisor_B', token, owner: 'supervisor_B',
    });
    assert.equal(removed.updates[`notificationTokens/supervisor_B/${tokenHash}`], null);
    assert.equal(removed.updates[`notificationTokenOwners/${tokenHash}`], null);
  });

  test('workers and supervisors are restricted by worker/site/helmet assignment', () => {
    const record = alert();
    const worker = {
      active: true,
      role: 'worker',
      authorizedHelmetIds: { helmet_A: true },
    };
    const supervisor = {
      active: true,
      role: 'supervisor',
      siteIds: { site_A: true },
      authorizedHelmetIds: { helmet_A: true },
    };
    assert.equal(userCanAccessAlert(worker, record, 'worker_A', 'worker'), true);
    assert.equal(userCanAccessAlert(worker, record, 'worker_B', 'worker'), false);
    assert.equal(userCanAccessAlert(supervisor, record, 'supervisor_A', 'supervisor'), true);
    assert.equal(userCanAccessAlert({ ...supervisor, siteIds: { site_B: true } }, record, 'supervisor_A', 'supervisor'), false);
  });
});

describe('audited lifecycle transitions', () => {
  test('two simultaneous supervisors use first-writer-wins acknowledgement', () => {
    const original = alert();
    const first = acknowledgeTransition(original, 'supervisor_A', now + 200);
    const secondRetry = acknowledgeTransition(first, 'supervisor_B', now + 201);
    assert.equal(secondRetry.acknowledgedBy, 'supervisor_A');
    assert.equal(secondRetry.acknowledgedAt, now + 200);
    assert.equal(secondRetry.viewedBy, 'supervisor_A');
    assert.equal(secondRetry.viewedAt, now + 200);
    assert.deepEqual(secondRetry.evidence, original.evidence);
    assert.equal(original.status, 'delivered');
  });

  test('acknowledgement preserves an earlier seen audit', () => {
    const viewed = viewedTransition(alert(), 'supervisor_A', now + 50);
    const acknowledged = acknowledgeTransition(viewed, 'supervisor_B', now + 100);
    assert.equal(acknowledged.viewedBy, 'supervisor_A');
    assert.equal(acknowledged.viewedAt, now + 50);
  });

  test('resolution backfills seen audit and explains an ongoing temperature hazard', () => {
    const acknowledged = {
      ...alert(),
      alertType: 'temperature',
      threshold: 35,
      status: 'acknowledged',
      acknowledgedBy: 'supervisor_A',
      acknowledgedAt: now,
    };
    assert.throws(
      () => resolveTransition(acknowledged, 'supervisor_A', 'Checked', {
        serverReceivedAt: now + 100,
        severity: 'critical',
        temperatureC: 39,
      }, now + 100),
      /Temperature is still 39 °C; the limit is 35 °C/,
    );
    const resolved = resolveTransition(acknowledged, 'supervisor_A', 'Checked', {
      serverReceivedAt: now + 100,
      severity: 'safe',
      temperatureC: 30,
    }, now + 100);
    assert.equal(resolved.viewedBy, 'supervisor_A');
    assert.equal(resolved.viewedAt, now + 100);
  });

  test('resolution requires acknowledgement and a fresh trusted safe state', () => {
    const acknowledged = acknowledgeTransition(alert(), 'supervisor_A', now + 100);
    const safeCurrent = {
      serverReceivedAt: now + 120,
      severity: 'safe',
      gasWarmUp: false,
      connectivity: 'online',
    };
    const resolved = resolveTransition(
      acknowledged,
      'supervisor_A',
      'Area ventilated and reading verified safe.',
      safeCurrent,
      now + 130,
    );
    assert.equal(resolved.status, 'resolved');
    assert.deepEqual(resolved.evidence, acknowledged.evidence);
    assert.throws(() => resolveTransition(
      acknowledged,
      'supervisor_A',
      'Unsafe retry',
      { ...safeCurrent, severity: 'critical' },
      now + 130,
    ), /does not confirm/);
  });
});
