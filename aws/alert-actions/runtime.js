import { GetParameterCommand, SSMClient } from '@aws-sdk/client-ssm';
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getDatabase } from 'firebase-admin/database';
import { getMessaging } from 'firebase-admin/messaging';

import { createAlertActionsHandler } from './alert_actions_service.js';

let runtimePromise;
const ssmClient = new SSMClient({ region: process.env.AWS_REGION });

function requiredEnvironment(name) {
  const value = process.env[name];
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new Error(`Missing required environment configuration: ${name}`);
  }
  return value;
}

async function buildRuntime() {
  const result = await ssmClient.send(new GetParameterCommand({
    Name: requiredEnvironment('CONFIGURATION_PARAMETER_NAME'),
    WithDecryption: true,
  }));
  if (typeof result.Parameter?.Value !== 'string' || result.Parameter.Value.length === 0) {
    throw new Error('Encrypted configuration parameter is unavailable.');
  }
  const configuration = JSON.parse(result.Parameter.Value);
  if (!configuration?.firebaseServiceAccount) {
    throw new Error('Firebase configuration is incomplete.');
  }
  const app = getApps()[0] ?? initializeApp({
    credential: cert(configuration.firebaseServiceAccount),
    databaseURL: requiredEnvironment('FIREBASE_DATABASE_URL'),
  });
  return createAlertActionsHandler({
    auth: getAuth(app),
    database: getDatabase(app),
    messaging: getMessaging(app),
  });
}

export function getRuntime() {
  runtimePromise ??= buildRuntime();
  return runtimePromise;
}
