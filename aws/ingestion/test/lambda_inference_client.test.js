import assert from 'node:assert/strict';
import test from 'node:test';

import { createLambdaInferenceClient } from '../lambda_inference_client.js';

const now = 1_800_000_000_000;

function telemetry() {
  return {
    schemaVersion: '2.0', eventId: 'event_1', helmetId: 'helmet001',
    deviceTimestamp: now - 100, serverReceivedAt: now,
    firmwareVersion: '0.3.0-staging', sensorFaults: [],
    mq7Raw: 575, mq135Raw: 443, mq7WarmUp: false, mq135WarmUp: false,
    temperatureC: 27, humidityPct: 55, heatIndexC: 28,
    fallFeatures: {
      acc_mean: 1, acc_std: 0.05, acc_min: 0.9, acc_max: 1.1,
      gyro_mean: 1, gyro_std: 0.2, gyro_max: 2,
      jerk_mean: 0.1, jerk_max: 0.3,
    },
    samplingRateHz: 50, windowSamples: 100, windowEndTimestamp: now - 100,
  };
}

function assessment() {
  return {
    schemaVersion: '1.0', assessmentId: 'event_1', eventId: 'event_1',
    helmetId: 'helmet001', sourceSchemaVersion: '2.0',
    deviceTimestamp: now - 100, sourceServerReceivedAt: now, assessedAt: now,
    modelBundleVersion: 'phase-a.1',
    gasInputMode: 'baselineMapped', mq7Ratio: 1, mq135Ratio: 1,
    gasThresholdRisk: 'safe', gasThresholdConsecutive: 0,
    fall: { status: 'evaluated', probability: 0.1, threshold: 0.46, modelVersion: '2.0' },
    gas: {
      status: 'evaluated', classification: 'NoGas', confidence: 0.9,
      probabilities: { Mixture: 0.02, NoGas: 0.9, Perfume: 0.05, Smoke: 0.03 },
      modelVersion: '1.0', outOfDistribution: false,
    },
    environment: {
      status: 'evaluated', temperatureRisk: 'normal',
      humidityRisk: 'normal', heatIndexRisk: 'normal',
    },
    overallRisk: 'safe', reasonCodes: ['GAS_NO_GAS'],
    recommendationCodes: ['NO_IMMEDIATE_ACTION'],
  };
}

test('private Lambda client sends canonical input and validates output', async () => {
  let command;
  const client = createLambdaInferenceClient({
    functionName: 'smart-safety-staging-inference',
    lambdaClient: {
      async send(value) {
        command = value;
        return { Payload: Buffer.from(JSON.stringify(assessment())) };
      },
    },
  });
  const result = await client.assess(telemetry());
  assert.equal(result.overallRisk, 'safe');
  assert.equal(command.input.FunctionName, 'smart-safety-staging-inference');
  const sent = JSON.parse(Buffer.from(command.input.Payload).toString('utf8'));
  assert.equal(sent.eventId, 'event_1');
  assert.equal(sent.gasInputMode, 'baselineLearning');
  assert.equal(sent.mq7Ratio, null);
  assert.equal(sent.connectivity, undefined);
});

test('private Lambda client rejects typed model validation errors', async () => {
  const client = createLambdaInferenceClient({
    functionName: 'smart-safety-staging-inference',
    lambdaClient: {
      async send() {
        return { Payload: Buffer.from(JSON.stringify({
          error: { code: 'INFERENCE_REQUEST_INVALID' },
        })) };
      },
    },
  });
  await assert.rejects(client.assess(telemetry()), { code: 'INFERENCE_REJECTED' });
});
