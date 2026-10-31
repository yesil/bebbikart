/** An error with a contract error code (contracts §7 "Error codes") and an HTTP status. */
export class ApiError extends Error {
  constructor(code, message, status = 400) {
    super(message);
    this.code = code;
    this.status = status;
  }
}

/** Tiny nickname filter: trims and masks a few words kids' parents won't want on the big screen. */
const BAD = [
  "fuck",
  "shit",
  "bitch",
  "cunt",
  "dick",
  "piss",
  "arsch",
  "fick",
  "scheiss",
  "scheiß",
  "hure",
  "wichser",
  "nazi",
  "hitler",
];
export function cleanNickname(raw) {
  let s = String(raw ?? "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 16);
  for (const w of BAD) s = s.replace(new RegExp(w, "gi"), (m) => "*".repeat(m.length));
  return s;
}
