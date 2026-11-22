export const ASSESSMENT_SCHEMA_VERSION = '1.0';

export const ASSESSMENT_REASON_CODES = Object.freeze([
  'FALL_DETECTED',
  'FALL_MODEL_UNAVAILABLE',
  'GAS_SMOKE',
  'GAS_MIXTURE',
  'GAS_PERFUME',
  'GAS_NO_GAS',
  'GAS_MODEL_UNAVAILABLE',
  'GAS_INPUT_OUT_OF_DISTRIBUTION',
  'GAS_SENSOR_WARMING',
  'GAS_BASELINE_LEARNING',
  'GAS_RISE_WARNING',
  'GAS_RISE_CRITICAL',
  'TEMPERATURE_WARNING',
  'TEMPERATURE_CRITICAL',
  'HUMIDITY_WARNING',
  'HUMIDITY_CRITICAL',
  'HEAT_INDEX_WARNING',
  'HEAT_INDEX_CRITICAL',
  'SENSOR_FAULT',
  'INPUT_STALE',
]);

export const ASSESSMENT_RECOMMENDATION_CODES = Object.freeze([
  'CHECK_WORKER_IMMEDIATELY',
  'FOLLOW_SITE_EMERGENCY_PROTOCOL',
  'MOVE_TO_FRESH_AIR',
  'INVESTIGATE_GAS_SOURCE',
  'VENTILATE_AREA_IF_SAFE',
  'MONITOR_ENVIRONMENT',
  'VERIFY_SENSORS',
  'ALLOW_GAS_SENSOR_WARMUP',
  'HYDRATE_AND_COOL_DOWN',
  'MOVE_TO_SAFE_TEMPERATURE',
  'NO_IMMEDIATE_ACTION',
]);

const topLevelFields = Object.freeze([
  'schemaVersion',
  'assessmentId',
  'eventId',
  'helmetId',
  'sourceSchemaVersion',
  'deviceTimestamp',
  'sourceServerReceivedAt',
  'assessedAt',
  'modelBundleVersion',
  'gasInputMode',
  'mq7Ratio',
  'mq135Ratio',
  'gasThresholdRisk',
  'gasThresholdConsecutive',
  'fall',
  'gas',
  'environment',
  'overallRisk',
  'reasonCodes',
  'recommendationCodes',
]);

const gasClasses = Object.freeze(['Mixture', 'NoGas', 'Perfume', 'Smoke']);
const componentRisks = Object.freeze(['normal', 'warning', 'critical', 'unavailable']);
const overallRisks = Object.freeze(['unknown', 'safe', 'warning', 'critical']);

export class AssessmentContractError extends Error {
  constructor(code, message, field = null) {
    super(message);
    this.name = 'AssessmentContractError';
    this.code = code;
    this.field = field;
  }

  toJSON() {
    return {
      code: this.code,
      message: this.message,
      ...(this.field === null ? {} : { field: this.field }),
    };
  }
}

function fail(code, message, field = null) {
  throw new AssessmentContractError(code, message, field);
}

function isRecord(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function requireRecord(value, field) {
  if (!isRecord(value)) fail('INVALID_TYPE', `${field} must be an object.`, field);
  return value;
}

function requireExactFields(value, fields, field) {
  const expected = new Set(fields);
  for (const key of Object.keys(value)) {
    if (!expected.has(key)) fail('UNKNOWN_FIELD', `${field} contains an unknown field.`, `${field}.${key}`);
  }
  for (const key of fields) {
    if (!Object.hasOwn(value, key)) {
      fail('MISSING_FIELD', `${field} is missing a required field.`, `${field}.${key}`);
    }
  }
}

function requireNullableRatio(value, field) {
  if (value === null) return null;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
    fail('INVALID_RANGE', `${field} must be null or a non-negative number.`, field);
  }
  return value;
}

function requireNonNegativeInteger(value, field) {
  if (!Number.isSafeInteger(value) || value < 0) {
    fail('INVALID_RANGE', `${field} must be a non-negative integer.`, field);
  }
  return value;
}

function requireId(value, field) {
  if (typeof value !== 'string' || value.length > 128 || !/^[A-Za-z0-9_-]+$/.test(value)) {
    fail('INVALID_VALUE', `${field} is invalid.`, field);
  }
  return value;
}

function requireVersion(value, field) {
  if (typeof value !== 'string' || value.length < 1 || value.length > 128 ||
      !/^[A-Za-z0-9][A-Za-z0-9._+-]*$/.test(value)) {
    fail('INVALID_VALUE', `${field} is invalid.`, field);
  }
  return value;
}

function requireTimestamp(value, field) {
  if (!Number.isSafeInteger(value) || value < 0) {
    fail('INVALID_TYPE', `${field} must be a non-negative epoch millisecond integer.`, field);
  }
  return value;
}

function requireProbability(value, field) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 1) {
    fail('INVALID_RANGE', `${field} must be between zero and one.`, field);
  }
  return Object.is(value, -0) ? 0 : value;
}

function requireEnum(value, allowed, field) {
  if (typeof value !== 'string' || !allowed.includes(value)) {
    fail('INVALID_VALUE', `${field} contains an unsupported value.`, field);
  }
  return value;
}

function requireUniqueCodes(value, allowed, field) {
  if (!Array.isArray(value)) fail('INVALID_TYPE', `${field} must be an array.`, field);
  const seen = new Set();
  for (const code of value) {
    if (typeof code !== 'string' || !allowed.includes(code) || seen.has(code)) {
      fail('INVALID_VALUE', `${field} contains an unsupported or duplicate code.`, field);
    }
    seen.add(code);
  }
  return [...seen].sort();
}

function validateFall(value) {
  const input = requireRecord(value, 'fall');
  if (input.status === 'unavailable') {
    requireExactFields(input, ['status'], 'fall');
    return { status: 'unavailable' };
  }
  requireExactFields(
    input,
    ['status', 'probability', 'threshold', 'modelVersion'],
    'fall',
  );
  if (input.status !== 'evaluated') fail('INVALID_VALUE', 'fall.status is unsupported.', 'fall.status');
  return {
    status: 'evaluated',
    probability: requireProbability(input.probability, 'fall.probability'),
    threshold: requireProbability(input.threshold, 'fall.threshold'),
    modelVersion: requireVersion(input.modelVersion, 'fall.modelVersion'),
  };
}

function validateGas(value) {
  const input = requireRecord(value, 'gas');
  if (input.status === 'unavailable') {
    requireExactFields(input, ['status'], 'gas');
    return { status: 'unavailable' };
  }
  requireExactFields(
    input,
    ['status', 'classification', 'confidence', 'probabilities', 'modelVersion', 'outOfDistribution'],
    'gas',
  );
  if (input.status !== 'evaluated') fail('INVALID_VALUE', 'gas.status is unsupported.', 'gas.status');
  const probabilities = requireRecord(input.probabilities, 'gas.probabilities');
  requireExactFields(probabilities, gasClasses, 'gas.probabilities');
  const normalizedProbabilities = Object.fromEntries(
    gasClasses.map((name) => [name, requireProbability(
      probabilities[name],
      `gas.probabilities.${name}`,
    )]),
  );
  const total = Object.values(normalizedProbabilities).reduce((sum, value) => sum + value, 0);
  if (Math.abs(total - 1) > 0.001) {
    fail('INVALID_VALUE', 'gas probabilities must sum to one.', 'gas.probabilities');
  }
  if (typeof input.outOfDistribution !== 'boolean') {
    fail('INVALID_TYPE', 'gas.outOfDistribution must be a boolean.', 'gas.outOfDistribution');
  }
  const classification = requireEnum(input.classification, gasClasses, 'gas.classification');
  const confidence = requireProbability(input.confidence, 'gas.confidence');
  if (Math.abs(normalizedProbabilities[classification] - confidence) > 0.000001 ||
      Object.values(normalizedProbabilities).some((value) => value > confidence)) {
    fail(
      'INVALID_VALUE',
      'gas classification and confidence must match the highest class probability.',
      'gas.confidence',
    );
  }
  return {
    status: 'evaluated',
    classification,
    confidence,
    probabilities: normalizedProbabilities,
    modelVersion: requireVersion(input.modelVersion, 'gas.modelVersion'),
    outOfDistribution: input.outOfDistribution,
  };
}

function validateEnvironment(value) {
  const input = requireRecord(value, 'environment');
  requireExactFields(
    input,
    ['status', 'temperatureRisk', 'humidityRisk', 'heatIndexRisk'],
    'environment',
  );
  const output = {
    status: requireEnum(input.status, ['evaluated', 'unavailable'], 'environment.status'),
    temperatureRisk: requireEnum(input.temperatureRisk, componentRisks, 'environment.temperatureRisk'),
    humidityRisk: requireEnum(input.humidityRisk, componentRisks, 'environment.humidityRisk'),
    heatIndexRisk: requireEnum(input.heatIndexRisk, componentRisks, 'environment.heatIndexRisk'),
  };
  const hasUnavailable = [
    output.temperatureRisk,
    output.humidityRisk,
    output.heatIndexRisk,
  ].includes('unavailable');
  if ((output.status === 'evaluated' && hasUnavailable) ||
      (output.status === 'unavailable' && !hasUnavailable)) {
    fail(
      'INVALID_VALUE',
      'environment.status must agree with component availability.',
      'environment.status',
    );
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

export function validateSafetyAssessment(value) {
  const input = requireRecord(value, 'assessment');
  requireExactFields(input, topLevelFields, 'assessment');
  if (input.schemaVersion !== ASSESSMENT_SCHEMA_VERSION) {
    fail('UNSUPPORTED_SCHEMA', 'Assessment schema version is unsupported.', 'schemaVersion');
  }
  const eventId = requireId(input.eventId, 'eventId');
  const assessmentId = requireId(input.assessmentId, 'assessmentId');
  if (assessmentId !== eventId) {
    fail('INVALID_VALUE', 'assessmentId must equal the source eventId.', 'assessmentId');
  }
  if (!['1.0', '2.0'].includes(input.sourceSchemaVersion)) {
    fail('INVALID_VALUE', 'sourceSchemaVersion is unsupported.', 'sourceSchemaVersion');
  }
  const sourceServerReceivedAt = requireTimestamp(
    input.sourceServerReceivedAt,
    'sourceServerReceivedAt',
  );
  const assessedAt = requireTimestamp(input.assessedAt, 'assessedAt');
  if (assessedAt < sourceServerReceivedAt) {
    fail('INVALID_VALUE', 'assessedAt cannot precede sourceServerReceivedAt.', 'assessedAt');
  }
  const output = {
    schemaVersion: ASSESSMENT_SCHEMA_VERSION,
    assessmentId,
    eventId,
    helmetId: requireId(input.helmetId, 'helmetId'),
    sourceSchemaVersion: input.sourceSchemaVersion,
    deviceTimestamp: requireTimestamp(input.deviceTimestamp, 'deviceTimestamp'),
    sourceServerReceivedAt,
    assessedAt,
    modelBundleVersion: requireVersion(input.modelBundleVersion, 'modelBundleVersion'),
    gasInputMode: requireEnum(
      input.gasInputMode,
      ['baselineLearning', 'baselineMapped'],
      'gasInputMode',
    ),
    mq7Ratio: requireNullableRatio(input.mq7Ratio, 'mq7Ratio'),
    mq135Ratio: requireNullableRatio(input.mq135Ratio, 'mq135Ratio'),
    gasThresholdRisk: requireEnum(
      input.gasThresholdRisk,
      ['unknown', 'safe', 'warning', 'critical'],
      'gasThresholdRisk',
    ),
    gasThresholdConsecutive: requireNonNegativeInteger(
      input.gasThresholdConsecutive,
      'gasThresholdConsecutive',
    ),
    fall: validateFall(input.fall),
    gas: validateGas(input.gas),
    environment: validateEnvironment(input.environment),
    overallRisk: requireEnum(input.overallRisk, overallRisks, 'overallRisk'),
    reasonCodes: requireUniqueCodes(input.reasonCodes, ASSESSMENT_REASON_CODES, 'reasonCodes'),
    recommendationCodes: requireUniqueCodes(
      input.recommendationCodes,
      ASSESSMENT_RECOMMENDATION_CODES,
      'recommendationCodes',
    ),
  };

  if ((output.gasInputMode === 'baselineLearning' &&
       (output.mq7Ratio !== null || output.mq135Ratio !== null ||
        output.gasThresholdRisk !== 'unknown' || output.gas.status !== 'unavailable')) ||
      (output.gasInputMode === 'baselineMapped' &&
       (output.mq7Ratio === null || output.mq135Ratio === null ||
        output.gasThresholdRisk === 'unknown'))) {
    fail(
      'INVALID_VALUE',
      'Gas baseline mode must agree with ratios and threshold risk.',
      'gasInputMode',
    );
  }
  if ((output.gasThresholdRisk === 'critical' && output.overallRisk !== 'critical') ||
      (output.gasThresholdRisk === 'warning' &&
       !['warning', 'critical'].includes(output.overallRisk))) {
    fail(
      'INVALID_VALUE',
      'Overall risk must include the baseline threshold risk.',
      'overallRisk',
    );
  }

  if (output.overallRisk === 'safe' &&
      (output.fall.status !== 'evaluated' ||
       output.gas.status !== 'evaluated' ||
       output.gas.outOfDistribution ||
       output.environment.status !== 'evaluated' ||
       Object.values(output.environment).includes('unavailable'))) {
    fail(
      'UNSAFE_SAFE_CLASSIFICATION',
      'Safe cannot be reported while an assessment input is unavailable or out of distribution.',
      'overallRisk',
    );
  }
  return deepFreeze(output);
}
