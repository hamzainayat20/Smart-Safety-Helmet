import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getDatabase } from 'firebase-admin/database';

import { createAssessmentProcessor } from '../src/assessment_pipeline.js';
import { createInferenceClient } from '../src/inference_client.js';

const projectId = process.env.GCLOUD_PROJECT ?? 'smart-safety-phase-b-test';
if (!process.env.FIREBASE_DATABASE_EMULATOR_HOST) {
  throw new Error('Run this script through firebase emulators:exec with the database emulator.');
}

const functionsDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const serviceDir = path.resolve(functionsDir, '..', 'inference_service');
const python = process.env.PHASE_B_PYTHON ?? (process.platform === 'win32' ? 'python.exe' : 'python3');
const port = Number(process.env.PHASE_B_INFERENCE_PORT ?? 18765);
const endpoint = `http://127.0.0.1:${port}`;
const server = spawn(
  python,
  ['-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', String(port)],
  { cwd: serviceDir, stdio: ['ignore', 'pipe', 'pipe'] },
);
let serverDiagnostics = '';
server.stdout.on('data', (chunk) => { serverDiagnostics += chunk.toString(); });
server.stderr.on('data', (chunk) => { serverDiagnostics += chunk.toString(); });

async function waitUntilHealthy() {
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    if (server.exitCode !== null) break;
    try {
      const response = await fetch(`${endpoint}/health`);
      if (response.ok) return response.json();
    } catch {
      // The local server is still starting and loading verified models.
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`Inference service did not become healthy.\n${serverDiagnostics}`);
}

const timestamp = 1_800_000_000_000;
const record = {
  schemaVersion: '2.0', eventId: 'phase_b_smoke_0001', helmetId: 'helmet001',
  deviceTimestamp: timestamp, serverReceivedAt: timestamp + 10,
  firmwareVersion: 'phase-b-simulator.1', sensorFaults: [],
  mq7Raw: 575, mq135Raw: 443, mq7WarmUp: false, mq135WarmUp: false,
  temperatureC: 27, humidityPct: 55, heatIndexC: 28,
  fallFeatures: {
    acc_mean: 1, acc_std: 0.05, acc_min: 0.9, acc_max: 1.1,
    gyro_mean: 1, gyro_std: 0.2, gyro_max: 2,
    jerk_mean: 0.1, jerk_max: 0.3,
  },
  samplingRateHz: 50, windowSamples: 100, windowEndTimestamp: timestamp,
  connectivity: 'online', severity: 'unassessed',
};

const app = initializeApp({
  projectId,
  databaseURL: `https://${projectId}-default-rtdb.firebaseio.com`,
});
const database = getDatabase(app);

try {
  const health = await waitUntilHealthy();
  assert.equal(health.modelsLoaded, true);
  await database.ref(`readings/${record.helmetId}/${record.eventId}`).set(record);
  const processor = createAssessmentProcessor({
    database,
    inferenceClient: createInferenceClient({
      endpoint, allowInsecureLocalhost: true, timeoutMs: 20_000,
    }),
  });
  const first = await processor(record);
  assert.equal(first.status, 'completed');
  assert.equal(first.duplicate, false);
  const [history, current, job] = (await Promise.all([
    database.ref(`assessments/${record.helmetId}/${record.eventId}`).get(),
    database.ref(`helmets/${record.helmetId}/currentAssessment`).get(),
    database.ref(`assessmentJobs/${record.helmetId}/${record.eventId}`).get(),
  ])).map((snapshot) => snapshot.val());
  assert.equal(history.eventId, record.eventId);
  assert.equal(current.eventId, record.eventId);
  assert.equal(job.status, 'completed');
  assert.equal(history.sourceServerReceivedAt, record.serverReceivedAt);
  assert.equal(history.assessedAt, record.serverReceivedAt);

  const retry = await processor(record);
  assert.equal(retry.duplicate, true);
  console.log(JSON.stringify({
    result: 'PASS',
    modelBundleVersion: health.modelBundleVersion,
    eventId: history.eventId,
    overallRisk: history.overallRisk,
    fallStatus: history.fall.status,
    gasStatus: history.gas.status,
    assessmentHistoryStored: true,
    currentAssessmentStored: true,
    duplicateWasIdempotent: true,
  }, null, 2));
} finally {
  await deleteApp(app);
  if (server.exitCode === null) server.kill();
}
