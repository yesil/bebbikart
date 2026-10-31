// Claude design client (Anthropic Messages API). Same interface as the DeepSeek client the passes
// were written for: complete(messages, opts) → reply text. The key comes from ANTHROPIC_API_KEY and
// is never logged or written to disk. No fallback: a missing key, an API error or a refusal fails
// the job with the reason.
import Anthropic from "@anthropic-ai/sdk";

export const CLAUDE_DEFAULTS = {
  model: "claude-sonnet-5-5",
  effort: "high",
  maxTokens: 32_000,
  timeoutMs: 180_000,
};

export class ClaudeError extends Error {}

/**
 * @param {{ apiKey?: string, model?: string, effort?: string, timeoutMs?: number }} [opts]
 * @returns {{ name: string, complete: (messages: object[], opts?: { effort?: string }) => Promise<string> }}
 */
export function createClaudeClient(opts = {}) {
  const env = process.env;
  const apiKey = opts.apiKey ?? env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new ClaudeError("ANTHROPIC_API_KEY is not set");
  const model = opts.model ?? env.CLAUDE_DESIGN_MODEL ?? CLAUDE_DEFAULTS.model;
  const defaultEffort = opts.effort ?? env.CLAUDE_EFFORT ?? CLAUDE_DEFAULTS.effort;
  const client = new Anthropic({
    apiKey,
    timeout: opts.timeoutMs ?? CLAUDE_DEFAULTS.timeoutMs,
    maxRetries: 2,
  });

  return {
    name: `claude:${model}`,
    async complete(messages, { effort = defaultEffort } = {}) {
      const { system, turns } = toClaudeMessages(messages);
      let msg;
      try {
        msg = await client.messages
          .stream({
            model,
            max_tokens: CLAUDE_DEFAULTS.maxTokens,
            thinking: { type: "adaptive" },
            output_config: { effort },
            // The system prompts (kit catalog, schema, rules) repeat across passes and racers.
            system: [{ type: "text", text: system, cache_control: { type: "ephemeral" } }],
            messages: turns,
          })
          .finalMessage();
      } catch (err) {
        if (err instanceof Anthropic.AuthenticationError)
          throw new ClaudeError(`${model}: invalid ANTHROPIC_API_KEY (${err.message})`);
        if (err instanceof Anthropic.APIError)
          throw new ClaudeError(`${model} HTTP ${err.status ?? "?"}: ${err.message}`);
        throw new ClaudeError(`${model} request failed: ${err.message}`);
      }
      if (msg.stop_reason === "refusal")
        throw new ClaudeError(
          `${model} declined (${msg.stop_details?.category ?? "no category"}): ${msg.stop_details?.explanation ?? ""}`,
        );
      if (msg.stop_reason === "max_tokens")
        throw new ClaudeError(
          `${model} reply was cut off (max_tokens ${CLAUDE_DEFAULTS.maxTokens})`,
        );
      const text = msg.content
        .filter((b) => b.type === "text")
        .map((b) => b.text)
        .join("");
      if (!text) throw new ClaudeError(`${model} reply has no text`);
      return text;
    },
  };
}

/**
 * The passes build OpenAI-style chat messages ({role: "system"}, image_url data URLs); this turns
 * them into a Claude system prompt and user turns with base64 image blocks.
 */
export function toClaudeMessages(messages) {
  const system = messages
    .filter((m) => m.role === "system")
    .map((m) => m.content)
    .join("\n\n");
  const turns = messages
    .filter((m) => m.role !== "system")
    .map((m) => ({
      role: m.role,
      content:
        typeof m.content === "string"
          ? m.content
          : m.content.map((part) => {
              if (part.type === "text") return { type: "text", text: part.text };
              if (part.type === "image_url") {
                const match = /^data:(image\/(?:jpeg|png|gif|webp));base64,(.+)$/.exec(
                  part.image_url.url,
                );
                if (!match) throw new ClaudeError("image is not a base64 data URL");
                return {
                  type: "image",
                  source: { type: "base64", media_type: match[1], data: match[2] },
                };
              }
              throw new ClaudeError(`unsupported message part "${part.type}"`);
            }),
    }));
  return { system, turns };
}
