import assert from 'node:assert/strict';
import test from 'node:test';

test('Lambda runtime and Firebase dependencies import successfully', async () => {
  const runtime = await import('../runtime.js');
  assert.equal(typeof runtime.getRuntime, 'function');
});
