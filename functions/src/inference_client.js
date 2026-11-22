import { validateSafetyAssessment } from './assessment_contract.js';

const MAX_RESPONSE_BYTES = 64 * 1024;

export class InferenceServiceError extends Error {
  constructor(code, message, { retryable = true } = {}) {
    super(message);
    this.name = 'InferenceServiceError';
    this.code = code;
    this.retryable = retryable;
  }
}

function resolveEndpoint(value, allowInsecureLocalhost) {
  const raw = typeof value === 'function' ? value() : value;
  if (typeof raw !== 'string' || raw.trim().length === 0) {
    throw new InferenceServiceError(
      'INFERENCE_NOT_CONFIGURED',
      'The private inference service URL is not configured.',
      { retryable: false },
    );
  }
  let base;
  try {
    base = new URL(raw);
  } catch {
    throw new InferenceServiceError(
      'INFERENCE_URL_INVALID',
      'The private inference service URL is invalid.',
      { retryable: false },
    );
  }
  const local = ['127.0.0.1', 'localhost', '::1'].includes(base.hostname);
  if (base.protocol !== 'https:' && !(allowInsecureLocalhost && local && base.protocol === 'http:')) {
    throw new InferenceServiceError(
      'INFERENCE_URL_INSECURE',
      'The inference service must use HTTPS.',
      { retryable: false },
    );
  }
  if (base.username || base.password || base.search || base.hash) {
    throw new InferenceServiceError(
      'INFERENCE_URL_INVALID',
      'The inference service URL must not contain credentials, query parameters, or fragments.',
      { retryable: false },
    );
  }
  const audience = `${base.protocol}//${base.host}`;
  return { audience, url: new URL('/v1/assess', `${audience}/`).toString() };
}

export function assessmentInputFromTelemetry(record) {
  if (!record || record.schemaVersion !== '2.0') {
    throw new InferenceServiceError(
      'UNSUPPORTED_TELEMETRY_SCHEMA',
      'Only telemetry schema 2.0 can be assessed.',
      { retryable: false },
    );
  }
  const fields = [
    'schemaVersion', 'eventId', 'helmetId', 'deviceTimestamp', 'serverReceivedAt',
    'firmwareVersion', 'sensorFaults', 'mq7Raw', 'mq135Raw', 'mq7WarmUp',
    'mq135WarmUp', 'temperatureC', 'humidityPct', 'heatIndexC', 'fallFeatures',
    'samplingRateHz', 'windowSamples', 'windowEndTimestamp',
    'gasInputMode', 'mq7Ratio', 'mq135Ratio', 'gasThresholdConsecutive',
  ];
  const input = Object.fromEntries(fields
    .filter((field) => record[field] !== undefined)
    .map((field) => [field, structuredClone(record[field])]));
  input.gasInputMode ??= 'baselineLearning';
  input.mq7Ratio ??= null;
  input.mq135Ratio ??= null;
  input.gasThresholdConsecutive ??= 0;
  return input;
}

export function createInferenceClient({
  endpoint,
  fetchImpl = globalThis.fetch,
  authorizationHeaderProvider = null,
  allowInsecureLocalhost = false,
  timeoutMs = 10_000,
} = {}) {
  if (typeof fetchImpl !== 'function') throw new TypeError('A fetch implementation is required.');
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 100 || timeoutMs > 60_000) {
    throw new TypeError('timeoutMs must be between 100 and 60000.');
  }

  return Object.freeze({
    async assess(storedTelemetry) {
      const { audience, url } = resolveEndpoint(endpoint, allowInsecureLocalhost);
      const payload = assessmentInputFromTelemetry(storedTelemetry);
      const headers = { 'content-type': 'application/json' };
      if (authorizationHeaderProvider) {
        const authorization = await authorizationHeaderProvider(audience);
        if (typeof authorization !== 'string' || !authorization.startsWith('Bearer ')) {
          throw new InferenceServiceError(
            'INFERENCE_AUTH_UNAVAILABLE',
            'A private inference identity token could not be obtained.',
          );
        }
        headers.authorization = authorization;
      }

      let response;
      try {
        response = await fetchImpl(url, {
          method: 'POST', headers, body: JSON.stringify(payload),
          signal: AbortSignal.timeout(timeoutMs),
        });
      } catch (error) {
        if (error instanceof InferenceServiceError) throw error;
        throw new InferenceServiceError(
          'INFERENCE_UNAVAILABLE',
          'The private inference service could not be reached.',
        );
      }
      if (!response.ok) {
        throw new InferenceServiceError(
          response.status >= 500 ? 'INFERENCE_UNAVAILABLE' : 'INFERENCE_REJECTED',
          'The private inference service did not accept the telemetry.',
          { retryable: response.status >= 500 || response.status === 429 },
        );
      }
      const declaredLength = Number(response.headers?.get?.('content-length'));
      if (Number.isFinite(declaredLength) && declaredLength > MAX_RESPONSE_BYTES) {
        throw new InferenceServiceError('INFERENCE_RESPONSE_INVALID', 'Inference response is too large.');
      }
      let candidate;
      try {
        const text = await response.text();
        if (Buffer.byteLength(text, 'utf8') > MAX_RESPONSE_BYTES) throw new Error('too large');
        candidate = JSON.parse(text);
      } catch {
        throw new InferenceServiceError(
          'INFERENCE_RESPONSE_INVALID',
          'The private inference response is invalid.',
        );
      }
      let assessment;
      try {
        assessment = validateSafetyAssessment(candidate);
      } catch {
        throw new InferenceServiceError(
          'INFERENCE_RESPONSE_INVALID',
          'The private inference response failed the backend contract.',
          { retryable: false },
        );
      }
      if (assessment.eventId !== payload.eventId || assessment.helmetId !== payload.helmetId) {
        throw new InferenceServiceError(
          'INFERENCE_RESPONSE_MISMATCH',
          'The private inference response does not match its source event.',
          { retryable: false },
        );
      }
      return assessment;
    },
  });
}
