export const INGESTION_CLEANUP_LIMIT = 25;

function isRecord(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function validOrderValue(reading) {
  return isRecord(reading) && Number.isSafeInteger(reading.deviceTimestamp) &&
    reading.deviceTimestamp >= 0 && typeof reading.eventId === 'string' &&
    /^[A-Za-z0-9_-]{1,128}$/.test(reading.eventId);
}

// Device time is authoritative for reading order. Event IDs are restricted to
// ASCII safe-ID characters, so direct code-unit comparison is deterministic
// across runtimes and independent of locale or arrival order.
export function compareTelemetryOrder(left, right) {
  if (!validOrderValue(left) || !validOrderValue(right)) {
    throw new TypeError('Comparable telemetry readings are required.');
  }
  if (left.deviceTimestamp !== right.deviceTimestamp) {
    return left.deviceTimestamp < right.deviceTimestamp ? -1 : 1;
  }
  if (left.eventId === right.eventId) return 0;
  return left.eventId < right.eventId ? -1 : 1;
}

export function incomingShouldReplaceCurrent(current, incoming) {
  if (!validOrderValue(incoming)) {
    throw new TypeError('A comparable incoming telemetry reading is required.');
  }
  if (!validOrderValue(current)) return true;
  // Rewriting the same event repairs a partially missing/malformed current
  // projection while preserving its original serverReceivedAt.
  if (current.eventId === incoming.eventId) return true;
  return compareTelemetryOrder(incoming, current) > 0;
}

export function expiredIngestionChildKeys(records, now, limit = INGESTION_CLEANUP_LIMIT) {
  if (!Number.isSafeInteger(now) || now < 0 ||
      !Number.isSafeInteger(limit) || limit < 1) {
    throw new TypeError('A valid cleanup time and positive limit are required.');
  }
  if (!isRecord(records)) return [];
  return Object.entries(records)
    .filter(([, value]) => isRecord(value) &&
      Number.isSafeInteger(value.expiresAt) && value.expiresAt <= now)
    .sort(([leftKey, left], [rightKey, right]) =>
      left.expiresAt - right.expiresAt ||
      (leftKey < rightKey ? -1 : leftKey > rightKey ? 1 : 0))
    .slice(0, limit)
    .map(([key]) => key);
}

async function expiredQuery(reference, now, limit) {
  // Active helmet branches are continuously bounded by this cleanup. Reading
  // the per-helmet branch avoids making maintenance depend on a deployed RTDB
  // index/rules change; deletion work remains strictly capped by limit.
  const snapshot = await reference.get();
  return expiredIngestionChildKeys(snapshot.val(), now, limit);
}

export async function cleanupExpiredIngestionState(
  database,
  helmetId,
  now,
  limit = INGESTION_CLEANUP_LIMIT,
) {
  const [nonceKeys, rateKeys] = await Promise.all([
    expiredQuery(database.ref(`ingestionNonces/${helmetId}`), now, limit),
    expiredQuery(database.ref(`ingestionRateLimits/${helmetId}`), now, limit),
  ]);
  const updates = {};
  for (const key of nonceKeys) updates[`ingestionNonces/${helmetId}/${key}`] = null;
  for (const key of rateKeys) updates[`ingestionRateLimits/${helmetId}/${key}`] = null;
  if (Object.keys(updates).length > 0) await database.ref().update(updates);
  return Object.freeze({ nonceDeletes: nonceKeys.length, rateLimitDeletes: rateKeys.length });
}
