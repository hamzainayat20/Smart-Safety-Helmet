import {
  buildUnassessedTelemetryRecord,
  enforceTelemetryPayloadSize,
  semanticTelemetryHash,
  TelemetryContractError,
  validateCanonicalTelemetry,
} from './telemetry_contract.js';
import {
  authenticateDeviceRequest,
  DEVICE_AUTH_HEADERS,
  DeviceAuthError,
  parseDeviceSecretRegistry,
} from './device_auth.js';
import {
  cleanupExpiredIngestionState,
  incomingShouldReplaceCurrent,
} from './ingestion_state.js';

export const INGESTION_RATE_LIMIT_PER_MINUTE = 30;

export class TelemetryIngestionError extends Error {
  constructor(code, message, httpStatus) {
    super(message);
    this.name = 'TelemetryIngestionError';
    this.code = code;
    this.httpStatus = httpStatus;
  }

  toJSON() {
    return { code: this.code, message: this.message };
  }
}

async function backendStage(code, operation) {
  try {
    return await operation();
  } catch (error) {
    if (error instanceof TelemetryIngestionError) throw error;
    throw new TelemetryIngestionError(
      code,
      'Telemetry storage is temporarily unavailable.',
      503,
    );
  }
}

function headerMap(headers) {
  return Object.fromEntries(
    Object.entries(headers ?? {}).map(([key, value]) => [
      key.toLowerCase(),
      Array.isArray(value) ? value[0] : value,
    ]),
  );
}

function parseJsonBody(rawBody) {
  try {
    return JSON.parse(rawBody.toString('utf8'));
  } catch {
    throw new TelemetryIngestionError('INVALID_JSON', 'Request body must be valid JSON.', 400);
  }
}

async function consumeRateLimit(database, helmetId, now, limit) {
  const minute = Math.floor(now / 60000);
  const reference = database.ref(`ingestionRateLimits/${helmetId}/${minute}`);
  const result = await backendStage('RATE_LIMIT_STORAGE_ERROR', () =>
    reference.transaction((current) => {
      const count = typeof current?.count === 'number' ? current.count : 0;
      if (count >= limit) return;
      return { count: count + 1, expiresAt: (minute + 2) * 60000 };
    }));
  if (!result.committed) {
    throw new TelemetryIngestionError('RATE_LIMITED', 'Telemetry rate limit exceeded.', 429);
  }
}

async function reserveNonce(database, auth, now) {
  const reference = database.ref(`ingestionNonces/${auth.helmetId}/${auth.nonce}`);
  const result = await backendStage('NONCE_STORAGE_ERROR', () =>
    reference.transaction((current) =>
      current ? undefined : {
        requestTimestamp: auth.timestamp,
        receivedAt: now,
        expiresAt: now + 600000,
      }));
  if (!result.committed) {
    throw new TelemetryIngestionError('REPLAYED_REQUEST', 'Device request was already used.', 409);
  }
}

async function reserveEvent(database, payload, hash, now) {
  const reference = database.ref(`dedupe/${payload.helmetId}/${payload.eventId}`);
  const result = await backendStage('DEDUPE_STORAGE_ERROR', () =>
    reference.transaction((current) => {
      if (current) return;
      return { semanticHash: hash, status: 'pending', firstReceivedAt: now };
    }));
  const existing = result.snapshot.val();
  if (existing?.semanticHash !== hash) {
    throw new TelemetryIngestionError(
      'EVENT_ID_CONFLICT',
      'The event ID is already associated with different telemetry.',
      409,
    );
  }
  if (!Number.isSafeInteger(existing?.firstReceivedAt) ||
      existing.firstReceivedAt < 0 ||
      !['pending', 'stored'].includes(existing.status)) {
    throw new TelemetryIngestionError(
      'INVALID_DEDUPE_STATE',
      'The event reservation cannot be reconciled.',
      503,
    );
  }
  return {
    duplicate: !result.committed,
    reference,
    firstReceivedAt: existing.firstReceivedAt,
  };
}

async function ensureHistory(database, payload, record) {
  const reference = database.ref(`readings/${payload.helmetId}/${payload.eventId}`);
  await backendStage('HISTORY_STORAGE_ERROR', () =>
    reference.transaction((current) => current ?? record));
}

async function reconcileCurrent(database, payload, record) {
  const reference = database.ref(`helmets/${payload.helmetId}/current`);
  await backendStage('CURRENT_STORAGE_ERROR', () =>
    reference.transaction((current) =>
      incomingShouldReplaceCurrent(current, record) ? record : undefined));
}

async function markHelmetOnline(database, helmetId, now) {
  const reference = database.ref(`helmets/${helmetId}/meta`);
  await backendStage('PRESENCE_STORAGE_ERROR', () =>
    reference.transaction((current) => {
      if (!current || typeof current !== 'object') return;
      const previousLastSeenAt = Number.isSafeInteger(current.lastSeenAt)
        ? current.lastSeenAt
        : 0;
      return {
        ...current,
        connectivity: 'online',
        lastSeenAt: Math.max(previousLastSeenAt, now),
      };
    }));
}

async function markEventStored(reservation, hash) {
  // The reservation has already bound eventId to semanticHash. A narrow update
  // avoids RTDB transaction callbacks aborting on an initially empty local
  // cache while preserving firstReceivedAt and semanticHash byte-for-byte.
  await backendStage('DEDUPE_FINALIZATION_ERROR', () =>
    reservation.reference.update({ status: 'stored' }));
  const stored = (await backendStage('DEDUPE_FINALIZATION_READ_ERROR', () =>
    reservation.reference.get())).val();
  if (stored?.semanticHash !== hash || stored?.status !== 'stored' ||
      stored?.firstReceivedAt !== reservation.firstReceivedAt) {
    throw new TelemetryIngestionError(
      'DEDUPE_FINALIZATION_FAILED',
      'The event could not be finalized.',
      503,
    );
  }
}

// Admin-registered helmets (Admin Console, module M15) keep their device
// credential in /deviceSecrets/{helmetId} because a callable cannot rewrite
// the HELMET_DEVICE_SECRETS env secret. Helmets present in the env registry
// are verified exactly as before and never touch the database here; only a
// helmet missing from the env registry falls back to its /deviceSecrets
// record, which then goes through the identical authenticateDeviceRequest
// verification (keyVersion match, revoked check, HMAC comparison).
async function secretRegistryWithDatabaseFallback(database, headers, envRegistry) {
  const helmetId = headers[DEVICE_AUTH_HEADERS.helmetId];
  if (typeof helmetId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(helmetId) ||
      Object.hasOwn(envRegistry, helmetId)) {
    return envRegistry;
  }
  let stored;
  try {
    stored = (await database.ref(`deviceSecrets/${helmetId}`).get()).val();
  } catch {
    throw new DeviceAuthError(
      'DEVICE_AUTH_UNAVAILABLE',
      'Device authentication is unavailable.',
      503,
    );
  }
  if (!stored || typeof stored !== 'object' || Array.isArray(stored)) {
    return envRegistry;
  }
  return { ...envRegistry, [helmetId]: stored };
}

export function createTelemetryIngestionHandler({
  database,
  secretRegistryValue,
  clock = () => Date.now(),
  rateLimit = INGESTION_RATE_LIMIT_PER_MINUTE,
}) {
  return async function handleTelemetryIngestion(request, response) {
    try {
      if (request.method !== 'POST') {
        response.set('Allow', 'POST').status(405).json({
          error: { code: 'METHOD_NOT_ALLOWED', message: 'Only POST is supported.' },
        });
        return;
      }
      const contentType = request.get?.('content-type') ?? request.headers?.['content-type'];
      if (typeof contentType !== 'string' || !contentType.toLowerCase().startsWith('application/json')) {
        throw new TelemetryIngestionError('UNSUPPORTED_MEDIA_TYPE', 'Content-Type must be application/json.', 415);
      }

      const rawBody = Buffer.isBuffer(request.rawBody)
        ? request.rawBody
        : Buffer.from(typeof request.body === 'string' ? request.body : JSON.stringify(request.body ?? null));
      enforceTelemetryPayloadSize(rawBody);
      const now = clock();
      const headers = headerMap(request.headers);
      const secretRegistry = await secretRegistryWithDatabaseFallback(
        database,
        headers,
        parseDeviceSecretRegistry(secretRegistryValue()),
      );
      const auth = authenticateDeviceRequest({
        headers,
        rawBody,
        secretRegistry,
        now,
      });
      // Opportunistic bounded cleanup keeps active helmet state bounded. A
      // future scheduled administrative sweep can use the same tested helper
      // for inactive/revoked helmets without changing ingestion semantics.
      try {
        await cleanupExpiredIngestionState(database, auth.helmetId, now);
      } catch {
        // Cleanup is maintenance-only and must not make valid telemetry fail.
      }
      const payload = validateCanonicalTelemetry(parseJsonBody(rawBody), { rawPayload: rawBody });
      if (payload.helmetId !== auth.helmetId) {
        throw new TelemetryIngestionError('HELMET_ID_MISMATCH', 'Device is not authorized for this helmet.', 403);
      }
      if (payload.deviceTimestamp > now + 300000) {
        throw new TelemetryIngestionError('INVALID_DEVICE_TIMESTAMP', 'Device timestamp is too far in the future.', 400);
      }

      const meta = (await database.ref(`helmets/${auth.helmetId}/meta`).get()).val();
      if (!meta || meta.active !== true || meta.provisioningStatus !== 'provisioned') {
        throw new TelemetryIngestionError('DEVICE_NOT_ACTIVE', 'Helmet is inactive or not provisioned.', 403);
      }

      await consumeRateLimit(database, auth.helmetId, now, rateLimit);
      await reserveNonce(database, auth, now);
      const hash = semanticTelemetryHash(payload);
      const reservation = await reserveEvent(database, payload, hash, now);

      const record = buildUnassessedTelemetryRecord(payload, {
        serverReceivedAt: reservation.firstReceivedAt,
        connectivity: 'online',
      });
      await ensureHistory(database, payload, record);
      await reconcileCurrent(database, payload, record);
      // A successfully authenticated request is authoritative evidence that
      // the provisioned device is currently reachable. Keep administrative
      // helmet metadata intact while updating only its runtime presence.
      await markHelmetOnline(database, payload.helmetId, now);
      await markEventStored(reservation, hash);
      response.status(reservation.duplicate ? 200 : 202).json({
        eventId: payload.eventId,
        duplicate: reservation.duplicate,
      });
    } catch (error) {
      if (error instanceof TelemetryContractError ||
          error instanceof DeviceAuthError ||
          error instanceof TelemetryIngestionError) {
        response.status(error.httpStatus ?? 400).json({ error: error.toJSON() });
        return;
      }
      response.status(503).json({
        error: { code: 'INGESTION_UNAVAILABLE', message: 'Telemetry ingestion is temporarily unavailable.' },
      });
    }
  };
}
