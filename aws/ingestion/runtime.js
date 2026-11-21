import { LambdaClient } from '@aws-sdk/client-lambda';
import {
  GetParameterCommand,
  SSMClient,
} from '@aws-sdk/client-ssm';
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getDatabase } from 'firebase-admin/database';
import { getMessaging } from 'firebase-admin/messaging';

import { createAwsTelemetryHandler } from './api_adapter.js';
import { createLambdaInferenceClient } from './lambda_inference_client.js';
import { createAlertDelivery } from '../../functions/src/alert_delivery.js';

let runtimePromise;

function requiredEnvironment(name) {
  const value = process.env[name];
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new Error(`Missing required environment configuration: ${name}`);
  }
  return value;
}

async function loadConfiguration() {
  const region = requiredEnvironment('AWS_REGION');
  const parameterName = requiredEnvironment('CONFIGURATION_PARAMETER_NAME');
  const client = new SSMClient({ region });
  const result = await client.send(new GetParameterCommand({
    Name: parameterName,
    WithDecryption: true,
  }));
  if (typeof result.Parameter?.Value !== 'string') {
    throw new Error('AWS configuration parameter must contain a JSON value.');
  }
  const value = JSON.parse(result.Parameter.Value);
  if (!value?.firebaseServiceAccount || !value?.helmetDeviceSecrets) {
    throw new Error('AWS configuration parameter is incomplete.');
  }
  return value;
}

async function buildRuntime() {
  const configuration = await loadConfiguration();
  const databaseURL = requiredEnvironment('FIREBASE_DATABASE_URL');
  const app = getApps()[0] ?? initializeApp({
    credential: cert(configuration.firebaseServiceAccount),
    databaseURL,
  });
  const database = getDatabase(app);
  const alertDelivery = createAlertDelivery({
    database,
    messaging: getMessaging(app),
  });
  const inferenceClient = createLambdaInferenceClient({
    lambdaClient: new LambdaClient({ region: requiredEnvironment('AWS_REGION') }),
    functionName: requiredEnvironment('INFERENCE_FUNCTION_NAME'),
  });
  const secretRegistry = JSON.stringify(configuration.helmetDeviceSecrets);
  return createAwsTelemetryHandler({
    database,
    inferenceClient,
    secretRegistryValue: () => secretRegistry,
    alertDelivery,
  });
}

export function getRuntime() {
  runtimePromise ??= buildRuntime();
  return runtimePromise;
}
