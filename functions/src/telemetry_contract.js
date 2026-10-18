import { createHash } from 'node:crypto';

export const TELEMETRY_SCHEMA_VERSION = '1.0';
export const TELEMETRY_SCHEMA_VERSION_V2 = '2.0';
export const TELEMETRY_SCHEMA_VERSIONS = Object.freeze([
  TELEMETRY_SCHEMA_VERSION,
  TELEMETRY_SCHEMA_VERSION_V2,
]);
export const TELEMETRY_MAX_PAYLOAD_BYTES = 8 * 1024;

export const TELEMETRY_FAULTS = Object.freeze([
  'mpuReadFailed',
  'dhtReadFailed',
  'mq7ReadFailed',
  'mq7Uncalibrated',
  'mq7HeaterStateUnknown',
  'mq135ReadFailed',
  'mq135Uncalibrated',
  'mq135HeaterStateUnknown',
  'fallWindowUnavailable',
  'gpsUnavailable',
  'batteryUnavailable',
]);

export const TELEMETRY_ERROR_CODES = Object.freeze({
  invalidPayload: 'INVALID_PAYLOAD',
  payloadTooLarge: 'PAYLOAD_TOO_LARGE',
  unknownField: 'UNKNOWN_FIELD',
  missingField: 'MISSING_FIELD',
  invalidType: 'INVALID_TYPE',
  invalidValue: 'INVALID_VALUE',
  invalidRange: 'INVALID_RANGE',
  unsupportedSchema: 'UNSUPPORTED_SCHEMA',
  unavailableField: 'UNAVAILABLE_FIELD',
  backendOwnedField: 'BACKEND_OWNED_FIELD',
  missingSensorFault: 'MISSING_SENSOR_FAULT',
  invalidValidatedPayload: 'INVALID_VALIDATED_PAYLOAD',
});

const commonRequiredFields = Object.freeze([
  'schemaVersion',
  'eventId',
  'helmetId',
  'deviceTimestamp',
  'firmwareVersion',
  'sensorFaults',
]);

const v1RequiredFields = Object.freeze([
  ...commonRequiredFields,
  'gasWarmUp',
  'fallStatus',
]);

const v2RequiredFields = Object.freeze([
  ...commonRequiredFields,
  'mq7WarmUp',
  'mq135WarmUp',
]);

export const FALL_FEATURE_FIELDS = Object.freeze([
  'acc_mean',
  'acc_std',
  'acc_min',
  'acc_max',
  'gyro_mean',
  'gyro_std',
  'gyro_max',
  'jerk_mean',
  'jerk_max',
]);

const optionalMeasurementFields = Object.freeze([
  'temperatureC',
  'humidityPct',
  'heatIndexC',
  'gasPpm',
  'gasRaw',
  'gasAdcVoltage',
  'gasSensorVoltage',
  'gasDigitalThreshold',
  'accelXG',
  'accelYG',
  'accelZG',
  'gyroXDegreesPerSecond',
  'gyroYDegreesPerSecond',
  'gyroZDegreesPerSecond',
  'location',
  'batteryPct',
  'mq7Raw',
  'mq135Raw',
  'mq7WarmUp',
  'mq135WarmUp',
  'fallFeatures',
  'samplingRateHz',
  'windowSamples',
  'windowEndTimestamp',
]);

const backendOwnedFields = Object.freeze([
  'serverReceivedAt',
  'severity',
  'connectivity',
]);

const allowedFields = new Set([
  ...v1RequiredFields,
  ...v2RequiredFields,
  ...optionalMeasurementFields,
]);
const backendOwnedFieldSet = new Set(backendOwnedFields);
const faultSet = new Set(TELEMETRY_FAULTS);
const validatedPayloadMarker = Symbol('validatedCanonicalTelemetry');

const requiredContractFaults = Object.freeze([
  'mq7Uncalibrated',
  'mq7HeaterStateUnknown',
  'gpsUnavailable',
  'batteryUnavailable',
]);

export class TelemetryContractError extends Error {
  constructor(code, message, { field = null, httpStatus = 400 } = {}) {
    super(message);
    this.name = 'TelemetryContractError';
    this.code = code;
    this.field = field;
    this.httpStatus = httpStatus;
  }

  toJSON() {
    return {
      code: this.code,
      message: this.message,
      ...(this.field === null ? {} : { field: this.field }),
    };
  }
}

function fail(code, message, field = null, httpStatus = 400) {
  throw new TelemetryContractError(code, message, { field, httpStatus });
}

function isRecord(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function requireRecord(value) {
  if (!isRecord(value)) {
    fail(
      TELEMETRY_ERROR_CODES.invalidPayload,
      'Telemetry payload must be a JSON object.',
    );
  }
  return value;
}

function serializedPayload(value) {
  try {
    const serialized = JSON.stringify(value);
    if (serialized === undefined) {
      fail(
        TELEMETRY_ERROR_CODES.invalidPayload,
        'Telemetry payload cannot be serialized as JSON.',
      );
    }
    return serialized;
  } catch {
    fail(
      TELEMETRY_ERROR_CODES.invalidPayload,
      'Telemetry payload cannot be serialized as JSON.',
    );
  }
}

export function telemetryPayloadByteLength(payload) {
  if (typeof payload === 'string') return Buffer.byteLength(payload, 'utf8');
  if (Buffer.isBuffer(payload) || payload instanceof Uint8Array) {
    return payload.byteLength;
  }
  return Buffer.byteLength(serializedPayload(payload), 'utf8');
}

export function enforceTelemetryPayloadSize(
  payload,
  maxBytes = TELEMETRY_MAX_PAYLOAD_BYTES,
) {
  if (!Number.isSafeInteger(maxBytes) || maxBytes <= 0) {
    throw new TypeError('maxBytes must be a positive safe integer.');
  }
  const byteLength = telemetryPayloadByteLength(payload);
  if (byteLength > maxBytes) {
    fail(
      TELEMETRY_ERROR_CODES.payloadTooLarge,
      'Telemetry payload exceeds the configured size limit.',
      null,
      413,
    );
  }
  return byteLength;
}

function rejectUnknownAndBackendFields(payload) {
  for (const key of Object.keys(payload)) {
    if (backendOwnedFieldSet.has(key)) {
      fail(
        TELEMETRY_ERROR_CODES.backendOwnedField,
        'Telemetry contains a backend-owned field.',
        key,
      );
    }
    if (!allowedFields.has(key)) {
      fail(
        TELEMETRY_ERROR_CODES.unknownField,
        'Telemetry contains an unknown field.',
        key,
      );
    }
  }
}

function requireFields(payload, fields) {
  for (const field of fields) {
    if (!Object.hasOwn(payload, field) || payload[field] === null) {
      fail(
        TELEMETRY_ERROR_CODES.missingField,
        'Telemetry is missing a required field.',
        field,
      );
    }
  }
}

function requireSafeId(value, field, maxLength = 128) {
  if (
    typeof value !== 'string' ||
    value.length > maxLength ||
    !/^[A-Za-z0-9_-]+$/.test(value)
  ) {
    fail(
      TELEMETRY_ERROR_CODES.invalidValue,
      'Telemetry identifier is invalid.',
      field,
    );
  }
  return value;
}

function requireFirmwareVersion(value) {
  if (
    typeof value !== 'string' ||
    value.length < 1 ||
    value.length > 64 ||
    !/^[A-Za-z0-9][A-Za-z0-9._+-]*$/.test(value)
  ) {
    fail(
      TELEMETRY_ERROR_CODES.invalidValue,
      'Firmware version is invalid.',
      'firmwareVersion',
    );
  }
  return value;
}

function requireFiniteNumber(value, field, { min, max } = {}) {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    fail(
      TELEMETRY_ERROR_CODES.invalidType,
      'Telemetry measurement must be a finite number.',
      field,
    );
  }
  if ((min !== undefined && value < min) || (max !== undefined && value > max)) {
    fail(
      TELEMETRY_ERROR_CODES.invalidRange,
      'Telemetry measurement is outside its allowed range.',
      field,
    );
  }
  return Object.is(value, -0) ? 0 : value;
}

function optionalFiniteNumber(payload, output, field, bounds) {
  if (!Object.hasOwn(payload, field) || payload[field] === null) return;
  output[field] = requireFiniteNumber(payload[field], field, bounds);
}

function optionalBoolean(payload, output, field) {
  if (!Object.hasOwn(payload, field) || payload[field] === null) return;
  if (typeof payload[field] !== 'boolean') {
    fail(
      TELEMETRY_ERROR_CODES.invalidType,
      'Telemetry diagnostic flag must be a boolean.',
      field,
    );
  }
  output[field] = payload[field];
}

function normalizeFaults(value, requiredFaults = requiredContractFaults) {
  if (!Array.isArray(value)) {
    fail(
      TELEMETRY_ERROR_CODES.invalidType,
      'sensorFaults must be an array.',
      'sensorFaults',
    );
  }
  const seen = new Set();
  for (const fault of value) {
    if (typeof fault !== 'string' || !faultSet.has(fault)) {
      fail(
        TELEMETRY_ERROR_CODES.invalidValue,
        'sensorFaults contains an unsupported value.',
        'sensorFaults',
      );
    }
    if (seen.has(fault)) {
      fail(
        TELEMETRY_ERROR_CODES.invalidValue,
        'sensorFaults cannot contain duplicate values.',
        'sensorFaults',
      );
    }
    seen.add(fault);
  }
  for (const fault of requiredFaults) {
    if (!seen.has(fault)) {
      fail(
        TELEMETRY_ERROR_CODES.missingSensorFault,
        'Telemetry is missing a required unavailable-sensor fault.',
        'sensorFaults',
      );
    }
  }
  return [...seen].sort();
}

function requireGroupFault(output, fields, fault) {
  if (fields.some((field) => !Object.hasOwn(output, field))) {
    if (!output.sensorFaults.includes(fault)) {
      fail(
        TELEMETRY_ERROR_CODES.missingSensorFault,
        'A missing sensor measurement requires an explicit fault.',
        'sensorFaults',
      );
    }
  }
}

function validateUnavailableFields(payload) {
  for (const field of ['gasPpm', 'batteryPct']) {
    if (Object.hasOwn(payload, field) && payload[field] !== null) {
      fail(
        TELEMETRY_ERROR_CODES.unavailableField,
        'Telemetry field is unavailable for the current hardware contract.',
        field,
      );
    }
  }

  if (Object.hasOwn(payload, 'location') && payload.location !== null) {
    if (
      isRecord(payload.location) &&
      payload.location.latitude === 0 &&
      payload.location.longitude === 0
    ) {
      fail(
        TELEMETRY_ERROR_CODES.invalidValue,
        'The invalid GPS sentinel is not allowed.',
        'location',
      );
    }
    fail(
      TELEMETRY_ERROR_CODES.unavailableField,
      'GPS is unavailable for the current hardware contract.',
      'location',
    );
  }
}

function validateSchemaSpecificFields(payload) {
  const v1Only = ['gasWarmUp', 'fallStatus', 'gasRaw', 'gasAdcVoltage',
    'gasSensorVoltage', 'gasDigitalThreshold'];
  const v2Only = ['mq7Raw', 'mq135Raw', 'mq7WarmUp', 'mq135WarmUp',
    'fallFeatures', 'samplingRateHz', 'windowSamples', 'windowEndTimestamp'];
  const disallowed = payload.schemaVersion === TELEMETRY_SCHEMA_VERSION
    ? v2Only
    : v1Only;
  for (const field of disallowed) {
    if (Object.hasOwn(payload, field)) {
      fail(
        TELEMETRY_ERROR_CODES.unknownField,
        'Telemetry field is not part of the selected schema version.',
        field,
      );
    }
  }
}

function validateRawAdc(payload, output, field) {
  if (!Object.hasOwn(payload, field) || payload[field] === null) return;
  if (!Number.isInteger(payload[field])) {
    fail(
      TELEMETRY_ERROR_CODES.invalidType,
      'Raw gas sensor readings must be integers.',
      field,
    );
  }
  output[field] = requireFiniteNumber(payload[field], field, { min: 0, max: 4095 });
}

function validateFallFeatures(value) {
  if (!isRecord(value)) {
    fail(
      TELEMETRY_ERROR_CODES.invalidType,
      'fallFeatures must be an object.',
      'fallFeatures',
    );
  }
  for (const key of Object.keys(value)) {
    if (!FALL_FEATURE_FIELDS.includes(key)) {
      fail(
        TELEMETRY_ERROR_CODES.unknownField,
        'fallFeatures contains an unknown field.',
        `fallFeatures.${key}`,
      );
    }
  }
  const output = {};
  for (const field of FALL_FEATURE_FIELDS) {
    if (!Object.hasOwn(value, field) || value[field] === null) {
      fail(
        TELEMETRY_ERROR_CODES.missingField,
        'fallFeatures is missing a required field.',
        `fallFeatures.${field}`,
      );
    }
    output[field] = requireFiniteNumber(value[field], `fallFeatures.${field}`, {
      min: 0,
      max: 100000,
    });
  }
  return output;
}

function deepFreeze(value) {
  if (value !== null && typeof value === 'object' && !Object.isFrozen(value)) {
    for (const child of Object.values(value)) deepFreeze(child);
    Object.freeze(value);
  }
  return value;
}

export function validateCanonicalTelemetry(payload, { rawPayload } = {}) {
  enforceTelemetryPayloadSize(rawPayload ?? payload);
  const input = requireRecord(payload);
  rejectUnknownAndBackendFields(input);
  requireFields(input, commonRequiredFields);
  if (!TELEMETRY_SCHEMA_VERSIONS.includes(input.schemaVersion)) {
    fail(
      TELEMETRY_ERROR_CODES.unsupportedSchema,
      'Telemetry schema version is unsupported.',
      'schemaVersion',
    );
  }
  validateSchemaSpecificFields(input);
  requireFields(
    input,
    input.schemaVersion === TELEMETRY_SCHEMA_VERSION
      ? v1RequiredFields
      : v2RequiredFields,
  );
  validateUnavailableFields(input);

  if (input.schemaVersion === TELEMETRY_SCHEMA_VERSION && input.gasWarmUp !== true) {
    fail(
      TELEMETRY_ERROR_CODES.invalidValue,
      'gasWarmUp must be true for the current hardware contract.',
      'gasWarmUp',
    );
  }
  if (input.schemaVersion === TELEMETRY_SCHEMA_VERSION &&
      input.fallStatus !== 'notEvaluated') {
    fail(
      TELEMETRY_ERROR_CODES.invalidValue,
      'fallStatus must remain notEvaluated.',
      'fallStatus',
    );
  }
  if (!Number.isSafeInteger(input.deviceTimestamp) || input.deviceTimestamp < 0) {
    fail(
      TELEMETRY_ERROR_CODES.invalidType,
      'deviceTimestamp must be a non-negative UTC epoch millisecond integer.',
      'deviceTimestamp',
    );
  }

  const output = {
    schemaVersion: input.schemaVersion,
    eventId: requireSafeId(input.eventId, 'eventId'),
    helmetId: requireSafeId(input.helmetId, 'helmetId'),
    deviceTimestamp: input.deviceTimestamp,
    firmwareVersion: requireFirmwareVersion(input.firmwareVersion),
    sensorFaults: normalizeFaults(
      input.sensorFaults,
      input.schemaVersion === TELEMETRY_SCHEMA_VERSION
        ? requiredContractFaults
        : ['gpsUnavailable', 'batteryUnavailable'],
    ),
  };

  if (input.schemaVersion === TELEMETRY_SCHEMA_VERSION) {
    output.gasWarmUp = true;
    output.fallStatus = 'notEvaluated';
  } else {
    optionalBoolean(input, output, 'mq7WarmUp');
    optionalBoolean(input, output, 'mq135WarmUp');
    const fallWindowFields = [
      'fallFeatures',
      'samplingRateHz',
      'windowSamples',
      'windowEndTimestamp',
    ];
    const presentFallWindowFields = fallWindowFields.filter((field) =>
      Object.hasOwn(input, field) && input[field] !== null);
    if (presentFallWindowFields.length === 0) {
      if (!output.sensorFaults.includes('mpuReadFailed') &&
          !output.sensorFaults.includes('fallWindowUnavailable')) {
        fail(
          TELEMETRY_ERROR_CODES.missingSensorFault,
          'A missing fall feature window requires an explicit fault.',
          'sensorFaults',
        );
      }
    } else if (presentFallWindowFields.length !== fallWindowFields.length) {
      fail(
        TELEMETRY_ERROR_CODES.missingField,
        'A fall feature window must include all window fields.',
        fallWindowFields.find((field) => !presentFallWindowFields.includes(field)),
      );
    } else if (input.samplingRateHz !== 50) {
      fail(
        TELEMETRY_ERROR_CODES.invalidValue,
        'samplingRateHz must match the approved 50 Hz model contract.',
        'samplingRateHz',
      );
    } else if (input.windowSamples !== 100) {
      fail(
        TELEMETRY_ERROR_CODES.invalidValue,
        'windowSamples must match the approved 100-sample model contract.',
        'windowSamples',
      );
    } else if (!Number.isSafeInteger(input.windowEndTimestamp) ||
        input.windowEndTimestamp < 0 ||
        input.windowEndTimestamp > input.deviceTimestamp) {
      fail(
        TELEMETRY_ERROR_CODES.invalidValue,
        'windowEndTimestamp must be a non-negative epoch millisecond at or before deviceTimestamp.',
        'windowEndTimestamp',
      );
    } else {
      output.fallFeatures = validateFallFeatures(input.fallFeatures);
      output.samplingRateHz = 50;
      output.windowSamples = 100;
      output.windowEndTimestamp = input.windowEndTimestamp;
    }
    validateRawAdc(input, output, 'mq7Raw');
    validateRawAdc(input, output, 'mq135Raw');
  }

  optionalFiniteNumber(input, output, 'temperatureC', { min: -40, max: 80 });
  optionalFiniteNumber(input, output, 'humidityPct', { min: 0, max: 100 });
  optionalFiniteNumber(input, output, 'heatIndexC', { min: -100, max: 250 });

  if (input.schemaVersion === TELEMETRY_SCHEMA_VERSION &&
      Object.hasOwn(input, 'gasRaw') && input.gasRaw !== null) {
    if (!Number.isInteger(input.gasRaw)) {
      fail(
        TELEMETRY_ERROR_CODES.invalidType,
        'gasRaw must be an integer.',
        'gasRaw',
      );
    }
    output.gasRaw = requireFiniteNumber(input.gasRaw, 'gasRaw', {
      min: 0,
      max: 4095,
    });
  }
  if (input.schemaVersion === TELEMETRY_SCHEMA_VERSION) {
    optionalFiniteNumber(input, output, 'gasAdcVoltage', { min: 0, max: 3.6 });
    optionalFiniteNumber(input, output, 'gasSensorVoltage', { min: 0, max: 5.5 });
    optionalBoolean(input, output, 'gasDigitalThreshold');
  }

  for (const field of ['accelXG', 'accelYG', 'accelZG']) {
    optionalFiniteNumber(input, output, field, { min: -2, max: 2 });
  }
  for (const field of [
    'gyroXDegreesPerSecond',
    'gyroYDegreesPerSecond',
    'gyroZDegreesPerSecond',
  ]) {
    optionalFiniteNumber(input, output, field, { min: -250, max: 250 });
  }

  requireGroupFault(output, ['temperatureC', 'humidityPct'], 'dhtReadFailed');
  requireGroupFault(
    output,
    [
      'accelXG',
      'accelYG',
      'accelZG',
      'gyroXDegreesPerSecond',
      'gyroYDegreesPerSecond',
      'gyroZDegreesPerSecond',
    ],
    'mpuReadFailed',
  );
  if (input.schemaVersion === TELEMETRY_SCHEMA_VERSION &&
    ![
      'gasRaw',
      'gasAdcVoltage',
      'gasSensorVoltage',
      'gasDigitalThreshold',
    ].some((field) => Object.hasOwn(output, field)) &&
    !output.sensorFaults.includes('mq7ReadFailed')
  ) {
    fail(
      TELEMETRY_ERROR_CODES.missingSensorFault,
      'Missing MQ-7 diagnostics require an explicit fault.',
      'sensorFaults',
    );
  }
  if (input.schemaVersion === TELEMETRY_SCHEMA_VERSION_V2) {
    if (!Object.hasOwn(output, 'mq7Raw') &&
        !output.sensorFaults.includes('mq7ReadFailed')) {
      fail(
        TELEMETRY_ERROR_CODES.missingSensorFault,
        'A missing MQ-7 reading requires an explicit fault.',
        'sensorFaults',
      );
    }
    if (!Object.hasOwn(output, 'mq135Raw') &&
        !output.sensorFaults.includes('mq135ReadFailed')) {
      fail(
        TELEMETRY_ERROR_CODES.missingSensorFault,
        'A missing MQ-135 reading requires an explicit fault.',
        'sensorFaults',
      );
    }
  }

  Object.defineProperty(output, validatedPayloadMarker, {
    value: true,
    enumerable: false,
  });
  return deepFreeze(output);
}

function requireValidatedPayload(payload) {
  if (!isRecord(payload) || payload[validatedPayloadMarker] !== true) {
    fail(
      TELEMETRY_ERROR_CODES.invalidValidatedPayload,
      'A validated canonical telemetry payload is required.',
    );
  }
  return payload;
}

function stableJson(value) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stableJson).join(',')}]`;
  return `{${Object.keys(value)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${stableJson(value[key])}`)
    .join(',')}}`;
}

export function canonicalizeTelemetryPayload(validatedPayload) {
  return stableJson(requireValidatedPayload(validatedPayload));
}

export function semanticTelemetryHash(validatedPayload) {
  return createHash('sha256')
    .update(canonicalizeTelemetryPayload(validatedPayload), 'utf8')
    .digest('hex');
}

// This helper is for a trusted backend record after projection, not for client
// validation. It excludes exactly the three backend-owned fields and sends every
// remaining field back through the strict public contract before hashing.
export function semanticTelemetryHashFromBackendRecord(record) {
  const input = requireRecord(record);
  const clientPayload = {};
  for (const [key, value] of Object.entries(input)) {
    if (!backendOwnedFieldSet.has(key)) clientPayload[key] = value;
  }
  return semanticTelemetryHash(validateCanonicalTelemetry(clientPayload));
}

export function buildUnassessedTelemetryRecord(
  validatedPayload,
  { serverReceivedAt, connectivity = 'online' },
) {
  const payload = requireValidatedPayload(validatedPayload);
  if (!Number.isSafeInteger(serverReceivedAt) || serverReceivedAt < 0) {
    throw new TypeError('serverReceivedAt must be a non-negative safe integer.');
  }
  if (!['online', 'degraded', 'offline_buffering'].includes(connectivity)) {
    throw new TypeError('connectivity is unsupported.');
  }
  return deepFreeze({
    ...payload,
    serverReceivedAt,
    connectivity,
    severity: 'unassessed',
  });
}

export const TELEMETRY_BACKEND_OWNED_FIELDS = backendOwnedFields;
