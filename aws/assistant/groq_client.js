export function createGroqClient({ apiKey, model, fetchImpl = fetch }) {
  if (typeof apiKey !== 'string' || apiKey.length < 20) {
    throw new Error('Groq API key is unavailable.');
  }
  if (typeof model !== 'string' || model.length === 0) {
    throw new Error('Groq model is unavailable.');
  }
  return {
    async complete(messages) {
      const response = await fetchImpl('https://api.groq.com/openai/v1/chat/completions', {
        method: 'POST',
        headers: {
          authorization: `Bearer ${apiKey}`,
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          model,
          messages,
          temperature: 0.1,
          max_completion_tokens: 500,
        }),
        signal: AbortSignal.timeout(15_000),
      });
      if (!response.ok) throw new Error(`Groq request failed with status ${response.status}.`);
      const payload = await response.json();
      const content = payload?.choices?.[0]?.message?.content;
      if (typeof content !== 'string' || content.trim().length === 0) {
        throw new Error('Groq returned an empty response.');
      }
      return content.trim();
    },
  };
}
