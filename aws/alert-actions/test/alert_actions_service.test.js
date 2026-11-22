import assert from 'node:assert/strict';
import test from 'node:test';

import { createAlertActionsHandler } from '../alert_actions_service.js';

const now = 1775900000000;

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
  }

  ref(path = '') {
    const database = this;
    return {
      async get() {
        const value = structuredClone(getAt(database.data, path) ?? null);
        return { val: () => value };
      },
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
  }
}

function data() {
  return {
    users: {
      supervisor1: {
        active: true,
        role: 'supervisor',
        siteIds: { site1: true },
        authorizedHelmetIds: { helmet1: true },
      },
      supervisor2: {
        active: true,
        role: 'supervisor',
        siteIds: { site2: true },
        authorizedHelmetIds: { helmet2: true },
      },
      worker1: {
        active: true,
        role: 'worker',
        authorizedHelmetIds: { helmet1: true },
      },
    },
    alerts: {
      alert1: {
        schemaVersion: '1.0',
        alertId: 'alert1',
        helmetId: 'helmet1',
        siteId: 'site1',
        workerId: 'worker1',
        alertType: 'fall',
        severity: 'critical',
        status: 'created',
      },
    },
    helmets: {
      helmet1: {
        current: {
          serverReceivedAt: now,
          severity: 'safe',
          fallState: 'normal',
        },
      },
    },
  };
}

function dependencies(database = new FakeDatabase(data())) {
  return {
    database,
    auth: {
      async verifyIdToken(token, checkRevoked) {
        assert.equal(checkRevoked, true);
        if (token === 'supervisor-token') return { uid: 'supervisor1', role: 'supervisor' };
        if (token === 'unauthorized-token') return { uid: 'supervisor2', role: 'supervisor' };
        if (token === 'worker-token') return { uid: 'worker1' };
        throw new Error('invalid');
      },
    },
    messaging: { async sendEachForMulticast() { throw new Error('not used'); } },
    clock: () => now,
  };
}

function request(path, token, body = { alertId: 'alert1' }) {
  return {
    rawPath: path,
    requestContext: { http: { method: 'POST' } },
    headers: token ? { authorization: `Bearer ${token}` } : {},
    body: JSON.stringify(body),
  };
}

test('authorized supervisor acknowledges an alert', async () => {
  const deps = dependencies();
  const response = await createAlertActionsHandler(deps)(
    request('/v1/alerts/acknowledge', 'supervisor-token'),
  );
  assert.equal(response.statusCode, 200);
  const alert = JSON.parse(response.body).alert;
  assert.equal(alert.status, 'acknowledged');
  assert.equal(alert.acknowledgedBy, 'supervisor1');
  assert.equal(alert.acknowledgedAt, now);
});

test('worker cannot acknowledge an alert', async () => {
  const response = await createAlertActionsHandler(dependencies())(
    request('/v1/alerts/acknowledge', 'worker-token'),
  );
  assert.equal(response.statusCode, 403);
  assert.equal(JSON.parse(response.body).error.code, 'permission-denied');
});

test('unauthorized supervisor cannot acknowledge an alert', async () => {
  const response = await createAlertActionsHandler(dependencies())(
    request('/v1/alerts/acknowledge', 'unauthorized-token'),
  );
  assert.equal(response.statusCode, 403);
  assert.equal(JSON.parse(response.body).error.code, 'permission-denied');
});

test('missing or invalid Firebase token returns 401', async () => {
  const handler = createAlertActionsHandler(dependencies());
  assert.equal((await handler(request('/v1/alerts/acknowledge'))).statusCode, 401);
  assert.equal(
    (await handler(request('/v1/alerts/acknowledge', 'invalid-token'))).statusCode,
    401,
  );
});

test('resolve before acknowledge returns failed-precondition', async () => {
  const response = await createAlertActionsHandler(dependencies())(
    request('/v1/alerts/resolve', 'supervisor-token', {
      alertId: 'alert1',
      resolutionNote: 'Area inspected and safe.',
    }),
  );
  assert.equal(response.statusCode, 409);
  assert.equal(JSON.parse(response.body).error.code, 'failed-precondition');
});

test('routes on the deployed named stage (rawPath includes /staging)', async () => {
  const handle = createAlertActionsHandler(dependencies());
  const staged = {
    routeKey: 'POST /v1/alerts/acknowledge',
    rawPath: '/staging/v1/alerts/acknowledge',
    requestContext: { stage: 'staging', http: { method: 'POST' } },
    headers: { authorization: 'Bearer supervisor-token' },
    body: JSON.stringify({ alertId: 'alert1' }),
  };
  const response = await handle(staged);
  assert.equal(response.statusCode, 200, response.body);
  assert.equal(JSON.parse(response.body).alert.status, 'acknowledged');

  const noRouteKey = { ...staged };
  delete noRouteKey.routeKey;
  const fallback = await createAlertActionsHandler(dependencies())(noRouteKey);
  assert.equal(fallback.statusCode, 200, fallback.body);
});

test('resolves with schema 2.0 telemetry when the current assessment is safe', async () => {
  const fixture = data();
  fixture.alerts.alert1.status = 'acknowledged';
  fixture.helmets.helmet1.current = {
    schemaVersion: '2.0', eventId: 'e9', serverReceivedAt: now - 5000,
    temperatureC: 26, mq7WarmUp: false, mq135WarmUp: false,
  };
  fixture.helmets.helmet1.currentAssessment = {
    eventId: 'e9', sourceServerReceivedAt: now - 5000, overallRisk: 'safe',
  };
  const response = await createAlertActionsHandler(dependencies(new FakeDatabase(fixture)))(
    request('/v1/alerts/resolve', 'supervisor-token', {
      alertId: 'alert1', resolutionNote: 'Worker checked and safe',
    }),
  );
  assert.equal(response.statusCode, 200, response.body);
  assert.equal(JSON.parse(response.body).alert.status, 'resolved');
});

test('resolve returns a readable 409 while the schema 2.0 assessment is not safe', async () => {
  const fixture = data();
  fixture.alerts.alert1.status = 'acknowledged';
  fixture.helmets.helmet1.current = {
    schemaVersion: '2.0', eventId: 'e9', serverReceivedAt: now - 5000,
  };
  fixture.helmets.helmet1.currentAssessment = {
    eventId: 'e9', sourceServerReceivedAt: now - 5000, overallRisk: 'critical',
  };
  const response = await createAlertActionsHandler(dependencies(new FakeDatabase(fixture)))(
    request('/v1/alerts/resolve', 'supervisor-token', {
      alertId: 'alert1', resolutionNote: 'Trying too early',
    }),
  );
  assert.equal(response.statusCode, 409, response.body);
  assert.equal(JSON.parse(response.body).error.code, 'failed-precondition');
});
