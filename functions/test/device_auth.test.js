import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import test from 'node:test';

import {
  authenticateDeviceRequest,
  canonicalDeviceRequest,
  DEVICE_AUTH_HEADERS,
  signDeviceRequest,
} from '../src/device_auth.js';

const secret = randomBytes(32);
const rawBody = Buffer.from('{"helmetId":"helmet001"}');
const now = 1775900000000;

function requestHeaders(overrides = {}) {
  const values = {
    helmetId: 'helmet001',
    timestamp: now,
    nonce: 'nonce_1234567890abcdef',
    keyVersion: 'v1',
    ...overrides,
  };
  return {
    [DEVICE_AUTH_HEADERS.helmetId]: values.helmetId,
    [DEVICE_AUTH_HEADERS.timestamp]: String(values.timestamp),
    [DEVICE_AUTH_HEADERS.nonce]: values.nonce,
    [DEVICE_AUTH_HEADERS.keyVersion]: values.keyVersion,
    [DEVICE_AUTH_HEADERS.signature]: signDeviceRequest(
      { ...values, rawBody },
      secret,
    ),
  };
}

const registry = {
  helmet001: { keyVersion: 'v1', secretBase64: secret.toString('base64') },
};

test('canonical request binds method, helmet, timestamp, nonce and body hash', () => {
  const canonical = canonicalDeviceRequest({
    helmetId: 'helmet001',
    timestamp: now,
    nonce: 'nonce_1234567890abcdef',
    rawBody,
  });
  assert.match(canonical, /^POST\n\/ingest\/v1\/helmets\/helmet001\/telemetry\n/);
  assert.equal(canonical.split('\n').length, 5);
});

test('valid helmet-bound signature authenticates', () => {
  assert.deepEqual(
    authenticateDeviceRequest({ headers: requestHeaders(), rawBody, secretRegistry: registry, now }),
    {
      helmetId: 'helmet001',
      timestamp: now,
      nonce: 'nonce_1234567890abcdef',
      keyVersion: 'v1',
    },
  );
});

test('changed body, wrong helmet, revoked key and expired request are rejected', () => {
  assert.throws(() => authenticateDeviceRequest({
    headers: requestHeaders(), rawBody: Buffer.from('{}'), secretRegistry: registry, now,
  }), { code: 'INVALID_DEVICE_AUTH' });
  assert.throws(() => authenticateDeviceRequest({
    headers: requestHeaders({ helmetId: 'helmet002' }), rawBody, secretRegistry: registry, now,
  }), { code: 'INVALID_DEVICE_AUTH' });
  assert.throws(() => authenticateDeviceRequest({
    headers: requestHeaders(), rawBody,
    secretRegistry: { helmet001: { ...registry.helmet001, revoked: true } }, now,
  }), { code: 'INVALID_DEVICE_AUTH' });
  assert.throws(() => authenticateDeviceRequest({
    headers: requestHeaders({ timestamp: now - 300001 }), rawBody, secretRegistry: registry, now,
  }), { code: 'EXPIRED_DEVICE_REQUEST' });
});
