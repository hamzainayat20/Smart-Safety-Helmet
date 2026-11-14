import assert from 'node:assert/strict';
import test from 'node:test';

import { createGroqClient } from '../groq_client.js';

test('Groq client sends a bounded low-temperature request', async () => {
  let captured;
  const client = createGroqClient({
    apiKey: 'test_key_that_is_long_enough',
    model: 'openai/gpt-oss-120b',
    fetchImpl: async (url, options) => {
      captured = { url, options };
      return {
        ok: true,
        json: async () => ({ choices: [{ message: { content: ' Grounded answer. ' } }] }),
      };
    },
  });
  assert.equal(await client.complete([{ role: 'user', content: 'Question' }]), 'Grounded answer.');
  assert.equal(captured.url, 'https://api.groq.com/openai/v1/chat/completions');
  assert.equal(captured.options.headers.authorization, 'Bearer test_key_that_is_long_enough');
  const body = JSON.parse(captured.options.body);
  assert.equal(body.model, 'openai/gpt-oss-120b');
  assert.equal(body.temperature, 0.1);
  assert.equal(body.max_completion_tokens, 500);
});

test('Groq provider errors do not expose response bodies', async () => {
  const client = createGroqClient({
    apiKey: 'test_key_that_is_long_enough',
    model: 'openai/gpt-oss-120b',
    fetchImpl: async () => ({ ok: false, status: 429 }),
  });
  await assert.rejects(
    client.complete([{ role: 'user', content: 'Question' }]),
    /status 429/,
  );
});
