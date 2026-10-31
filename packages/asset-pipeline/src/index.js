export { createDeepSeekClient, DEEPSEEK_DEFAULTS, DeepSeekError } from "./deepseek.js";
export { parseReply, recolourDefault, runDesignJob, writeSpec } from "./design.js";
export { createMockClient, MOCK_DESIGNS, SAMPLE_RUNS } from "./mock.js";
export { extractPalette, normaliseDrawing, UnsupportedFileError } from "./normalise.js";
export {
  buildMessages,
  catalogText,
  EXAMPLES,
  PROMPT_VERSION,
  REJECT_MESSAGES,
  SYSTEM_PROMPT,
} from "./prompt.js";
