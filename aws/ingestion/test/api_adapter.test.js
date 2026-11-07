import assert from 'node:assert/strict';
import test from 'node:test';

import { apiGatewayRequest } from '../api_adapter.js';

test('API Gateway adapter preserves the exact UTF-8 body used by HMAC', () => {
  const body = '{"helmetId":"helmet001","value":"✓"}';
  const request = apiGatewayRequest({
    body,
    isBase64Encoded: false,
    headers: { 'Content-Type': 'application/json', 'X-Test': 'value' },
    requestContext: { http: { method: 'POST' } },
  });
  assert.equal(request.method, 'POST');
  assert.equal(request.get('CONTENT-TYPE'), 'application/json');
  assert.equal(request.rawBody.toString('utf8'), body);
});

test('API Gateway adapter decodes binary-safe base64 request bodies', () => {
  const body = Buffer.from('{"eventId":"event_001"}', 'utf8');
  const request = apiGatewayRequest({
    body: body.toString('base64'),
    isBase64Encoded: true,
    headers: {},
    requestContext: { http: { method: 'POST' } },
  });
  assert.deepEqual(request.rawBody, body);
});
