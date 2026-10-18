import { createHash } from 'node:crypto';

export const ALERT_TYPES = Object.freeze([
  'gas',
  'temperature',
  'humidity',
  'fall',
  'battery',
  'sensor_fault',
  'connectivity',
]);

export const ALERT_STATUSES = Object.freeze([
  'created',
  'delivered',
  'viewed',
  'acknowledged',
  'resolved',
]);

const UNITS = new Set([
  'degreesCelsius',
  'percentRelativeHumidity',
  'partsPerMillion',
  'percent',
  'standardGravity',
  'decibelMilliwatts',
]);

const MEASURED_ALERT_TYPES = new Set([
  'gas',
  'temperature',
  'humidity',
  'fall',
  'battery',
]);

export class AlertValidationError extends Error {
  constructor(message, code = 'invalid-argument') {
    super(message);
    this.name = 'AlertValidationError';
    this.code = code;
  }
}

function record(value, field) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new AlertValidationError(`${field} must be an object.`);
  }
  return value;
}

function requiredId(value, field) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(value)) {
    throw new AlertValidationError(
      `${field} must be a safe opaque identifier of at most 128 characters.`,
    );
  }
  return value;
}

function requiredEnum(value, field, values) {
  if (typeof value !== 'string' || !values.includes(value)) {
    throw new AlertValidationError(`${field} has an unsupported value.`);
  }
  return value;
}

function finiteNumber(value, field, { required = false } = {}) {
  if (value === null || value === undefined) {
    if (required) throw new AlertValidationError(`${field} is required.`);
    return null;
  }
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new AlertValidationError(`${field} must be a finite number.`);
  }
  return value;
}

function integerTimestamp(value, field) {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new AlertValidationError(`${field} must be a UTC epoch millisecond timestamp.`);
  }
  return value;
}

function validateLocation(value, now) {
  if (value === null || value === undefined) return null;
  const location = record(value, 'location');
  const latitude = finiteNumber(location.latitude, 'location.latitude', { required: true });
  const longitude = finiteNumber(location.longitude, 'location.longitude', { required: true });
  const hdop = finiteNumber(location.hdop, 'location.hdop', { required: true });
  const capturedAt = integerTimestamp(location.capturedAt, 'location.capturedAt');
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    throw new AlertValidationError('Location coordinates are outside valid ranges.');
  }
  if (latitude === 0 && longitude === 0) {
    throw new AlertValidationError('The invalid 0,0 GPS sentinel is not allowed.');
  }
  if (hdop < 0 || hdop > 5) {
    throw new AlertValidationError('Location HDOP must be between 0 and 5.');
  }
  if (capturedAt > now + 5 * 60 * 1000) {
    throw new AlertValidationError('Location timestamp is too far in the future.');
  }
  if (typeof location.isLastKnown !== 'boolean') {
    throw new AlertValidationError('location.isLastKnown must be a boolean.');
  }
  return { latitude, longitude, hdop, capturedAt, isLastKnown: location.isLastKnown };
}

function validateEvidence(value) {
  const evidence = record(value, 'evidence');
  const entries = Object.entries(evidence);
  if (entries.length === 0 || entries.length > 24) {
    throw new AlertValidationError('evidence must contain between 1 and 24 fields.');
  }
  const normalized = {};
  for (const [key, item] of entries) {
    if (!/^[A-Za-z][A-Za-z0-9_]{0,63}$/.test(key)) {
      throw new AlertValidationError('evidence contains an invalid field name.');
    }
    if (item !== null && (typeof item !== 'number' || !Number.isFinite(item))) {
      throw new AlertValidationError('evidence values must be finite numbers or null.');
    }
    normalized[key] = item;
  }
  return normalized;
}

export function canonicalAlertId(helmetId, eventId) {
  return createHash('sha256')
    .update(`${helmetId}\u0000${eventId}`)
    .digest('hex');
}

export function registrationTokenHash(token) {
  return createHash('sha256').update(token).digest('hex');
}

export function tokenAssociationUpdates({
  uid,
  token,
  platform,
  now,
  existingCreatedAt,
  previousOwner,
}) {
  const tokenHash = registrationTokenHash(token);
  const updates = {
    [`notificationTokens/${uid}/${tokenHash}`]: {
      token,
      platform,
      createdAt: existingCreatedAt ?? now,
      updatedAt: now,
    },
    [`users/${uid}/fcmTokenRefs/${tokenHash}`]: true,
    [`notificationTokenOwners/${tokenHash}`]: uid,
  };
  if (typeof previousOwner === 'string' && previousOwner !== uid) {
    updates[`notificationTokens/${previousOwner}/${tokenHash}`] = null;
    updates[`users/${previousOwner}/fcmTokenRefs/${tokenHash}`] = null;
  }
  return { tokenHash, updates };
}

export function tokenRemovalUpdates({ uid, token, owner }) {
  const tokenHash = registrationTokenHash(token);
  const updates = {
    [`notificationTokens/${uid}/${tokenHash}`]: null,
    [`users/${uid}/fcmTokenRefs/${tokenHash}`]: null,
  };
  if (owner === uid) updates[`notificationTokenOwners/${tokenHash}`] = null;
  return { tokenHash, updates };
}

export function validateAlertPayload(input, { claimedHelmetId, now = Date.now() }) {
  const payload = record(input, 'alert');
  const serializedLength = Buffer.byteLength(JSON.stringify(payload), 'utf8');
  if (serializedLength > 16 * 1024) {
    throw new AlertValidationError('Alert payload exceeds the 16 KiB limit.');
  }
  const helmetId = requiredId(payload.helmetId, 'helmetId');
  if (helmetId !== claimedHelmetId) {
    throw new AlertValidationError('Device identity is not bound to this Helmet ID.', 'permission-denied');
  }
  const eventId = requiredId(payload.eventId, 'eventId');
  const alertType = requiredEnum(payload.alertType, 'alertType', ALERT_TYPES);
  const severity = requiredEnum(payload.severity, 'severity', ['warning', 'critical']);
  const deviceTimestamp = integerTimestamp(payload.deviceTimestamp, 'deviceTimestamp');
  if (deviceTimestamp > now + 5 * 60 * 1000 || deviceTimestamp < now - 30 * 24 * 60 * 60 * 1000) {
    throw new AlertValidationError('deviceTimestamp is outside the accepted replay/skew window.');
  }
  const requiresMeasurement = MEASURED_ALERT_TYPES.has(alertType);
  const sensorValue = finiteNumber(payload.sensorValue, 'sensorValue', { required: requiresMeasurement });
  const threshold = finiteNumber(payload.threshold, 'threshold', { required: requiresMeasurement });
  let unit = null;
  if (sensorValue !== null || threshold !== null) {
    unit = requiredEnum(payload.unit, 'unit', [...UNITS]);
  } else if (payload.unit !== null && payload.unit !== undefined) {
    throw new AlertValidationError('unit is only valid with numeric sensor evidence.');
  }
  const evidence = validateEvidence(payload.evidence);
  if (alertType === 'fall') {
    for (const field of ['freeFallDurationMs', 'impactG', 'stillnessDurationMs']) {
      if (!Number.isFinite(evidence[field]) || evidence[field] <= 0) {
        throw new AlertValidationError(
          `Confirmed fall evidence requires a positive ${field}.`,
        );
      }
    }
  }
  if (alertType === 'gas' && evidence.gasWarmUp !== 0 && evidence.warmUp !== 0) {
    throw new AlertValidationError('Gas alerts are invalid during MQ135 warm-up.');
  }
  return {
    schemaVersion: payload.schemaVersion === '1.0' ? '1.0' : (() => {
      throw new AlertValidationError('Unsupported schemaVersion.');
    })(),
    eventId,
    helmetId,
    alertType,
    severity,
    sensorValue,
    threshold,
    unit,
    evidence,
    deviceTimestamp,
    location: validateLocation(payload.location, now),
  };
}

function requiredConfigNumber(config, key) {
  const value = config?.[key];
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new AlertValidationError(
      `Approved configuration is missing ${key}.`,
      'failed-precondition',
    );
  }
  return value;
}

function approximatelyEqual(left, right) {
  return Math.abs(left - right) < 1e-9;
}

export function validateAlertDecision(payload, config) {
  const { alertType: type, severity, sensorValue: value, threshold, unit } = payload;
  const expectUnit = (expected) => {
    if (unit !== expected) throw new AlertValidationError(`Unexpected unit for ${type} alert.`);
  };
  const expectThreshold = (expected) => {
    if (!approximatelyEqual(threshold, expected)) {
      throw new AlertValidationError('Alert threshold does not match approved configuration.');
    }
  };
  switch (type) {
    case 'gas': {
      expectUnit('partsPerMillion');
      const warning = requiredConfigNumber(config, 'gasWarningPpm');
      const critical = requiredConfigNumber(config, 'gasCriticalPpm');
      const expected = severity === 'critical' ? critical : warning;
      expectThreshold(expected);
      if (value < expected || (severity === 'warning' && value >= critical)) {
        throw new AlertValidationError('Gas severity does not match the approved thresholds.');
      }
      break;
    }
    case 'temperature': {
      expectUnit('degreesCelsius');
      const warning = requiredConfigNumber(config, 'temperatureWarningC');
      const critical = requiredConfigNumber(config, 'temperatureCriticalC');
      const expected = severity === 'critical' ? critical : warning;
      expectThreshold(expected);
      if (value < expected || (severity === 'warning' && value >= critical)) {
        throw new AlertValidationError('Temperature severity does not match approved thresholds.');
      }
      break;
    }
    case 'humidity': {
      expectUnit('percentRelativeHumidity');
      const warningLow = requiredConfigNumber(config, 'humidityWarningLowPct');
      const criticalLow = requiredConfigNumber(config, 'humidityCriticalLowPct');
      const warningHigh = requiredConfigNumber(config, 'humidityWarningHighPct');
      const criticalHigh = requiredConfigNumber(config, 'humidityCriticalHighPct');
      const lowSide = value < warningLow;
      const expected = severity === 'critical'
        ? (lowSide ? criticalLow : criticalHigh)
        : (lowSide ? warningLow : warningHigh);
      expectThreshold(expected);
      const valid = severity === 'critical'
        ? value < criticalLow || value > criticalHigh
        : (value >= criticalLow && value < warningLow) ||
          (value > warningHigh && value <= criticalHigh);
      if (!valid) throw new AlertValidationError('Humidity severity does not match approved thresholds.');
      break;
    }
    case 'battery':
      expectUnit('percent');
      expectThreshold(20);
      if (severity !== 'warning' || value >= 20 || value < 0) {
        throw new AlertValidationError('Low-battery alerts must be warnings below 20%.');
      }
      break;
    case 'fall': {
      expectUnit('standardGravity');
      if (severity !== 'critical') {
        throw new AlertValidationError('A confirmed fall must be critical.');
      }
      const impact = requiredConfigNumber(config, 'fallImpactThresholdG');
      expectThreshold(impact);
      if (payload.evidence.impactG < impact || value < impact) {
        throw new AlertValidationError('Fall impact evidence is below the approved threshold.');
      }
      break;
    }
    case 'sensor_fault':
      if (value !== null || threshold !== null || unit !== null) {
        throw new AlertValidationError('Sensor-fault alerts use fault evidence, not fabricated readings.');
      }
      break;
    case 'connectivity':
      if (value !== null && unit !== 'decibelMilliwatts') {
        throw new AlertValidationError('Connectivity measurements must use dBm.');
      }
      break;
    default:
      throw new AlertValidationError('Unsupported alert decision type.');
  }
  return payload;
}

export function buildAlertRecord(payload, assignment, now = Date.now()) {
  const siteId = requiredId(assignment.siteId, 'assignment.siteId');
  const workerId = assignment.assignedWorkerId == null
    ? null
    : requiredId(assignment.assignedWorkerId, 'assignment.assignedWorkerId');
  const alertId = canonicalAlertId(payload.helmetId, payload.eventId);
  return {
    schemaVersion: '1.0',
    alertId,
    eventId: payload.eventId,
    helmetId: payload.helmetId,
    siteId,
    workerId,
    alertType: payload.alertType,
    severity: payload.severity,
    ...(payload.sensorValue !== null ? { sensorValue: payload.sensorValue } : {}),
    ...(payload.threshold !== null ? { threshold: payload.threshold } : {}),
    ...(payload.unit !== null ? { unit: payload.unit } : {}),
    evidence: payload.evidence,
    deviceTimestamp: payload.deviceTimestamp,
    serverReceivedAt: now,
    ...(payload.location !== null ? { location: payload.location } : {}),
    status: 'created',
  };
}

export function safeNotificationPayload(alert) {
  const critical = alert.severity === 'critical';
  return {
    notification: {
      title: critical ? 'Critical safety alert' : 'Safety warning',
      body: 'Open SafeHelmet Pro to review the authenticated incident record.',
    },
    data: {
      alertId: alert.alertId,
      severity: alert.severity,
    },
  };
}

export function viewedTransition(alert, actorUid, now = Date.now()) {
  if (!['created', 'delivered'].includes(alert.status)) return alert;
  return { ...alert, status: 'viewed', viewedBy: actorUid, viewedAt: now };
}

export function acknowledgeTransition(alert, actorUid, now = Date.now()) {
  if (alert.status === 'acknowledged' || alert.status === 'resolved') return alert;
  if (!['created', 'delivered', 'viewed'].includes(alert.status)) {
    throw new AlertValidationError('Alert is not in an acknowledgeable state.', 'failed-precondition');
  }
  return {
    ...alert,
    status: 'acknowledged',
    acknowledgedBy: actorUid,
    acknowledgedAt: now,
  };
}

export function sanitizeResolutionNote(value) {
  if (typeof value !== 'string') {
    throw new AlertValidationError('resolutionNote is required.');
  }
  const note = value.trim();
  if (note.length === 0 || note.length > 500) {
    throw new AlertValidationError('resolutionNote must contain 1 to 500 characters.');
  }
  return note;
}

export function isHazardCleared(alert, current, now = Date.now()) {
  if (!current || !Number.isSafeInteger(current.serverReceivedAt)) return false;
  if (now - current.serverReceivedAt > 30_000 || current.serverReceivedAt > now + 5_000) return false;
  if (current.severity !== 'safe') return false;
  switch (alert.alertType) {
    case 'battery':
      return Number.isFinite(current.batteryPct) && current.batteryPct >= 20;
    case 'connectivity':
      return current.connectivity === 'online';
    case 'sensor_fault':
      return current.sensorFault !== true;
    case 'fall':
      return current.fallState === 'normal';
    case 'gas':
      return current.gasWarmUp === false;
    default:
      return true;
  }
}

export function resolveTransition(alert, actorUid, note, current, now = Date.now()) {
  if (alert.status === 'resolved') return alert;
  if (alert.status !== 'acknowledged') {
    throw new AlertValidationError('Alert must be acknowledged before resolution.', 'failed-precondition');
  }
  if (!isHazardCleared(alert, current, now)) {
    throw new AlertValidationError(
      'The latest trusted helmet state does not confirm that the physical hazard has cleared.',
      'failed-precondition',
    );
  }
  return {
    ...alert,
    status: 'resolved',
    resolvedBy: actorUid,
    resolvedAt: now,
    resolutionNote: sanitizeResolutionNote(note),
  };
}

export function userCanAccessAlert(user, alert, uid, role) {
  if (!user || user.active !== true || user.role !== role) return false;
  if (role === 'administrator') return true;
  const helmetAllowed = user.authorizedHelmetIds?.[alert.helmetId] === true;
  if (!helmetAllowed) return false;
  if (role === 'worker') return alert.workerId === uid;
  if (role === 'supervisor') {
    return user.siteIds?.[alert.siteId] === true;
  }
  return false;
}
