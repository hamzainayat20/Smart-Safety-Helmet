// Creates in-app alert records from stored AI safety assessments.
//
// Scope: this writes alert records to /alerts so that they appear in the
// supervisor and worker alert screens. It deliberately sends NO push
// notifications and does not change telemetry, assessments, or their
// responses. Every value in an alert comes from the stored reading or the
// validated assessment; gas never receives a ppm value.

import { canonicalAlertId } from './alert_logic.js';

// One alert per helmet and hazard type per window, so a hazard that lasts for
// many 5-second readings does not flood the alert list. A more severe level
// (warning -> critical) is always alerted immediately.
export const ASSESSMENT_ALERT_COOLDOWN_MS = 5 * 60 * 1000;
export const ALERT_PHONE_LOCATION_MAX_AGE_MS = 2 * 60 * 1000;

const SEVERITY_RANK = Object.freeze({ warning: 1, critical: 2 });
// Tie-break order when several hazards share the same severity.
const TYPE_PRIORITY = Object.freeze(['fall', 'gas', 'temperature', 'humidity']);
const SAFE_ID = /^[A-Za-z0-9_-]{1,128}$/;

function isFinite(value) {
  return typeof value === 'number' && Number.isFinite(value);
}

function isAlertRisk(value) {
  return value === 'warning' || value === 'critical';
}

function hazardsFrom(assessment, reading) {
  const hazards = [];
  const reasons = Array.isArray(assessment.reasonCodes) ? assessment.reasonCodes : [];

  if (assessment.fall?.status === 'evaluated' && reasons.includes('FALL_DETECTED')) {
    hazards.push({ alertType: 'fall', severity: 'critical' });
  }

  const gas = assessment.gas;
  if (gas?.status === 'evaluated' && gas.outOfDistribution === false &&
      !reasons.includes('GAS_MODEL_UNAVAILABLE') && gas.confidence >= 0.55) {
    if (gas.classification === 'Smoke' && reasons.includes('GAS_SMOKE')) {
      hazards.push({ alertType: 'gas', severity: gas.confidence >= 0.8 ? 'critical' : 'warning' });
    } else if (gas.classification === 'Mixture' && reasons.includes('GAS_MIXTURE')) {
      hazards.push({ alertType: 'gas', severity: 'warning' });
    }
  }

  const environment = assessment.environment ?? {};
  const temperatureRisk = environment.temperatureRisk;
  const heatIndexRisk = environment.heatIndexRisk;
  if (isAlertRisk(temperatureRisk) || isAlertRisk(heatIndexRisk)) {
    const useTemperature = isAlertRisk(temperatureRisk) &&
      (!isAlertRisk(heatIndexRisk) ||
       SEVERITY_RANK[temperatureRisk] >= SEVERITY_RANK[heatIndexRisk]);
    const severity = useTemperature ? temperatureRisk : heatIndexRisk;
    const value = useTemperature ? reading.temperatureC : reading.heatIndexC;
    hazards.push({
      alertType: 'temperature',
      severity,
      ...(isFinite(value) ? { sensorValue: value, unit: 'degreesCelsius' } : {}),
    });
  }
  if (isAlertRisk(environment.humidityRisk)) {
    hazards.push({
      alertType: 'humidity',
      severity: environment.humidityRisk,
      ...(isFinite(reading.humidityPct)
        ? { sensorValue: reading.humidityPct, unit: 'percentRelativeHumidity' }
        : {}),
    });
  }
  return hazards;
}

function evidenceFrom(assessment, reading) {
  const evidence = {};
  for (const key of ['temperatureC', 'humidityPct', 'heatIndexC']) {
    if (isFinite(reading[key])) evidence[key] = reading[key];
  }
  if (assessment.fall?.status === 'evaluated') {
    if (isFinite(assessment.fall.probability)) evidence.fallProbability = assessment.fall.probability;
    if (isFinite(assessment.fall.threshold)) evidence.fallThreshold = assessment.fall.threshold;
  }
  if (assessment.gas?.status === 'evaluated' && isFinite(assessment.gas.confidence)) {
    evidence.gasConfidence = assessment.gas.confidence;
  }
  return evidence;
}

/**
 * Picks the single most important hazard of a warning/critical assessment.
 * Returns null when the assessment does not warrant an alert.
 */
export function alertCandidateFromAssessment(assessment, reading) {
  if (!assessment || !reading || !isAlertRisk(assessment.overallRisk)) return null;
  const hazards = hazardsFrom(assessment, reading);
  if (hazards.length === 0) return null;
  hazards.sort((a, b) =>
    (SEVERITY_RANK[b.severity] - SEVERITY_RANK[a.severity]) ||
    (TYPE_PRIORITY.indexOf(a.alertType) - TYPE_PRIORITY.indexOf(b.alertType)));
  const evidence = evidenceFrom(assessment, reading);
  if (Object.keys(evidence).length === 0) return null;
  return { ...hazards[0], evidence };
}

/** Builds the alert record in the exact shape the Flutter app parses. */
function freshPhoneLocation(value, serverReceivedAt) {
  if (!value || value.source !== 'phoneGps' ||
      !isFinite(value.latitude) || value.latitude < -90 || value.latitude > 90 ||
      !isFinite(value.longitude) || value.longitude < -180 || value.longitude > 180 ||
      (value.latitude === 0 && value.longitude === 0) ||
      !isFinite(value.accuracyM) || value.accuracyM < 0 ||
      !Number.isSafeInteger(value.updatedAt) ||
      Math.abs(serverReceivedAt - value.updatedAt) > ALERT_PHONE_LOCATION_MAX_AGE_MS) {
    return null;
  }
  return {
    latitude: value.latitude,
    longitude: value.longitude,
    accuracyM: value.accuracyM,
    source: 'phoneGps',
    capturedAt: value.updatedAt,
  };
}

export function buildAssessmentAlertRecord({ candidate, reading, meta, workerLocation, now }) {
  const alertId = canonicalAlertId(reading.helmetId, reading.eventId);
  const location = freshPhoneLocation(workerLocation, now);
  return {
    schemaVersion: '1.0',
    alertId,
    eventId: reading.eventId,
    helmetId: reading.helmetId,
    siteId: meta.siteId,
    ...(typeof meta.assignedWorkerId === 'string' && SAFE_ID.test(meta.assignedWorkerId)
      ? { workerId: meta.assignedWorkerId }
      : {}),
    alertType: candidate.alertType,
    severity: candidate.severity,
    ...(candidate.sensorValue !== undefined
      ? { sensorValue: candidate.sensorValue, unit: candidate.unit }
      : {}),
    evidence: candidate.evidence,
    deviceTimestamp: reading.deviceTimestamp,
    serverReceivedAt: now,
    ...(location ? { location } : {}),
    status: 'created',
  };
}

/**
 * Writes one in-app alert for a warning/critical assessment, if the cooldown
 * allows it. Never sends notifications. Returns a small status object.
 */
export async function createAlertFromAssessment({
  database,
  assessment,
  reading,
  clock = () => Date.now(),
  cooldownMs = ASSESSMENT_ALERT_COOLDOWN_MS,
}) {
  const candidate = alertCandidateFromAssessment(assessment, reading);
  if (!candidate) return { status: 'none' };
  if (!SAFE_ID.test(reading.helmetId ?? '') || !SAFE_ID.test(reading.eventId ?? '') ||
      !Number.isSafeInteger(reading.deviceTimestamp)) {
    return { status: 'skipped', reason: 'INVALID_SOURCE' };
  }

  const [metaSnapshot, locationSnapshot] = await Promise.all([
    database.ref(`helmets/${reading.helmetId}/meta`).get(),
    database.ref(`helmets/${reading.helmetId}/workerLocation`).get(),
  ]);
  const meta = metaSnapshot.val();
  if (!meta || typeof meta.siteId !== 'string' || !SAFE_ID.test(meta.siteId)) {
    return { status: 'skipped', reason: 'HELMET_SITE_UNKNOWN' };
  }

  const now = clock();
  const alert = buildAssessmentAlertRecord({
    candidate,
    reading,
    meta,
    workerLocation: locationSnapshot.val(),
    now,
  });
  const rank = SEVERITY_RANK[candidate.severity];

  // Cooldown marker in the existing backend-only dedupe branch.
  const markerReference = database.ref(
    `dedupe/${reading.helmetId}/assessmentAlert_${candidate.alertType}`,
  );
  let previousMarker = null;
  const marker = await markerReference.transaction((current) => {
    previousMarker = current ?? null;
    if (current &&
        Number.isSafeInteger(current.createdAt) &&
        now - current.createdAt < cooldownMs &&
        Number(current.severityRank) >= rank) {
      return undefined; // still within cooldown at the same or higher severity
    }
    return { alertId: alert.alertId, severityRank: rank, createdAt: now };
  });
  if (!marker.committed) return { status: 'suppressed', alertId: null };

  try {
    const written = await database.ref(`alerts/${alert.alertId}`).transaction(
      (current) => (current ? undefined : alert),
    );
    return {
      status: written.committed ? 'created' : 'exists',
      alertId: alert.alertId,
    };
  } catch (error) {
    // Restore the previous cooldown marker so a later reading can retry.
    await markerReference.set(previousMarker).catch(() => {});
    throw error;
  }
}
