import assert from 'node:assert/strict';
import test from 'node:test';

import {
  compareTelemetryOrder,
  expiredIngestionChildKeys,
  incomingShouldReplaceCurrent,
} from '../src/ingestion_state.js';

test('reading order uses device timestamp then ASCII event ID', () => {
  const base = { deviceTimestamp: 1000, eventId: 'event_B' };
  assert.equal(compareTelemetryOrder(base, { ...base, deviceTimestamp: 999 }), 1);
  assert.equal(compareTelemetryOrder(base, { ...base, eventId: 'event_A' }), 1);
  assert.equal(compareTelemetryOrder(base, { ...base }), 0);
  assert.equal(incomingShouldReplaceCurrent(null, base), true);
  assert.equal(incomingShouldReplaceCurrent(base, { ...base }), true);
  assert.equal(incomingShouldReplaceCurrent(base, { ...base, eventId: 'event_A' }), false);
});

test('cleanup selection is expired-only, deterministic and bounded', () => {
  const records = {
    later: { expiresAt: 100 },
    same_b: { expiresAt: 50 },
    same_a: { expiresAt: 50 },
    future: { expiresAt: 101 },
    malformed: { expiresAt: '50' },
  };
  assert.deepEqual(expiredIngestionChildKeys(records, 100, 2), ['same_a', 'same_b']);
  assert.deepEqual(expiredIngestionChildKeys(records, 100, 10), [
    'same_a', 'same_b', 'later',
  ]);
});
