// SQLite persistence (bun:sqlite). Each table holds JSON documents keyed by id; the server keeps
// everything in memory and writes through, so a restart or reload keeps players and the leaderboard.
import { Database } from "bun:sqlite";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";

const TABLES = ["session", "device", "player", "build", "run", "asset_job", "best_trace"];

export function openDb(file) {
  if (file !== ":memory:") mkdirSync(dirname(file), { recursive: true });
  const db = new Database(file, { create: true });
  db.exec("PRAGMA journal_mode = WAL;");
  for (const t of TABLES) {
    db.exec(`CREATE TABLE IF NOT EXISTS ${t} (id TEXT PRIMARY KEY, data TEXT NOT NULL)`);
  }
  const stmts = Object.fromEntries(
    TABLES.map((t) => [
      t,
      {
        put: db.prepare(`INSERT OR REPLACE INTO ${t} (id, data) VALUES (?, ?)`),
        del: db.prepare(`DELETE FROM ${t} WHERE id = ?`),
        all: db.prepare(`SELECT data FROM ${t}`),
        clear: db.prepare(`DELETE FROM ${t}`),
      },
    ]),
  );
  return {
    put: (t, doc) => stmts[t].put.run(doc.id, JSON.stringify(doc)),
    del: (t, id) => stmts[t].del.run(id),
    all: (t) => stmts[t].all.all().map((r) => JSON.parse(r.data)),
    clear: (t) => stmts[t].clear.run(),
    close: () => db.close(),
  };
}
