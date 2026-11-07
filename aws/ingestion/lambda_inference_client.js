import { InvokeCommand } from '@aws-sdk/client-lambda';

import {
  assessmentInputFromTelemetry,
  InferenceServiceError,
} from '../../functions/src/inference_client.js';
import { validateSafetyAssessment } from '../../functions/src/assessment_contract.js';

const decoder = new TextDecoder();

export function createLambdaInferenceClient({ lambdaClient, functionName }) {
  if (!lambdaClient?.send) throw new TypeError('An AWS Lambda client is required.');
  if (typeof functionName !== 'string' || functionName.trim().length === 0) {
    throw new TypeError('An inference Lambda function name is required.');
  }

  return Object.freeze({
    async assess(storedTelemetry) {
      const payload = assessmentInputFromTelemetry(storedTelemetry);
      let result;
      try {
        result = await lambdaClient.send(new InvokeCommand({
          FunctionName: functionName,
          InvocationType: 'RequestResponse',
          Payload: Buffer.from(JSON.stringify(payload)),
        }));
      } catch {
        throw new InferenceServiceError(
          'INFERENCE_UNAVAILABLE',
          'The private inference Lambda could not be invoked.',
        );
      }
      if (result?.FunctionError || !result?.Payload) {
        throw new InferenceServiceError(
          'INFERENCE_UNAVAILABLE',
          'The private inference Lambda failed.',
        );
      }

      let candidate;
      try {
        candidate = JSON.parse(decoder.decode(result.Payload));
      } catch {
        throw new InferenceServiceError(
          'INFERENCE_RESPONSE_INVALID',
          'The private inference Lambda returned invalid JSON.',
          { retryable: false },
        );
      }
      if (candidate?.error) {
        throw new InferenceServiceError(
          candidate.error.code === 'INFERENCE_REQUEST_INVALID'
            ? 'INFERENCE_REJECTED'
            : 'INFERENCE_RESPONSE_INVALID',
          'The private inference Lambda rejected the request.',
          { retryable: false },
        );
      }

      let assessment;
      try {
        assessment = validateSafetyAssessment(candidate);
      } catch {
        throw new InferenceServiceError(
          'INFERENCE_RESPONSE_INVALID',
          'The private inference Lambda response failed the backend contract.',
          { retryable: false },
        );
      }
      if (assessment.eventId !== payload.eventId ||
          assessment.helmetId !== payload.helmetId) {
        throw new InferenceServiceError(
          'INFERENCE_RESPONSE_MISMATCH',
          'The private inference Lambda response does not match its source event.',
          { retryable: false },
        );
      }
      return assessment;
    },
  });
}
