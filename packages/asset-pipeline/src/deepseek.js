// DeepSeek chat-completions client (OpenAI-compatible). The key comes from DEEPSEEK_API_KEY and is
// never logged or written to disk.

export const DEEPSEEK_DEFAULTS = {
  baseUrl: "https://api.deepseek.com",
  // Looks at the photos (look + critique passes): the vision model, thinking at max effort.
  visionModel: "deepseek-flash",
  // Writes the spec (design + refine passes). deepseek-v4-pro gave no better designs in a side-by-side
  // test and was 2–4× slower (166–271 s per design), so the flash model with thinking it is.
  designModel: "deepseek-flash",
  timeoutMs: 150_000,
};

export class DeepSeekError extends Error {}

/**
 * @param {{ apiKey?: string, baseUrl?: string, visionModel?: string, designModel?: string, timeoutMs?: number, fetch?: typeof fetch }} [opts]
 * @returns {{ name: string, complete: (messages: object[], opts?: CompleteOpts) => Promise<string> }}
 * @typedef {{ vision?: boolean, temperature?: number, effort?: "off"|"low"|"high"|"max", maxTokens?: number }} CompleteOpts
 * effort "off" disables thinking.
 */
export function createDeepSeekClient(opts = {}) {
  const env = process.env;
  const apiKey = opts.apiKey ?? env.DEEPSEEK_API_KEY;
  if (!apiKey) throw new DeepSeekError("DEEPSEEK_API_KEY is not set");
  const baseUrl = (opts.baseUrl ?? env.DEEPSEEK_BASE_URL ?? DEEPSEEK_DEFAULTS.baseUrl).replace(
    /\/$/,
    "",
  );
  const visionModel =
    opts.visionModel ?? env.DEEPSEEK_VISION_MODEL ?? DEEPSEEK_DEFAULTS.visionModel;
  const designModel =
    opts.designModel ?? env.DEEPSEEK_DESIGN_MODEL ?? DEEPSEEK_DEFAULTS.designModel;
  const timeoutMs =
    opts.timeoutMs ?? Number(env.DEEPSEEK_TIMEOUT_MS ?? DEEPSEEK_DEFAULTS.timeoutMs);
  const doFetch = opts.fetch ?? fetch;

  return {
    name: `deepseek:${visionModel}+${designModel}`,
    async complete(
      messages,
      { vision = false, temperature = 0.8, effort = "high", maxTokens = 32_000 } = {},
    ) {
      const model = vision ? visionModel : designModel;
      const body = {
        model,
        messages,
        response_format: { type: "json_object" },
        temperature,
        max_tokens: maxTokens,
        stream: false,
        ...(effort === "off"
          ? { thinking: { type: "disabled" } }
          : { thinking: { type: "enabled" }, reasoning_effort: effort }),
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
        throw new DeepSeekError(`${model} request failed: ${err.message}`);
      }
      if (!res.ok) {
        const text = (await res.text().catch(() => "")).slice(0, 500);
        throw new DeepSeekError(`${model} HTTP ${res.status}: ${text}`);
      }
      const json = await res.json();
      const choice = json.choices?.[0];
      if (choice?.finish_reason === "length")
        throw new DeepSeekError(`${model} reply was cut off (max_tokens ${maxTokens})`);
      const content = choice?.message?.content;
      if (typeof content !== "string")
        throw new DeepSeekError(`${model} reply has no message content`);
      return content;
    },
  };
}
