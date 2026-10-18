import { persistSafetyAssessment } from './assessment_storage.js';
import { InferenceServiceError } from './inference_client.js';

export class AssessmentPipelineError extends Error {
  constructor(code, message, { retryable = true, cause } = {}) {
    super(message, { cause });
    this.name = 'AssessmentPipelineError';
    this.code = code;
    this.retryable = retryable;
  }
}

function safeFailureCode(error) {
  if (error instanceof InferenceServiceError || error instanceof AssessmentPipelineError) {
    return error.code;
  }
  return 'ASSESSMENT_PIPELINE_FAILED';
}

export function createAssessmentProcessor({ database, inferenceClient, clock = () => Date.now() }) {
  if (!database?.ref) throw new TypeError('A Firebase Realtime Database instance is required.');
  if (!inferenceClient?.assess) throw new TypeError('An inference client is required.');

  return async function processStoredTelemetry(record) {
    if (!record || record.schemaVersion !== '2.0') {
      return { status: 'notApplicable', duplicate: false, assessment: null };
    }
    const jobReference = database.ref(`assessmentJobs/${record.helmetId}/${record.eventId}`);
    const existing = (await database.ref(
      `assessments/${record.helmetId}/${record.eventId}`,
    ).get()).val();
    if (existing) {
      await jobReference.update({ status: 'completed', completedAt: existing.assessedAt });
      return { status: 'completed', duplicate: true, assessment: existing };
    }

    const startedAt = clock();
    await jobReference.transaction((current) => ({
      status: 'processing',
      attemptCount: (Number.isSafeInteger(current?.attemptCount) ? current.attemptCount : 0) + 1,
      firstAttemptAt: Number.isSafeInteger(current?.firstAttemptAt)
        ? current.firstAttemptAt
        : startedAt,
      lastAttemptAt: startedAt,
      lastErrorCode: null,
    }));

    try {
      const candidate = await inferenceClient.assess(record);
      const result = await persistSafetyAssessment(database, candidate);
      await jobReference.update({
        status: 'completed', completedAt: clock(), lastErrorCode: null,
      });
      return { status: 'completed', ...result };
    } catch (error) {
      const code = safeFailureCode(error);
      await jobReference.update({
        status: 'failed', failedAt: clock(), lastErrorCode: code,
      });
      throw new AssessmentPipelineError(
        code,
        'The telemetry assessment could not be completed.',
        { retryable: error?.retryable !== false, cause: error },
      );
    }
  };
}

export function createAssessmentEventHandler({ processor, logger = console }) {
  if (typeof processor !== 'function') throw new TypeError('An assessment processor is required.');
  return async function handleAssessmentEvent(event) {
    const record = event?.data?.val?.();
    if (!record) return null;
    if (record.schemaVersion !== '2.0') return { status: 'notApplicable' };
    if (record.helmetId !== event.params?.helmetId || record.eventId !== event.params?.eventId) {
      logger.error?.('Telemetry assessment rejected', {
        helmetId: event.params?.helmetId,
        eventId: event.params?.eventId,
        code: 'ASSESSMENT_SOURCE_PATH_MISMATCH',
        retryable: false,
      });
      return { status: 'rejected', code: 'ASSESSMENT_SOURCE_PATH_MISMATCH' };
    }
    try {
      return await processor(record);
    } catch (error) {
      logger.error?.('Telemetry assessment failed', {
        helmetId: event.params.helmetId,
        eventId: event.params.eventId,
        code: safeFailureCode(error),
        retryable: error?.retryable !== false,
      });
      if (error?.retryable === false) {
        return { status: 'failed', code: safeFailureCode(error) };
      }
      throw error;
    }
  };
}
