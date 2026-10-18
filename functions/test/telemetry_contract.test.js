import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { isHazardCleared, validateAlertPayload } from '../src/alert_logic.js';
import {
  TELEMETRY_BACKEND_OWNED_FIELDS,
  TELEMETRY_ERROR_CODES,
  TELEMETRY_MAX_PAYLOAD_BYTES,
  TelemetryContractError,
  buildUnassessedTelemetryRecord,
  canonicalizeTelemetryPayload,
  enforceTelemetryPayloadSize,
  semanticTelemetryHash,
  semanticTelemetryHashFromBackendRecord,
  telemetryPayloadByteLength,
  validateCanonicalTelemetry,
} from '../src/telemetry_contract.js';

const requiredFaults = [
  'mq7Uncalibrated',
  'mq7HeaterStateUnknown',
  'gpsUnavailable',
  'batteryUnavailable',
];

function payload(overrides = {}) {
  return {
    schemaVersion: '1.0',
    eventId: 'event_001',
    helmetId: 'helmet_001',
    deviceTimestamp: 1_800_000_000_000,
    firmwareVersion: 'manual-1.0.0',
    gasWarmUp: true,
    fallStatus: 'notEvaluated',
    sensorFaults: [...requiredFaults],
    temperatureC: 27.5,
    humidityPct: 55.2,
    heatIndexC: 28.1,
    gasRaw: 1450,
    gasAdcVoltage: 1.168,
    gasSensorVoltage: 1.752,
    gasDigitalThreshold: false,
    accelXG: 0.01,
    accelYG: -0.02,
    accelZG: 0.99,
    gyroXDegreesPerSecond: 1.2,
    gyroYDegreesPerSecond: -2.4,
    gyroZDegreesPerSecond: 0,
    ...overrides,
  };
}

function expectContractError(action, code, field = undefined) {
  assert.throws(action, (error) => {
    assert.equal(error instanceof TelemetryContractError, true);
    assert.equal(error.code, code);
    if (field !== undefined) assert.equal(error.field, field);
    assert.equal(JSON.stringify(error).includes('1450'), false);
    return true;
  });
}

describe('payload size contract', () => {
  test('uses UTF-8 byte length and accepts exactly 8 KiB', () => {
    assert.equal(telemetryPayloadByteLength('£'), 2);
    assert.equal(
      enforceTelemetryPayloadSize(Buffer.alloc(TELEMETRY_MAX_PAYLOAD_BYTES)),
      TELEMETRY_MAX_PAYLOAD_BYTES,
    );
  });

  test('rejects a payload larger than 8 KiB without exposing content', () => {
    expectContractError(
      () => enforceTelemetryPayloadSize(Buffer.alloc(TELEMETRY_MAX_PAYLOAD_BYTES + 1)),
      TELEMETRY_ERROR_CODES.payloadTooLarge,
    );
  });

  test('checks the supplied raw payload before field validation', () => {
    expectContractError(
      () => validateCanonicalTelemetry(payload(), {
        rawPayload: Buffer.alloc(TELEMETRY_MAX_PAYLOAD_BYTES + 1),
      }),
      TELEMETRY_ERROR_CODES.payloadTooLarge,
    );
  });
});

describe('strict canonical telemetry validation', () => {
  test('accepts and freezes the complete canonical hardware contract', () => {
    const validated = validateCanonicalTelemetry(payload());
    assert.equal(validated.schemaVersion, '1.0');
    assert.equal(validated.gasWarmUp, true);
    assert.equal(validated.fallStatus, 'notEvaluated');
    assert.deepEqual(validated.sensorFaults, [...requiredFaults].sort());
    assert.equal(Object.isFrozen(validated), true);
    assert.equal(Object.isFrozen(validated.sensorFaults), true);
    assert.equal('severity' in validated, false);
  });

  test('requires every required field', () => {
    for (const field of [
      'schemaVersion', 'eventId', 'helmetId', 'deviceTimestamp',
      'firmwareVersion', 'gasWarmUp', 'fallStatus', 'sensorFaults',
    ]) {
      const input = payload();
      delete input[field];
      expectContractError(
        () => validateCanonicalTelemetry(input),
        TELEMETRY_ERROR_CODES.missingField,
        field,
      );
    }
  });

  test('rejects aliases, unknown fields, and nested GPS content', () => {
    for (const field of ['temperature', 'mq7Raw', 'mpuValid', 'arbitrary']) {
      expectContractError(
        () => validateCanonicalTelemetry({ ...payload(), [field]: 1 }),
        TELEMETRY_ERROR_CODES.unknownField,
        field,
      );
    }
    expectContractError(
      () => validateCanonicalTelemetry({
        ...payload(),
        location: { latitude: 1, longitude: 2, nested: { unsafe: true } },
      }),
      TELEMETRY_ERROR_CODES.unavailableField,
      'location',
    );
  });

  test('rejects all client-supplied backend-owned fields', () => {
    for (const field of TELEMETRY_BACKEND_OWNED_FIELDS) {
      expectContractError(
        () => validateCanonicalTelemetry({ ...payload(), [field]: 'client-value' }),
        TELEMETRY_ERROR_CODES.backendOwnedField,
        field,
      );
    }
  });

  test('keeps gas, GPS, and battery unavailable and rejects GPS 0,0', () => {
    assert.doesNotThrow(() => validateCanonicalTelemetry({
      ...payload(), gasPpm: null, location: null, batteryPct: null,
    }));
    for (const [field, value] of [['gasPpm', 10], ['batteryPct', 0]]) {
      expectContractError(
        () => validateCanonicalTelemetry({ ...payload(), [field]: value }),
        TELEMETRY_ERROR_CODES.unavailableField,
        field,
      );
    }
    expectContractError(
      () => validateCanonicalTelemetry({
        ...payload(),
        location: { latitude: 0, longitude: 0 },
      }),
      TELEMETRY_ERROR_CODES.invalidValue,
      'location',
    );
  });

  test('requires schema 1.0, warming-up gas, and unevaluated fall state', () => {
    expectContractError(
      () => validateCanonicalTelemetry(payload({ schemaVersion: '1.1' })),
      TELEMETRY_ERROR_CODES.unsupportedSchema,
      'schemaVersion',
    );
    expectContractError(
      () => validateCanonicalTelemetry(payload({ gasWarmUp: false })),
      TELEMETRY_ERROR_CODES.invalidValue,
      'gasWarmUp',
    );
    expectContractError(
      () => validateCanonicalTelemetry(payload({ fallStatus: 'normal' })),
      TELEMETRY_ERROR_CODES.invalidValue,
      'fallStatus',
    );
  });

  test('validates identifiers, firmware version, and timestamps', () => {
    for (const [field, value] of [
      ['eventId', 'bad/id'],
      ['helmetId', ''],
      ['firmwareVersion', 'bad version'],
      ['deviceTimestamp', 1.5],
    ]) {
      expectContractError(
        () => validateCanonicalTelemetry(payload({ [field]: value })),
        field === 'deviceTimestamp'
          ? TELEMETRY_ERROR_CODES.invalidType
          : TELEMETRY_ERROR_CODES.invalidValue,
        field,
      );
    }
  });

  test('enforces DHT22 ranges and finite values', () => {
    for (const [field, value] of [
      ['temperatureC', -40.01],
      ['temperatureC', 80.01],
      ['humidityPct', -0.01],
      ['humidityPct', 100.01],
      ['heatIndexC', Number.NaN],
      ['temperatureC', Number.POSITIVE_INFINITY],
    ]) {
      expectContractError(
        () => validateCanonicalTelemetry(payload({ [field]: value })),
        Number.isFinite(value)
          ? TELEMETRY_ERROR_CODES.invalidRange
          : TELEMETRY_ERROR_CODES.invalidType,
        field,
      );
    }
    assert.doesNotThrow(() => validateCanonicalTelemetry(payload({
      temperatureC: -40,
      humidityPct: 0,
      heatIndexC: -100,
    })));
    assert.doesNotThrow(() => validateCanonicalTelemetry(payload({
      temperatureC: 80,
      humidityPct: 100,
      heatIndexC: 250,
    })));
  });

  test('enforces MPU configured ranges and complete measurement faults', () => {
    for (const [field, value] of [
      ['accelXG', -2.01],
      ['accelZG', 2.01],
      ['gyroXDegreesPerSecond', -250.01],
      ['gyroZDegreesPerSecond', 250.01],
    ]) {
      expectContractError(
        () => validateCanonicalTelemetry(payload({ [field]: value })),
        TELEMETRY_ERROR_CODES.invalidRange,
        field,
      );
    }
    const missingAxis = payload();
    delete missingAxis.accelXG;
    expectContractError(
      () => validateCanonicalTelemetry(missingAxis),
      TELEMETRY_ERROR_CODES.missingSensorFault,
      'sensorFaults',
    );
    assert.doesNotThrow(() => validateCanonicalTelemetry({
      ...missingAxis,
      sensorFaults: [...requiredFaults, 'mpuReadFailed'],
    }));
    assert.doesNotThrow(() => validateCanonicalTelemetry(payload({
      accelXG: -2,
      accelYG: 2,
      gyroXDegreesPerSecond: -250,
      gyroYDegreesPerSecond: 250,
    })));
  });

  test('enforces MQ-7 diagnostic types and transport ranges', () => {
    for (const [field, value, code] of [
      ['gasRaw', 1.2, TELEMETRY_ERROR_CODES.invalidType],
      ['gasRaw', 4096, TELEMETRY_ERROR_CODES.invalidRange],
      ['gasAdcVoltage', 3.61, TELEMETRY_ERROR_CODES.invalidRange],
      ['gasSensorVoltage', 5.51, TELEMETRY_ERROR_CODES.invalidRange],
      ['gasSensorVoltage', Number.NaN, TELEMETRY_ERROR_CODES.invalidType],
      ['gasDigitalThreshold', 0, TELEMETRY_ERROR_CODES.invalidType],
    ]) {
      expectContractError(
        () => validateCanonicalTelemetry(payload({ [field]: value })),
        code,
        field,
      );
    }
    assert.doesNotThrow(() => validateCanonicalTelemetry(payload({
      gasRaw: 0,
      gasAdcVoltage: 0,
      gasSensorVoltage: 0,
    })));
    assert.doesNotThrow(() => validateCanonicalTelemetry(payload({
      gasRaw: 4095,
      gasAdcVoltage: 3.6,
      gasSensorVoltage: 5.5,
    })));
  });

  test('requires explicit faults for missing DHT, MPU, and MQ-7 groups', () => {
    const noDht = payload();
    delete noDht.temperatureC;
    delete noDht.humidityPct;
    delete noDht.heatIndexC;
    expectContractError(
      () => validateCanonicalTelemetry(noDht),
      TELEMETRY_ERROR_CODES.missingSensorFault,
    );

    const noMpu = payload();
    for (const field of [
      'accelXG', 'accelYG', 'accelZG',
      'gyroXDegreesPerSecond', 'gyroYDegreesPerSecond', 'gyroZDegreesPerSecond',
    ]) delete noMpu[field];
    expectContractError(
      () => validateCanonicalTelemetry(noMpu),
      TELEMETRY_ERROR_CODES.missingSensorFault,
    );

    const noMq7 = payload();
    for (const field of [
      'gasRaw', 'gasAdcVoltage', 'gasSensorVoltage', 'gasDigitalThreshold',
    ]) delete noMq7[field];
    expectContractError(
      () => validateCanonicalTelemetry(noMq7),
      TELEMETRY_ERROR_CODES.missingSensorFault,
    );

    assert.doesNotThrow(() => validateCanonicalTelemetry({
      ...noDht,
      sensorFaults: [...requiredFaults, 'dhtReadFailed'],
    }));
    assert.doesNotThrow(() => validateCanonicalTelemetry({
      ...noMpu,
      sensorFaults: [...requiredFaults, 'mpuReadFailed'],
    }));
    assert.doesNotThrow(() => validateCanonicalTelemetry({
      ...noMq7,
      sensorFaults: [...requiredFaults, 'mq7ReadFailed'],
    }));
  });

  test('validates every fault enum, duplicates, and required contract faults', () => {
    expectContractError(
      () => validateCanonicalTelemetry(payload({ sensorFaults: ['unknownFault'] })),
      TELEMETRY_ERROR_CODES.invalidValue,
      'sensorFaults',
    );
    expectContractError(
      () => validateCanonicalTelemetry(payload({
        sensorFaults: [...requiredFaults, 'gpsUnavailable'],
      })),
      TELEMETRY_ERROR_CODES.invalidValue,
      'sensorFaults',
    );
    for (const missing of requiredFaults) {
      expectContractError(
        () => validateCanonicalTelemetry(payload({
          sensorFaults: requiredFaults.filter((fault) => fault !== missing),
        })),
        TELEMETRY_ERROR_CODES.missingSensorFault,
        'sensorFaults',
      );
    }
  });
});

describe('canonicalization, hashing, and safe state', () => {
  test('field order and fault order produce identical canonical JSON and hash', () => {
    const original = payload();
    const reordered = Object.fromEntries(Object.entries(original).reverse());
    reordered.sensorFaults = [...requiredFaults].reverse();
    const left = validateCanonicalTelemetry(original);
    const right = validateCanonicalTelemetry(reordered);
    assert.equal(canonicalizeTelemetryPayload(left), canonicalizeTelemetryPayload(right));
    assert.equal(semanticTelemetryHash(left), semanticTelemetryHash(right));
  });

  test('null unavailable values normalize to the same semantic payload as absence', () => {
    const absent = validateCanonicalTelemetry(payload());
    const explicitNull = validateCanonicalTelemetry({
      ...payload(), gasPpm: null, location: null, batteryPct: null,
    });
    assert.equal(semanticTelemetryHash(absent), semanticTelemetryHash(explicitNull));
  });

  test('different sensor data with the same event ID has a different hash', () => {
    const first = validateCanonicalTelemetry(payload({ temperatureC: 25 }));
    const changed = validateCanonicalTelemetry(payload({ temperatureC: 26 }));
    assert.equal(first.eventId, changed.eventId);
    assert.notEqual(semanticTelemetryHash(first), semanticTelemetryHash(changed));
  });

  test('only the validated client contract participates in semantic hashing', () => {
    const validated = validateCanonicalTelemetry(payload());
    const hash = semanticTelemetryHash(validated);
    const first = buildUnassessedTelemetryRecord(validated, {
      serverReceivedAt: 1_800_000_000_100,
      connectivity: 'online',
    });
    const second = buildUnassessedTelemetryRecord(validated, {
      serverReceivedAt: 1_800_000_000_200,
      connectivity: 'degraded',
    });
    assert.equal(semanticTelemetryHashFromBackendRecord(first), hash);
    assert.equal(semanticTelemetryHashFromBackendRecord(second), hash);
    assert.equal(first.severity, 'unassessed');
    assert.equal(second.severity, 'unassessed');
    assert.deepEqual(
      TELEMETRY_BACKEND_OWNED_FIELDS,
      ['serverReceivedAt', 'severity', 'connectivity'],
    );
    expectContractError(
      () => semanticTelemetryHashFromBackendRecord({ ...first, siteId: 'site_1' }),
      TELEMETRY_ERROR_CODES.unknownField,
      'siteId',
    );
  });

  test('canonicalization rejects objects that did not pass validation', () => {
    expectContractError(
      () => canonicalizeTelemetryPayload(payload()),
      TELEMETRY_ERROR_CODES.invalidValidatedPayload,
    );
  });

  test('unassessed projection is never safe and cannot clear a hazard', () => {
    const validated = validateCanonicalTelemetry(payload());
    const record = buildUnassessedTelemetryRecord(validated, {
      serverReceivedAt: 1_800_000_000_000,
    });
    assert.equal(record.severity, 'unassessed');
    assert.notEqual(record.severity, 'safe');
    assert.equal(
      isHazardCleared(
        { alertType: 'temperature', severity: 'critical' },
        record,
        1_800_000_000_100,
      ),
      false,
    );
    assert.throws(
      () => validateAlertPayload({
        schemaVersion: '1.0',
        eventId: record.eventId,
        helmetId: record.helmetId,
        alertType: 'temperature',
        severity: record.severity,
        sensorValue: record.temperatureC,
        threshold: 40,
        unit: 'degreesCelsius',
        evidence: { temperatureC: record.temperatureC },
        deviceTimestamp: record.deviceTimestamp,
      }, {
        claimedHelmetId: record.helmetId,
        now: record.deviceTimestamp,
      }),
      /unsupported value/,
    );
  });

  test('safe errors contain codes and field names but no payload values', () => {
    try {
      validateCanonicalTelemetry(payload({ gasRaw: 5000 }));
      assert.fail('Expected validation to fail.');
    } catch (error) {
      assert.equal(error instanceof TelemetryContractError, true);
      assert.deepEqual(error.toJSON(), {
        code: 'INVALID_RANGE',
        message: 'Telemetry measurement is outside its allowed range.',
        field: 'gasRaw',
      });
      assert.equal(JSON.stringify(error.toJSON()).includes('5000'), false);
      assert.equal('source' in error, false);
      assert.equal('payload' in error, false);
    }
  });
});
