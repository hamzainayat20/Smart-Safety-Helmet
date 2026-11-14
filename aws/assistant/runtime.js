import { GetParameterCommand, SSMClient } from '@aws-sdk/client-ssm';
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getDatabase } from 'firebase-admin/database';

import { createAssistantHandler } from './assistant_service.js';
import { createGroqClient } from './groq_client.js';

let runtimePromise;
const ssmClient = new SSMClient({ region: process.env.AWS_REGION });

function requiredEnvironment(name) {
  const value = process.env[name];
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new Error(`Missing required environment configuration: ${name}`);
  }
  return value;
}

async function getSecureParameter(name) {
  const result = await ssmClient.send(new GetParameterCommand({
    Name: name,
    WithDecryption: true,
  }));
  if (typeof result.Parameter?.Value !== 'string' || result.Parameter.Value.length === 0) {
    throw new Error('Encrypted configuration parameter is unavailable.');
  }
  return result.Parameter.Value;
}

async function buildRuntime() {
  const [configurationJson, groqApiKey] = await Promise.all([
    getSecureParameter(requiredEnvironment('CONFIGURATION_PARAMETER_NAME')),
    getSecureParameter(requiredEnvironment('GROQ_API_KEY_PARAMETER_NAME')),
  ]);
  const configuration = JSON.parse(configurationJson);
  if (!configuration?.firebaseServiceAccount) {
    throw new Error('Firebase configuration is incomplete.');
  }
  const app = getApps()[0] ?? initializeApp({
    credential: cert(configuration.firebaseServiceAccount),
    databaseURL: requiredEnvironment('FIREBASE_DATABASE_URL'),
  });
  return createAssistantHandler({
    auth: getAuth(app),
    database: getDatabase(app),
    groqClient: createGroqClient({
      apiKey: groqApiKey,
      model: requiredEnvironment('GROQ_MODEL'),
    }),
  });
}

export function getRuntime() {
  runtimePromise ??= buildRuntime();
  return runtimePromise;
}
