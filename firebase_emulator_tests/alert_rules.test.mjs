import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  equalTo,
  get,
  limitToLast,
  orderByChild,
  query,
  ref,
  set,
  update,
} from 'firebase/database';

const projectId = 'smart-safety-rules-test';
let environment;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    database: {
      host: '127.0.0.1',
      port: 9000,
      rules: readFileSync('database.rules.json', 'utf8'),
    },
  });
});

beforeEach(async () => {
  await environment.clearDatabase();
  await environment.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), '/'), {
      users: {
        worker1: {
          role: 'worker', active: true,
          authorizedHelmetIds: { helmetA: true },
        },
        supervisor1: {
          role: 'supervisor', active: true,
          siteIds: { siteA: true },
          authorizedHelmetIds: { helmetA: true },
        },
        administrator1: { role: 'administrator', active: true },
      },
      helmets: {
        helmetA: {
          meta: { siteId: 'siteA', assignedWorkerId: 'worker1', active: true },
        },
      },
      alerts: {
        alertA: {
          schemaVersion: '1.0', alertId: 'alertA', eventId: 'eventA',
          helmetId: 'helmetA', siteId: 'siteA', workerId: 'worker1',
          alertType: 'gas', severity: 'critical', sensorValue: 250,
          threshold: 200, unit: 'partsPerMillion', evidence: { gasPpm: 250 },
          deviceTimestamp: 900, serverReceivedAt: 1000, status: 'delivered',
        },
      },
      notificationTokens: {
        supervisor1: {
          hashA: { token: 'restricted-token-value', platform: 'android' },
        },
      },
      notificationTokenOwners: { hashA: 'supervisor1' },
      dedupe: { helmetA: { eventA: { alertId: 'alertA' } } },
    });
  });
});

after(async () => environment?.cleanup());

const verified = (role) => ({ email_verified: true, role });

describe('Phase 4 alert and notification security rules', () => {
  test('authorized users retain scoped alert reads', async () => {
    const worker = environment.authenticatedContext('worker1', verified('worker')).database();
    const supervisor = environment.authenticatedContext('supervisor1', verified('supervisor')).database();
    const bounded = (database) => query(
      ref(database, 'alerts'),
      orderByChild('helmetId'),
      equalTo('helmetA'),
      limitToLast(100),
    );
    await assertSucceeds(get(ref(worker, 'alerts/alertA')));
    await assertSucceeds(get(bounded(supervisor)));
  });

  test('no client role can acknowledge or alter immutable evidence directly', async () => {
    for (const [uid, role] of [
      ['worker1', 'worker'],
      ['supervisor1', 'supervisor'],
      ['administrator1', 'administrator'],
    ]) {
      const database = environment.authenticatedContext(uid, verified(role)).database();
      await assertFails(update(ref(database, 'alerts/alertA'), {
        status: 'acknowledged', acknowledgedBy: uid, acknowledgedAt: 1001,
      }));
      await assertFails(update(ref(database, 'alerts/alertA'), {
        evidence: { gasPpm: 10 },
      }));
    }
  });

  test('notification tokens, owner index, and dedupe records are backend-only', async () => {
    const contexts = [
      environment.unauthenticatedContext().database(),
      environment.authenticatedContext('worker1', verified('worker')).database(),
      environment.authenticatedContext('supervisor1', verified('supervisor')).database(),
      environment.authenticatedContext('administrator1', verified('administrator')).database(),
    ];
    for (const database of contexts) {
      await assertFails(get(ref(database, 'notificationTokens/supervisor1/hashA')));
      await assertFails(get(ref(database, 'notificationTokenOwners/hashA')));
      await assertFails(get(ref(database, 'dedupe/helmetA/eventA')));
      await assertFails(set(ref(database, 'notificationTokens/supervisor1/attacker'), {
        token: 'attacker-token',
      }));
    }
  });
});
