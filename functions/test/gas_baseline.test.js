import assert from 'node:assert/strict';
import test from 'node:test';

import {
  GAS_BASELINE_ALPHA,
  GAS_BASELINE_INITIAL_SAMPLES,
  prepareGasAssessmentInput,
} from '../src/gas_baseline.js';

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
  constructor(data = {}) { this.data = structuredClone(data); }

  ref(path) {
    const database = this;
    return {
      async get() {
        const value = structuredClone(getAt(database.data, path));
        return { val: () => value };
      },
      async transaction(update) {
        const current = structuredClone(getAt(database.data, path));
        const next = update(current);
        if (next === undefined) {
          return { committed: false, snapshot: { val: () => current } };
        }
        setAt(database.data, path, next);
        return { committed: true, snapshot: { val: () => structuredClone(next) } };
      },
    };
  }
}

function reading(overrides = {}) {
  return {
    schemaVersion: '2.0', eventId: 'event_1', helmetId: 'helmet001',
    deviceTimestamp: 1_800_000_000_000, serverReceivedAt: 1_800_000_000_100,
    mq7Raw: 2960, mq135Raw: 1072, mq7WarmUp: false, mq135WarmUp: false,
    ...overrides,
  };
}

test('learns the first 12 valid post-warm-up readings', async () => {
  const database = new FakeDatabase();
  let input;
  for (let index = 1; index <= GAS_BASELINE_INITIAL_SAMPLES; index += 1) {
    input = await prepareGasAssessmentInput({
      database,
      reading: reading({
        eventId: `event_${index}`,
        deviceTimestamp: 1000 + index,
        serverReceivedAt: 2000 + index,
      }),
    });
    assert.equal(input.gasInputMode, index < 12 ? 'baselineLearning' : 'baselineMapped');
  }
  assert.equal(getAt(database.data, 'helmets/helmet001/gasBaseline/samples'), 12);
  assert.equal(input.mq7Raw, 610);
  assert.equal(input.mq135Raw, 470);
  assert.equal(input.mq7Ratio, 1);
  assert.equal(input.mq135Ratio, 1);
});

test('uses the 20-minute EMA only for readings within the clean-air ceiling', async () => {
  const baseline = {
    mq7: 2960, mq135: 1072, samples: 12, updatedAt: 1000,
  };
  const database = new FakeDatabase({ helmets: { helmet001: { gasBaseline: baseline } } });
  await prepareGasAssessmentInput({
    database,
    reading: reading({ mq7Raw: 3000, mq135Raw: 1100, serverReceivedAt: 2000 }),
  });
  const updated = getAt(database.data, 'helmets/helmet001/gasBaseline');
  assert.equal(updated.mq7, 2960 + GAS_BASELINE_ALPHA * 40);
  assert.equal(updated.mq135, 1072 + GAS_BASELINE_ALPHA * 28);
  assert.equal(updated.samples, 13);
});

test('freezes the baseline during smoke and sanitiser rises', async () => {
  for (const [mq7Raw, mq135Raw] of [[3611, 1501], [3463, 1522]]) {
    const baseline = { mq7: 2960, mq135: 1072, samples: 12, updatedAt: 1000 };
    const database = new FakeDatabase({ helmets: { helmet001: { gasBaseline: baseline } } });
    const input = await prepareGasAssessmentInput({
      database,
      reading: reading({ mq7Raw, mq135Raw, serverReceivedAt: 2000 }),
    });
    assert.deepEqual(getAt(database.data, 'helmets/helmet001/gasBaseline'), baseline);
    assert.equal(input.gasInputMode, 'baselineMapped');
  }
});

test('does not mutate stored raw readings while creating mapped model inputs', async () => {
  const source = reading();
  const database = new FakeDatabase({
    helmets: { helmet001: { gasBaseline: {
      mq7: 2960, mq135: 1072, samples: 12, updatedAt: 1000,
    } } },
  });
  const mapped = await prepareGasAssessmentInput({ database, reading: source });
  assert.equal(source.mq7Raw, 2960);
  assert.equal(source.mq135Raw, 1072);
  assert.equal(mapped.mq7Raw, 610);
  assert.equal(mapped.mq135Raw, 470);
});

test('counts consecutive warning rises from the current assessment', async () => {
  const database = new FakeDatabase({ helmets: { helmet001: {
    gasBaseline: { mq7: 2960, mq135: 1072, samples: 12, updatedAt: 1000 },
    currentAssessment: {
      eventId: 'event_0', deviceTimestamp: 900, gasInputMode: 'baselineMapped',
      mq7Ratio: 1.13, mq135Ratio: 1.05, gasThresholdConsecutive: 1,
    },
  } } });
  const mapped = await prepareGasAssessmentInput({
    database,
    reading: reading({ eventId: 'event_1', deviceTimestamp: 1000, mq7Raw: 3345 }),
  });
  assert.equal(mapped.gasThresholdConsecutive, 2);
});
