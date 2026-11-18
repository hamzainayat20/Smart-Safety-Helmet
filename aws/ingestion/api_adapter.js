import { createAlertFromAssessment } from '../../functions/src/assessment_alerts.js';
import { createAssessmentProcessor } from '../../functions/src/assessment_pipeline.js';
import { createTelemetryIngestionHandler } from '../../functions/src/telemetry_ingestion.js';

function requestBody(event) {
  if (typeof event?.body !== 'string') return Buffer.alloc(0);
  return Buffer.from(event.body, event.isBase64Encoded ? 'base64' : 'utf8');
}

export function apiGatewayRequest(event) {
  const headers = Object.fromEntries(Object.entries(event?.headers ?? {})
    .map(([key, value]) => [key.toLowerCase(), value]));
  const rawBody = requestBody(event);
  return {
    method: event?.requestContext?.http?.method ?? event?.httpMethod ?? '',
    headers,
    rawBody,
    get(name) { return headers[name.toLowerCase()]; },
  };
}

function responseCollector() {
  const state = { statusCode: 200, headers: {} };
  const response = {
    set(name, value) { state.headers[name.toLowerCase()] = value; return response; },
    status(value) { state.statusCode = value; return response; },
    json(value) { state.body = value; return response; },
  };
  return { state, response };
}

function gatewayResponse(state) {
  return {
    statusCode: state.statusCode,
    headers: { 'content-type': 'application/json', ...state.headers },
    body: JSON.stringify(state.body ?? null),
  };
}

export function createAwsTelemetryHandler({
  database,
  secretRegistryValue,
  inferenceClient,
  clock = () => Date.now(),
  alertWriter = createAlertFromAssessment,
}) {
  const ingest = createTelemetryIngestionHandler({
    database,
    secretRegistryValue,
    clock,
  });
  const assess = createAssessmentProcessor({ database, inferenceClient, clock });

  return async function handleApiGatewayEvent(event) {
    const request = apiGatewayRequest(event);
    const { state, response } = responseCollector();
    await ingest(request, response);
    if (state.statusCode >= 400) return gatewayResponse(state);

    let source;
    try {
      const body = JSON.parse(request.rawBody.toString('utf8'));
      source = (await database.ref(`readings/${body.helmetId}/${body.eventId}`).get()).val();
    } catch {
      return gatewayResponse({
        ...state,
        body: { ...state.body, assessmentStatus: 'failed' },
      });
    }

    let assessmentStatus = 'notApplicable';
    try {
      const result = await assess(source);
      assessmentStatus = result.status;
      if (result.status === 'completed' && result.assessment) {
        try {
          // In-app alert record only (no push notification). A failure here
          // never changes the telemetry or assessment outcome.
          await alertWriter({ database, assessment: result.assessment, reading: source, clock });
        } catch {
          // Alert creation is best-effort and must not affect the device.
        }
      }
    } catch {
      // Telemetry has been safely stored. Reporting an assessment failure lets
      // the device retry the same immutable event with a fresh nonce.
      assessmentStatus = 'failed';
    }
    return gatewayResponse({
      ...state,
      body: { ...state.body, assessmentStatus },
    });
  };
}
