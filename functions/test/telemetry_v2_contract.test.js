import assert from 'node:assert/strict';
import test from 'node:test';

import {
  FALL_FEATURE_FIELDS,
  TELEMETRY_ERROR_CODES,
  TelemetryContractError,
  validateCanonicalTelemetry,
} from '../src/telemetry_contract.js';

const fallFeatures = Object.freeze({
  acc_mean: 1,
  acc_std: 0.2,
  acc_min: 0.4,
  acc_max: 2.3,
  gyro_mean: 8,
  gyro_std: 2,
  gyro_max: 20,
  jerk_mean: 1.5,
  jerk_max: 9,
});

function payload(overrides = {}) {
  return {
    schemaVersion: '2.0',
    eventId: 'helmet001_window_1',
    helmetId: 'helmet001',
    deviceTimestamp: 1_800_000_000_000,
    firmwareVersion: '0.3.0-staging',
    temperatureC: 25,
    humidityPct: 50,
    heatIndexC: 25.5,
    accelXG: 0,
    accelYG: 0,
    accelZG: 1,
    gyroXDegreesPerSecond: 0,
    gyroYDegreesPerSecond: 0,
    gyroZDegreesPerSecond: 0,
    mq7Raw: 512,
    mq135Raw: 420,
    mq7WarmUp: false,
    mq135WarmUp: false,
    fallFeatures: { ...fallFeatures },
    samplingRateHz: 50,
    windowSamples: 100,
    windowEndTimestamp: 1_800_000_000_000,
    sensorFaults: ['gpsUnavailable', 'batteryUnavailable'],
    ...overrides,
  };
}

function contractError(fn, code, field) {
  assert.throws(fn, (error) => {
    assert.equal(error instanceof TelemetryContractError, true);
    assert.equal(error.code, code);
    if (field !== undefined) assert.equal(error.field, field);
    return true;
  });
}

test('schema 2.0 preserves separate gas inputs and the exact fall feature order', () => {
  const result = validateCanonicalTelemetry(payload());
  assert.equal(result.schemaVersion, '2.0');
  assert.equal(result.mq7Raw, 512);
  assert.equal(result.mq135Raw, 420);
  assert.equal(result.mq7WarmUp, false);
  assert.equal(result.mq135WarmUp, false);
  assert.deepEqual(Object.keys(result.fallFeatures), FALL_FEATURE_FIELDS);
  assert.equal(result.samplingRateHz, 50);
  assert.equal(result.windowSamples, 100);
});

test('schema 1.0 remains accepted without schema 2.0 fields', () => {
  const result = validateCanonicalTelemetry({
    schemaVersion: '1.0',
    eventId: 'legacy_1',
    helmetId: 'helmet001',
    deviceTimestamp: 1_800_000_000_000,
    firmwareVersion: '0.2.0-staging',
    temperatureC: 25,
    humidityPct: 50,
    accelXG: 0,
    accelYG: 0,
    accelZG: 1,
    gyroXDegreesPerSecond: 0,
    gyroYDegreesPerSecond: 0,
    gyroZDegreesPerSecond: 0,
    gasWarmUp: true,
    fallStatus: 'notEvaluated',
    sensorFaults: [
      'mq7ReadFailed',
      'mq7Uncalibrated',
      'mq7HeaterStateUnknown',
      'gpsUnavailable',
      'batteryUnavailable',
    ],
  });
  assert.equal(result.schemaVersion, '1.0');
});

test('schema versions reject fields from the other contract', () => {
  contractError(
    () => validateCanonicalTelemetry(payload({ gasWarmUp: true })),
    TELEMETRY_ERROR_CODES.unknownField,
    'gasWarmUp',
  );
  const legacy = payload({ schemaVersion: '1.0', gasWarmUp: true, fallStatus: 'notEvaluated' });
  contractError(
    () => validateCanonicalTelemetry(legacy),
    TELEMETRY_ERROR_CODES.unknownField,
    'mq7Raw',
  );
});

test('schema 2.0 enforces the approved fall window contract', () => {
  contractError(
    () => validateCanonicalTelemetry(payload({ samplingRateHz: 100 })),
    TELEMETRY_ERROR_CODES.invalidValue,
    'samplingRateHz',
  );
  contractError(
    () => validateCanonicalTelemetry(payload({ windowSamples: 99 })),
    TELEMETRY_ERROR_CODES.invalidValue,
    'windowSamples',
  );
  const incomplete = { ...fallFeatures };
  delete incomplete.jerk_max;
  contractError(
    () => validateCanonicalTelemetry(payload({ fallFeatures: incomplete })),
    TELEMETRY_ERROR_CODES.missingField,
    'fallFeatures.jerk_max',
  );
  contractError(
    () => validateCanonicalTelemetry(payload({
      fallFeatures: { ...fallFeatures, unexpected: 1 },
    })),
    TELEMETRY_ERROR_CODES.unknownField,
    'fallFeatures.unexpected',
  );
});

test('missing fall window requires a fault and never fabricated features', () => {
  const unavailable = payload();
  delete unavailable.fallFeatures;
  delete unavailable.samplingRateHz;
  delete unavailable.windowSamples;
  delete unavailable.windowEndTimestamp;
  contractError(
    () => validateCanonicalTelemetry(unavailable),
    TELEMETRY_ERROR_CODES.missingSensorFault,
    'sensorFaults',
  );
  const result = validateCanonicalTelemetry({
    ...unavailable,
    sensorFaults: [...unavailable.sensorFaults, 'fallWindowUnavailable'],
  });
  assert.equal(Object.hasOwn(result, 'fallFeatures'), false);
});

test('missing gas inputs require independent sensor faults', () => {
  const noMq7 = payload();
  delete noMq7.mq7Raw;
  contractError(
    () => validateCanonicalTelemetry(noMq7),
    TELEMETRY_ERROR_CODES.missingSensorFault,
    'sensorFaults',
  );
  assert.doesNotThrow(() => validateCanonicalTelemetry({
    ...noMq7,
    sensorFaults: [...noMq7.sensorFaults, 'mq7ReadFailed'],
  }));

  const noMq135 = payload();
  delete noMq135.mq135Raw;
  contractError(
    () => validateCanonicalTelemetry(noMq135),
    TELEMETRY_ERROR_CODES.missingSensorFault,
    'sensorFaults',
  );
  assert.doesNotThrow(() => validateCanonicalTelemetry({
    ...noMq135,
    sensorFaults: [...noMq135.sensorFaults, 'mq135ReadFailed'],
  }));
});
