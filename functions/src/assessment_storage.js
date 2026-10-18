import { validateSafetyAssessment } from './assessment_contract.js';

export class AssessmentStorageError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'AssessmentStorageError';
    this.code = code;
  }
}

function stableJson(value) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stableJson).join(',')}]`;
  return `{${Object.keys(value).sort().map((key) =>
    `${JSON.stringify(key)}:${stableJson(value[key])}`).join(',')}}`;
}

export function incomingAssessmentShouldReplaceCurrent(current, incoming) {
  if (!current || typeof current !== 'object') return true;
  if (incoming.deviceTimestamp !== current.deviceTimestamp) {
    return incoming.deviceTimestamp > current.deviceTimestamp;
  }
  if (typeof current.eventId !== 'string') return true;
  return incoming.eventId > current.eventId;
}

export async function persistSafetyAssessment(database, candidate) {
  if (!database?.ref) throw new TypeError('A Firebase Realtime Database instance is required.');
  const assessment = validateSafetyAssessment(candidate);
  const source = (await database.ref(
    `readings/${assessment.helmetId}/${assessment.eventId}`,
  ).get()).val();
  if (!source) {
    throw new AssessmentStorageError(
      'ASSESSMENT_SOURCE_NOT_FOUND',
      'The source telemetry event does not exist.',
    );
  }
  if (source.eventId !== assessment.eventId ||
      source.helmetId !== assessment.helmetId ||
      source.schemaVersion !== assessment.sourceSchemaVersion ||
      source.deviceTimestamp !== assessment.deviceTimestamp ||
      source.serverReceivedAt !== assessment.sourceServerReceivedAt) {
    throw new AssessmentStorageError(
      'ASSESSMENT_SOURCE_MISMATCH',
      'The assessment does not match its source telemetry event.',
    );
  }
  const historyReference = database.ref(
    `assessments/${assessment.helmetId}/${assessment.eventId}`,
  );
  const history = await historyReference.transaction((current) =>
    current ? undefined : assessment);
  const stored = history.snapshot.val();
  if (stableJson(stored) !== stableJson(assessment)) {
    throw new AssessmentStorageError(
      'ASSESSMENT_EVENT_CONFLICT',
      'The event ID is already associated with a different assessment.',
    );
  }

  const currentReference = database.ref(
    `helmets/${assessment.helmetId}/currentAssessment`,
  );
  await currentReference.transaction((current) =>
    incomingAssessmentShouldReplaceCurrent(current, assessment)
      ? assessment
      : undefined);

  return {
    assessment: stored,
    duplicate: history.committed === false,
  };
}
