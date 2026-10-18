import { createHash, createHmac, timingSafeEqual } from 'node:crypto';

export const DEVICE_AUTH_HEADERS = Object.freeze({
  helmetId: 'x-smart-safety-helmet-id',
  timestamp: 'x-smart-safety-timestamp',
  nonce: 'x-smart-safety-nonce',
  keyVersion: 'x-smart-safety-key-version',
  signature: 'x-smart-safety-signature',
});

export const DEVICE_AUTH_TOLERANCE_MS = 5 * 60 * 1000;

export class DeviceAuthError extends Error {
  constructor(code, message, httpStatus = 401) {
    super(message);
    this.name = 'DeviceAuthError';
    this.code = code;
    this.httpStatus = httpStatus;
  }

  toJSON() {
    return { code: this.code, message: this.message };
  }
}

export function sha256Hex(value) {
  return createHash('sha256').update(value).digest('hex');
}

export function telemetrySigningPath(helmetId) {
  return `/ingest/v1/helmets/${helmetId}/telemetry`;
}

export function canonicalDeviceRequest({ helmetId, timestamp, nonce, rawBody }) {
  return [
    'POST',
    telemetrySigningPath(helmetId),
    String(timestamp),
    nonce,
    sha256Hex(rawBody),
  ].join('\n');
}

export function signDeviceRequest(request, secret) {
  return createHmac('sha256', secret)
    .update(canonicalDeviceRequest(request), 'utf8')
    .digest('hex');
}

function safeEqualHex(actual, expected) {
  if (!/^[a-f0-9]{64}$/i.test(actual)) return false;
  const actualBytes = Buffer.from(actual, 'hex');
  const expectedBytes = Buffer.from(expected, 'hex');
  return actualBytes.length === expectedBytes.length &&
    timingSafeEqual(actualBytes, expectedBytes);
}

export function parseDeviceSecretRegistry(serialized) {
  let registry;
  try {
    registry = JSON.parse(serialized);
  } catch {
    throw new DeviceAuthError(
      'DEVICE_AUTH_UNAVAILABLE',
      'Device authentication is unavailable.',
      503,
    );
  }
  if (!registry || typeof registry !== 'object' || Array.isArray(registry)) {
    throw new DeviceAuthError(
      'DEVICE_AUTH_UNAVAILABLE',
      'Device authentication is unavailable.',
      503,
    );
  }
  return registry;
}

export function authenticateDeviceRequest({
  headers,
  rawBody,
  secretRegistry,
  now = Date.now(),
  toleranceMs = DEVICE_AUTH_TOLERANCE_MS,
}) {
  const helmetId = headers[DEVICE_AUTH_HEADERS.helmetId];
  const timestampText = headers[DEVICE_AUTH_HEADERS.timestamp];
  const nonce = headers[DEVICE_AUTH_HEADERS.nonce];
  const keyVersion = headers[DEVICE_AUTH_HEADERS.keyVersion];
  const signature = headers[DEVICE_AUTH_HEADERS.signature];

  if (typeof helmetId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(helmetId) ||
      typeof nonce !== 'string' || !/^[A-Za-z0-9_-]{16,96}$/.test(nonce) ||
      typeof keyVersion !== 'string' || !/^[A-Za-z0-9._-]{1,32}$/.test(keyVersion) ||
      typeof signature !== 'string') {
    throw new DeviceAuthError('INVALID_DEVICE_AUTH', 'Device authentication failed.');
  }

  if (!/^\d{13}$/.test(String(timestampText))) {
    throw new DeviceAuthError('INVALID_DEVICE_AUTH', 'Device authentication failed.');
  }
  const timestamp = Number(timestampText);
  if (!Number.isSafeInteger(timestamp) || Math.abs(now - timestamp) > toleranceMs) {
    throw new DeviceAuthError('EXPIRED_DEVICE_REQUEST', 'Device request timestamp is outside the allowed window.');
  }

  const credential = secretRegistry[helmetId];
  if (!credential || credential.revoked === true || credential.keyVersion !== keyVersion ||
      typeof credential.secretBase64 !== 'string') {
    throw new DeviceAuthError('INVALID_DEVICE_AUTH', 'Device authentication failed.');
  }
  let secret;
  try {
    secret = Buffer.from(credential.secretBase64, 'base64');
  } catch {
    secret = Buffer.alloc(0);
  }
  if (secret.length < 32) {
    throw new DeviceAuthError('DEVICE_AUTH_UNAVAILABLE', 'Device authentication is unavailable.', 503);
  }

  const expected = signDeviceRequest({ helmetId, timestamp, nonce, rawBody }, secret);
  if (!safeEqualHex(signature, expected)) {
    throw new DeviceAuthError('INVALID_DEVICE_AUTH', 'Device authentication failed.');
  }
  return Object.freeze({ helmetId, timestamp, nonce, keyVersion });
}
