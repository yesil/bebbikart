// DeepSeek chat-completions client (OpenAI-compatible). The key comes from DEEPSEEK_API_KEY and is
// never logged or written to disk.

export const DEEPSEEK_DEFAULTS = {
  baseUrl: "https://api.deepseek.com",
  // Model named in asset-pipeline.md. Override with DEEPSEEK_MODEL if the vision model has another id.
  model: "deepseek-v4-flash-vision-exp",
  timeoutMs: 90_000,
};

export class DeepSeekError extends Error {}

/**
 * @param {{ apiKey?: string, baseUrl?: string, model?: string, timeoutMs?: number, fetch?: typeof fetch }} [opts]
 * @returns {{ name: string, complete: (messages: object[], opts?: { temperature?: number }) => Promise<string> }}
 */
export function createDeepSeekClient(opts = {}) {
  const env = process.env;
  const apiKey = opts.apiKey ?? env.DEEPSEEK_API_KEY;
  if (!apiKey) throw new DeepSeekError("DEEPSEEK_API_KEY is not set");
  const baseUrl = (opts.baseUrl ?? env.DEEPSEEK_BASE_URL ?? DEEPSEEK_DEFAULTS.baseUrl).replace(
    /\/$/,
    "",
  );
  const model = opts.model ?? env.DEEPSEEK_MODEL ?? DEEPSEEK_DEFAULTS.model;
  const timeoutMs = opts.timeoutMs ?? DEEPSEEK_DEFAULTS.timeoutMs;
  const doFetch = opts.fetch ?? fetch;
  // Thinking mode is slow; off by default. DEEPSEEK_THINKING=enabled turns it on, "omit" leaves the field out.
  const thinking = env.DEEPSEEK_THINKING ?? "disabled";

  return {
    name: `deepseek:${model}`,
    async complete(messages, { temperature = 0.8 } = {}) {
      const body = {
        model,
        messages,
        response_format: { type: "json_object" },
        temperature,
        max_tokens: 4000,
        stream: false,
        ...(thinking === "omit" ? {} : { thinking: { type: thinking } }),
      };
      let res;
      try {
        res = await doFetch(`${baseUrl}/chat/completions`, {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
          body: JSON.stringify(body),
          signal: AbortSignal.timeout(timeoutMs),
        });
      } catch (err) {
        throw new DeepSeekError(`request failed: ${err.message}`);
      }
      if (!res.ok) {
        const text = (await res.text().catch(() => "")).slice(0, 500);
        throw new DeepSeekError(`HTTP ${res.status}: ${text}`);
      }
      const json = await res.json();
      const choice = json.choices?.[0];
      if (choice?.finish_reason === "length")
        throw new DeepSeekError("reply was cut off (max_tokens)");
      const content = choice?.message?.content;
      if (typeof content !== "string") throw new DeepSeekError("reply has no message content");
      return content;
    },
  };
}
