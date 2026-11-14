import { getRuntime } from './runtime.js';

export async function handler(event) {
  try {
    const runtime = await getRuntime();
    return await runtime(event);
  } catch {
    return {
      statusCode: 503,
      headers: {
        'content-type': 'application/json',
        'cache-control': 'no-store',
        'access-control-allow-origin': '*',
      },
      body: JSON.stringify({
        error: {
          code: 'ASSISTANT_UNAVAILABLE',
          message: 'The assistant is temporarily unavailable.',
        },
      }),
    };
  }
}
