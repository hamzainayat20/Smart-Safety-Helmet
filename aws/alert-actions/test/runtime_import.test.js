import assert from 'node:assert/strict';
import test from 'node:test';

test('runtime module imports without loading configuration', async () => {
  const runtime = await import('../runtime.js');
  assert.equal(typeof runtime.getRuntime, 'function');
});
