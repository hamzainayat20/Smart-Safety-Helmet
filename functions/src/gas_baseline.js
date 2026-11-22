export const GAS_BASELINE_INITIAL_SAMPLES = 12;
export const GAS_BASELINE_ALPHA = 0.004;

const GAS_BASELINE_MAX_RATIO = 1.10;
const MQ7_WARNING_RATIO = 1.12;
const MQ135_WARNING_RATIO = 1.20;

function validReading(reading) {
  return reading?.schemaVersion === '2.0' &&
    Number.isInteger(reading.mq7Raw) && reading.mq7Raw > 0 && reading.mq7Raw <= 4095 &&
    Number.isInteger(reading.mq135Raw) && reading.mq135Raw > 0 && reading.mq135Raw <= 4095 &&
    reading.mq7WarmUp === false && reading.mq135WarmUp === false;
}

function validBaseline(value) {
  return value && Number.isFinite(value.mq7) && value.mq7 > 0 &&
    Number.isFinite(value.mq135) && value.mq135 > 0 &&
    Number.isSafeInteger(value.samples) && value.samples > 0;
}

function nextBaseline(current, reading) {
  if (!validReading(reading)) return undefined;
  if (!validBaseline(current)) {
    return {
      mq7: reading.mq7Raw,
      mq135: reading.mq135Raw,
      samples: 1,
      updatedAt: reading.serverReceivedAt,
    };
  }
  if (Number.isSafeInteger(current.updatedAt) &&
      reading.serverReceivedAt <= current.updatedAt) {
    return undefined;
  }
  if (current.samples < GAS_BASELINE_INITIAL_SAMPLES) {
    const samples = current.samples + 1;
    return {
      mq7: current.mq7 + ((reading.mq7Raw - current.mq7) / samples),
      mq135: current.mq135 + ((reading.mq135Raw - current.mq135) / samples),
      samples,
      updatedAt: reading.serverReceivedAt,
    };
  }
  if (reading.mq7Raw > current.mq7 * GAS_BASELINE_MAX_RATIO ||
      reading.mq135Raw > current.mq135 * GAS_BASELINE_MAX_RATIO) {
    return undefined;
  }
  return {
    mq7: current.mq7 + GAS_BASELINE_ALPHA * (reading.mq7Raw - current.mq7),
    mq135: current.mq135 + GAS_BASELINE_ALPHA * (reading.mq135Raw - current.mq135),
    samples: current.samples + 1,
    updatedAt: reading.serverReceivedAt,
  };
}

function clampAdc(value) {
  return Math.max(0, Math.min(4095, Math.round(value)));
}

function warningRise(mq7Ratio, mq135Ratio) {
  return mq7Ratio >= MQ7_WARNING_RATIO || mq135Ratio >= MQ135_WARNING_RATIO;
}

export async function prepareGasAssessmentInput({ database, reading, updateBaseline = true }) {
  if (!reading || typeof reading.helmetId !== 'string') return reading;
  const baselineRef = database.ref(`helmets/${reading.helmetId}/gasBaseline`);
  let baseline;
  if (updateBaseline && validReading(reading)) {
    const result = await baselineRef.transaction((current) => nextBaseline(current, reading));
    baseline = result.snapshot.val();
  } else {
    baseline = (await baselineRef.get()).val();
  }

  if (!validReading(reading) || !validBaseline(baseline) ||
      baseline.samples < GAS_BASELINE_INITIAL_SAMPLES) {
    return {
      ...reading,
      gasInputMode: 'baselineLearning',
      mq7Ratio: null,
      mq135Ratio: null,
      gasThresholdConsecutive: 0,
    };
  }

  const mq7Ratio = reading.mq7Raw / baseline.mq7;
  const mq135Ratio = reading.mq135Raw / baseline.mq135;
  let gasThresholdConsecutive = 0;
  if (warningRise(mq7Ratio, mq135Ratio)) {
    const previous = (await database.ref(`helmets/${reading.helmetId}/currentAssessment`).get()).val();
    const priorRise = previous?.gasInputMode === 'baselineMapped' &&
      Number.isFinite(previous.mq7Ratio) && Number.isFinite(previous.mq135Ratio) &&
      warningRise(previous.mq7Ratio, previous.mq135Ratio) &&
      previous.eventId !== reading.eventId &&
      Number.isSafeInteger(previous.deviceTimestamp) &&
      previous.deviceTimestamp <= reading.deviceTimestamp;
    gasThresholdConsecutive = priorRise
      ? Math.max(1, Number(previous.gasThresholdConsecutive) || 1) + 1
      : 1;
  }

  return {
    ...reading,
    mq7Raw: clampAdc(610 * baseline.mq7 / reading.mq7Raw),
    mq135Raw: clampAdc(470 * baseline.mq135 / reading.mq135Raw),
    gasInputMode: 'baselineMapped',
    mq7Ratio,
    mq135Ratio,
    gasThresholdConsecutive,
  };
}

export const __test = Object.freeze({ nextBaseline, validBaseline, validReading });
