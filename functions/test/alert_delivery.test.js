import assert from 'node:assert/strict';
import test from 'node:test';

import { createAlertDelivery } from '../src/alert_delivery.js';

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
  constructor(data) {
    this.data = structuredClone(data);
    this.deliveryUpdates = [];
  }

  ref(path = '') {
    const database = this;
    return {
      async get() {
        const value = structuredClone(getAt(database.data, path) ?? null);
        return { val: () => value };
      },
      async update(updates) {
        if (path.endsWith('/notificationDelivery')) {
          database.deliveryUpdates.push(structuredClone(updates));
        }
        for (const [childPath, value] of Object.entries(updates)) {
          setAt(database.data, path ? `${path}/${childPath}` : childPath, value);
        }
      },
      async transaction(update) {
        const current = structuredClone(getAt(database.data, path) ?? null);
        const next = update(current);
        setAt(database.data, path, next);
        return { committed: true, snapshot: { val: () => structuredClone(next) } };
      },
    };
  }
}

const alert = {
  alertId: 'alert1',
  helmetId: 'helmet1',
  siteId: 'site1',
  severity: 'critical',
  status: 'created',
};

test('delivery audit records active send then no authorized device', async () => {
  const database = new FakeDatabase({
    alerts: { alert1: alert },
    sites: { site1: { supervisors: { supervisor1: true } } },
    users: {
      supervisor1: {
        active: true,
        role: 'supervisor',
        siteIds: { site1: true },
        authorizedHelmetIds: { helmet1: true },
      },
    },
  });
  let messagingCalled = false;
  const deliver = createAlertDelivery({
    database,
    messaging: {
      async sendEachForMulticast() {
        messagingCalled = true;
        return { successCount: 0, failureCount: 0, responses: [] };
      },
    },
    clock: () => 1000,
  });

  await deliver(alert);

  assert.equal(messagingCalled, false);
  assert.equal(database.deliveryUpdates[0].inProgress, true);
  assert.deepEqual(database.deliveryUpdates.at(-1), {
    successCount: 0,
    failureCount: 0,
    lastErrorCode: 'NO_AUTHORIZED_TOKENS',
    inProgress: false,
    lastAttemptAt: 1000,
  });
});

test('delivery failure clears active send and records failure', async () => {
  const database = new FakeDatabase({
    alerts: { alert1: alert },
    sites: { site1: { supervisors: { supervisor1: true } } },
    users: {
      supervisor1: {
        active: true,
        role: 'supervisor',
        siteIds: { site1: true },
        authorizedHelmetIds: { helmet1: true },
      },
    },
    notificationTokens: {
      supervisor1: { token1: { token: 'registered-token' } },
    },
  });
  const deliver = createAlertDelivery({
    database,
    messaging: {
      async sendEachForMulticast() {
        const error = new Error('unavailable');
        error.code = 'messaging/internal-error';
        throw error;
      },
    },
    clock: () => 1000,
  });

  await deliver(alert);

  assert.equal(database.deliveryUpdates[0].inProgress, true);
  assert.deepEqual(database.deliveryUpdates.at(-1), {
    successCount: 0,
    failureCount: 1,
    lastErrorCode: 'messaging/internal-error',
    inProgress: false,
    lastAttemptAt: 1000,
  });
});
