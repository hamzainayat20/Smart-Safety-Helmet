import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  equalTo,
  get as getDatabaseValue,
  limitToLast,
  orderByChild,
  query,
  ref,
  set,
  update,
} from 'firebase/database';
import {
  doc,
  getDoc,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

const projectId = 'smart-safety-rules-test';
let environment;

const verified = (role) => ({ email_verified: true, role });

before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    // Host and port are discovered from the emulator started by
    // `firebase emulators:exec` (firebase.rules-test.json), not hard-coded.
    database: {
      rules: readFileSync('database.rules.json', 'utf8'),
    },
    firestore: {
      rules: readFileSync('firestore.rules', 'utf8'),
    },
  });
});

beforeEach(async () => {
  await environment.clearDatabase();
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), '/'), {
      users: {
        worker1: {
          role: 'worker', active: true,
          authorizedHelmetIds: { helmetA: true },
          authorizedSupervisorIds: { supervisor1: true },
        },
        worker2: {
          role: 'worker', active: true,
          authorizedHelmetIds: { helmetB: true },
          authorizedSupervisorIds: { supervisor2: true },
        },
        supervisor1: {
          role: 'supervisor', active: true,
          siteIds: { siteA: true },
          authorizedHelmetIds: { helmetA: true },
        },
        supervisor2: {
          role: 'supervisor', active: true,
          siteIds: { siteB: true },
          authorizedHelmetIds: { helmetB: true },
        },
        administrator1: { role: 'administrator', active: true },
        disabled1: {
          role: 'worker', active: false,
          authorizedHelmetIds: { helmetA: true },
        },
      },
      sites: {
        siteA: { name: 'A', supervisors: { supervisor1: true } },
        siteB: { name: 'B', supervisors: { supervisor2: true } },
      },
      helmets: {
        helmetA: {
          meta: { siteId: 'siteA', assignedWorkerId: 'worker1', active: true },
          current: { helmetId: 'helmetA', serverReceivedAt: 1000 },
          currentAssessment: {
            assessmentId: 'eventA', eventId: 'eventA', helmetId: 'helmetA',
            deviceTimestamp: 900, assessedAt: 1100, overallRisk: 'safe',
          },
        },
        helmetB: {
          meta: { siteId: 'siteB', assignedWorkerId: 'worker2', active: true },
          current: { helmetId: 'helmetB', serverReceivedAt: 1000 },
          currentAssessment: {
            assessmentId: 'eventB', eventId: 'eventB', helmetId: 'helmetB',
            deviceTimestamp: 900, assessedAt: 1100, overallRisk: 'warning',
          },
        },
      },
      readings: {
        helmetA: {
          eventA: { eventId: 'eventA', helmetId: 'helmetA', serverReceivedAt: 1000 },
        },
        helmetB: {
          eventB: { eventId: 'eventB', helmetId: 'helmetB', serverReceivedAt: 1000 },
        },
      },
      assessments: {
        helmetA: {
          eventA: {
            assessmentId: 'eventA', eventId: 'eventA', helmetId: 'helmetA',
            deviceTimestamp: 900, assessedAt: 1100, overallRisk: 'safe',
          },
        },
        helmetB: {
          eventB: {
            assessmentId: 'eventB', eventId: 'eventB', helmetId: 'helmetB',
            deviceTimestamp: 900, assessedAt: 1100, overallRisk: 'warning',
          },
        },
      },
      alerts: {
        alertA: {
          schemaVersion: '1.0', alertId: 'alertA', eventId: 'alertEventA',
          siteId: 'siteA', helmetId: 'helmetA', workerId: 'worker1',
          alertType: 'gas', severity: 'critical', sensorValue: 250,
          threshold: 200, unit: 'partsPerMillion', evidence: { gasPpm: 250 },
          deviceTimestamp: 900, serverReceivedAt: 1000, status: 'delivered',
        },
        alertB: {
          schemaVersion: '1.0', alertId: 'alertB', eventId: 'alertEventB',
          siteId: 'siteB', helmetId: 'helmetB', workerId: 'worker2',
          alertType: 'temperature', severity: 'warning', sensorValue: 42,
          threshold: 40, unit: 'degreesCelsius', evidence: { temperatureC: 42 },
          deviceTimestamp: 900, serverReceivedAt: 1000, status: 'delivered',
        },
      },
      config: {
        defaults: { schemaVersion: '1.0', configVersion: 'default-1' },
        helmets: {
          helmetA: { helmetId: 'helmetA', configVersion: 'a-1' },
          helmetB: { helmetId: 'helmetB', configVersion: 'b-1' },
        },
      },
    });

    const firestore = context.firestore();
    for (const [uid, data] of Object.entries({
      worker1: {
        uid: 'worker1', email: 'worker1@example.com', role: 'worker', active: true,
        authorizedSupervisorIds: ['supervisor1'], siteIds: [],
        authorizedHelmetIds: ['helmetA'], name: 'Worker One', updatedAt: 1,
      },
      worker2: {
        uid: 'worker2', email: 'worker2@example.com', role: 'worker', active: true,
        authorizedSupervisorIds: ['supervisor2'], siteIds: [],
        authorizedHelmetIds: ['helmetB'], name: 'Worker Two', updatedAt: 1,
      },
      supervisor1: {
        uid: 'supervisor1', email: 'supervisor1@example.com', role: 'supervisor', active: true,
        authorizedSupervisorIds: [], siteIds: ['siteA'],
        authorizedHelmetIds: ['helmetA'], name: 'Supervisor One', updatedAt: 1,
      },
      administrator1: {
        uid: 'administrator1', email: 'admin@example.com', role: 'administrator', active: true,
        authorizedSupervisorIds: [], siteIds: [], authorizedHelmetIds: [],
        name: 'Admin', updatedAt: 1,
      },
      disabled1: {
        uid: 'disabled1', email: 'disabled@example.com', role: 'worker', active: false,
        authorizedSupervisorIds: [], siteIds: [], authorizedHelmetIds: ['helmetA'],
        name: 'Disabled', updatedAt: 1,
      },
    })) {
      await setDoc(doc(firestore, 'users', uid), data);
    }
  });
});

after(async () => environment?.cleanup());

describe('Realtime Database authorization', () => {
  test('anonymous users are denied while trusted unverified users retain scoped access', async () => {
    await assertFails(getDatabaseValue(ref(environment.unauthenticatedContext().database(), 'helmets/helmetA/meta')));
    const unverified = environment.authenticatedContext('worker1', {
      email_verified: false, role: 'worker',
    }).database();
    await assertSucceeds(getDatabaseValue(ref(unverified, 'users/worker1')));
    await assertSucceeds(getDatabaseValue(ref(unverified, 'helmets/helmetA/current')));
    await assertFails(getDatabaseValue(ref(unverified, 'helmets/helmetB/current')));
  });

  test('worker reads only own profile, assigned helmet, readings, and alerts', async () => {
    const database = environment.authenticatedContext('worker1', verified('worker')).database();
    await assertSucceeds(getDatabaseValue(ref(database, 'users/worker1')));
    await assertFails(getDatabaseValue(ref(database, 'users/worker2')));
    await assertSucceeds(getDatabaseValue(ref(database, 'helmets/helmetA/meta')));
    await assertSucceeds(getDatabaseValue(ref(database, 'helmets/helmetA/current')));
    await assertSucceeds(getDatabaseValue(ref(database, 'helmets/helmetA/currentAssessment')));
    await assertFails(getDatabaseValue(ref(database, 'helmets/helmetB/meta')));
    await assertFails(getDatabaseValue(ref(database, 'helmets/helmetB/current')));
    await assertFails(getDatabaseValue(ref(database, 'helmets/helmetB/currentAssessment')));
    await assertSucceeds(getDatabaseValue(ref(database, 'readings/helmetA')));
    await assertSucceeds(getDatabaseValue(ref(database, 'assessments/helmetA')));
    await assertFails(getDatabaseValue(ref(database, 'assessments/helmetB')));
    await assertSucceeds(getDatabaseValue(ref(database, 'alerts/alertA')));
    await assertFails(getDatabaseValue(ref(database, 'alerts/alertB')));
    await assertSucceeds(getDatabaseValue(ref(database, 'config/helmets/helmetA')));
    await assertFails(getDatabaseValue(ref(database, 'config/helmets/helmetB')));
  });

  test('supervisor reads only assigned sites, helmets, and workers', async () => {
    const database = environment.authenticatedContext('supervisor1', verified('supervisor')).database();
    await assertSucceeds(getDatabaseValue(ref(database, 'sites/siteA')));
    await assertFails(getDatabaseValue(ref(database, 'sites/siteB')));
    await assertSucceeds(getDatabaseValue(ref(database, 'helmets/helmetA/meta')));
    await assertSucceeds(getDatabaseValue(ref(database, 'helmets/helmetA/currentAssessment')));
    await assertSucceeds(getDatabaseValue(ref(database, 'assessments/helmetA')));
    await assertFails(getDatabaseValue(ref(database, 'helmets/helmetB/meta')));
    await assertFails(getDatabaseValue(ref(database, 'helmets/helmetB/currentAssessment')));
    await assertFails(getDatabaseValue(ref(database, 'assessments/helmetB')));
    await assertSucceeds(getDatabaseValue(ref(database, 'users/worker1')));
    await assertFails(getDatabaseValue(ref(database, 'users/worker2')));
  });

  test('administrator reads all scoped records but clients cannot mutate them', async () => {
    const database = environment.authenticatedContext('administrator1', verified('administrator')).database();
    await assertSucceeds(getDatabaseValue(ref(database, 'sites/siteB')));
    await assertSucceeds(getDatabaseValue(ref(database, 'helmets/helmetB/current')));
    await assertSucceeds(getDatabaseValue(ref(database, 'helmets/helmetB/currentAssessment')));
    await assertSucceeds(getDatabaseValue(ref(database, 'assessments/helmetB')));
    await assertSucceeds(getDatabaseValue(ref(database, 'users/worker2')));
    await assertFails(set(ref(database, 'users/worker2/role'), 'administrator'));
  });

  test('disabled principal is denied even with a valid role claim', async () => {
    const database = environment.authenticatedContext('disabled1', verified('worker')).database();
    await assertFails(getDatabaseValue(ref(database, 'users/disabled1')));
    await assertFails(getDatabaseValue(ref(database, 'helmets/helmetA/current')));
  });

  test('alert queries must be helmet-scoped and bounded', async () => {
    const workerClaims = verified('worker');
    const supervisorClaims = verified('supervisor');
    const alertQuery = (database, helmetId) => query(
      ref(database, 'alerts'),
      orderByChild('helmetId'),
      equalTo(helmetId),
      limitToLast(100),
    );
    const worker = environment.authenticatedContext('worker1', workerClaims).database();
    await assertSucceeds(getDatabaseValue(alertQuery(worker, 'helmetA')));
    await assertFails(getDatabaseValue(alertQuery(worker, 'helmetB')));
    await assertFails(getDatabaseValue(ref(worker, 'alerts')));
    const supervisor = environment.authenticatedContext('supervisor1', supervisorClaims).database();
    await assertSucceeds(getDatabaseValue(alertQuery(supervisor, 'helmetA')));
    await assertFails(getDatabaseValue(alertQuery(supervisor, 'helmetB')));
  });

  test('alert lifecycle and evidence are server-only writes', async () => {
    const database = environment.authenticatedContext('supervisor1', verified('supervisor')).database();
    await assertFails(update(ref(database, 'alerts/alertA'), {
      status: 'acknowledged', acknowledgedBy: 'supervisor1', acknowledgedAt: 1001,
    }));
    await assertFails(update(ref(database, 'alerts/alertA'), { sensorValue: 10 }));
  });

  test('assessment history and current projections are backend-only writes', async () => {
    for (const [uid, claims] of [
      ['worker1', verified('worker')],
      ['supervisor1', verified('supervisor')],
      ['administrator1', verified('administrator')],
    ]) {
      const database = environment.authenticatedContext(uid, claims).database();
      await assertFails(set(ref(database, 'assessments/helmetA/eventX'), {
        assessmentId: 'eventX', eventId: 'eventX', helmetId: 'helmetA',
      }));
      await assertFails(update(ref(database, 'helmets/helmetA/currentAssessment'), {
        overallRisk: 'safe',
      }));
      await assertFails(getDatabaseValue(ref(database, 'assessmentJobs/helmetA/eventX')));
      await assertFails(set(ref(database, 'assessmentJobs/helmetA/eventX'), {
        status: 'completed',
      }));
    }
  });

  test('FCM tokens and dedupe markers are inaccessible to every client role', async () => {
    const supervisor = environment.authenticatedContext('supervisor1', verified('supervisor')).database();
    const administrator = environment.authenticatedContext('administrator1', verified('administrator')).database();
    await assertFails(getDatabaseValue(ref(supervisor, 'notificationTokens/supervisor1')));
    await assertFails(set(ref(supervisor, 'notificationTokens/supervisor1/fake'), { token: 'secret' }));
    await assertFails(getDatabaseValue(ref(administrator, 'notificationTokens/supervisor1')));
    await assertFails(getDatabaseValue(ref(supervisor, 'notificationTokenOwners/fake')));
    await assertFails(set(ref(administrator, 'dedupe/helmetA/eventA'), true));
  });

  test('Realtime Database signup cannot create a privileged role', async () => {
    const valid = {
      schemaVersion: '1.0', uid: 'newWorker', name: 'New Worker',
      email: 'new@example.com', role: 'worker', active: true,
      pushAlertsEnabled: true, criticalAlertsOnly: false,
      vibrationEnabled: true, updatedAt: 1,
    };
    const database = environment.authenticatedContext('newWorker', {
      email_verified: false, email: 'new@example.com',
    }).database();
    await assertSucceeds(set(ref(database, 'users/newWorker'), valid));
    await assertFails(set(ref(database, 'users/newWorker'), {
      ...valid, role: 'supervisor',
    }));
  });
});

describe('Legacy Firestore profile authorization', () => {
  test('trusted unverified worker can read only their own active profile', async () => {
    const firestore = environment.authenticatedContext('worker1', {
      email_verified: false, role: 'worker', email: 'worker1@example.com',
    }).firestore();
    await assertSucceeds(getDoc(doc(firestore, 'users', 'worker1')));
    await assertFails(getDoc(doc(firestore, 'users', 'worker2')));
  });

  test('worker cannot read another profile or elevate protected fields', async () => {
    const firestore = environment.authenticatedContext('worker1', {
      ...verified('worker'), email: 'worker1@example.com',
    }).firestore();
    await assertSucceeds(getDoc(doc(firestore, 'users', 'worker1')));
    await assertFails(getDoc(doc(firestore, 'users', 'worker2')));
    await assertFails(updateDoc(doc(firestore, 'users', 'worker1'), { role: 'administrator' }));
  });

  test('supervisor and administrator reads follow trusted assignments', async () => {
    const supervisor = environment.authenticatedContext('supervisor1', verified('supervisor')).firestore();
    await assertSucceeds(getDoc(doc(supervisor, 'users', 'worker1')));
    await assertFails(getDoc(doc(supervisor, 'users', 'worker2')));
    const administrator = environment.authenticatedContext('administrator1', verified('administrator')).firestore();
    await assertSucceeds(getDoc(doc(administrator, 'users', 'worker2')));
  });

  test('disabled and anonymous principals cannot read profiles', async () => {
    const disabled = environment.authenticatedContext('disabled1', verified('worker')).firestore();
    await assertFails(getDoc(doc(disabled, 'users', 'disabled1')));
    await assertFails(getDoc(doc(environment.unauthenticatedContext().firestore(), 'users', 'worker1')));
  });

  test('controlled signup can create only a worker with empty assignments', async () => {
    const firestore = environment.authenticatedContext('newWorker', {
      email_verified: false, email: 'new@example.com',
    }).firestore();
    const valid = {
      schemaVersion: 1, uid: 'newWorker', name: 'New Worker',
      email: 'new@example.com', organization: null, role: 'worker', active: true,
      siteIds: [], authorizedHelmetIds: [], pushAlertsEnabled: true,
      criticalAlertsOnly: false, vibrationEnabled: true,
      createdAt: 1, updatedAt: 1,
    };
    await assertSucceeds(setDoc(doc(firestore, 'users', 'newWorker'), valid));
    await assertFails(setDoc(doc(firestore, 'users', 'attacker'), {
      ...valid, uid: 'attacker', role: 'supervisor',
    }));
  });
});

test('security fixtures are valid', () => assert.ok(environment));
