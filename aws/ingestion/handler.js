import { getRuntime } from './runtime.js';

export async function handler(event) {
  try {
    const runtime = await getRuntime();
    return await runtime(event);
  } catch {
    // Never leak Firebase credentials, device secrets, or provider errors.
    return {
      statusCode: 503,
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        error: {
          code: 'SERVICE_UNAVAILABLE',
          message: 'Telemetry service is temporarily unavailable.',
        },
      }),
    };
  }
}
